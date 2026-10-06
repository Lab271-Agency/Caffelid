import AppKit
import ServiceManagement
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = SleepController()
    private let lidMonitor = LidMonitor()
    private let hardware = HardwareMonitor()
    private let preferences = SafetyPreferences(legacyDefaults: UserDefaults(suiteName: "app.caffelid.mac"))
    private let batteryView = LimitSliderView(kind: .battery)
    private let temperatureView = LimitSliderView(kind: .temperature)
    private let logger = Logger(subsystem: "app.caffelid.desktop", category: "limits")
    private var snapshot = HardwareSnapshot()
    private var safetyPolicy = SafetyPolicy()
    private var lastSafetyReason: SafetyReason?
    private var sampling = false
    private var lastStateCheck: TimeInterval = -.infinity
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let toggleView = MenuToggleView(accessibilityLabel: Strings.text("toggle.label"),
                                            help: Strings.text("toggle.help"))
    private let loginView = MenuToggleView(title: Strings.text("launchAtLogin"),
                                           accessibilityLabel: Strings.text("launchAtLogin"),
                                           help: Strings.text("login.help"))
    private let quitView = QuitButtonView()
    private var active = false
    private var busy = true
    private var pendingActive: Bool?
    private var updatingLogin = false
    private var quitRequested = false
    private var terminating = false
    private var activateWhenApproved = false
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let identifier = Bundle.main.bundleIdentifier else { exit(1) }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            + NSRunningApplication.runningApplications(withBundleIdentifier: "app.caffelid.mac")
        guard !others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) else {
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)
        lidMonitor.onLidChange = { [weak self] closed in
            guard let self else { return }
            if !closed { self.safetyPolicy.reset() }
            Task { await self.monitor() }
        }
        menu.autoenablesItems = false
        menu.delegate = self
        toggleView.onChange = { [weak self] in self?.toggleSleep() }
        loginView.onChange = { [weak self] in self?.toggleLogin() }
        quitView.onQuit = { [weak self] in self?.quit() }
        let title = NSMenuItem()
        title.view = MenuHeaderView()
        menu.addItem(title)
        menu.addItem(.separator())
        let toggleItem = NSMenuItem()
        toggleItem.view = toggleView
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        for view in [batteryView, temperatureView] {
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let loginItem = NSMenuItem()
        loginItem.view = loginView
        menu.addItem(loginItem)
        let quitItem = NSMenuItem()
        quitItem.view = quitView
        menu.addItem(quitItem)
        batteryView.onChange = { [weak self] step in
            guard let self else { return }
            self.preferences.setBatteryStep(step)
            self.updateMenu()
            Task { await self.monitor() }
        }
        temperatureView.onChange = { [weak self] step in
            guard let self else { return }
            self.preferences.setTemperatureStep(step)
            self.updateMenu()
            Task { await self.monitor() }
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.menu = menu
        statusItem = item
        updateMenu()
        Task {
            var failure: Error?
            do {
                try await controller.resetIfNeeded()
                try lidMonitor.start()
            }
            catch { await refreshState(); failure = error }
            snapshot = await hardware.sample()
            finishOperation(failure)
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.monitor() }
        }
        self.timer = timer
        // Menu tracking must not pause the safety checks.
        RunLoop.main.add(timer, forMode: .common)
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
        Task { await monitor() }
    }

    private func monitor() async {
        guard !busy, !terminating, !sampling else { return }
        sampling = true
        defer { sampling = false }
        snapshot = await hardware.sample()
        guard !busy, !terminating else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastStateCheck >= 5 {
            lastStateCheck = now
            await refreshState()
        }
        guard !busy, !terminating else { return }
        if let reason = safetyPolicy.deactivationReason(snapshot, limits: preferences.limits,
            active: active, lidClosed: LidMonitor.currentLidClosed() != false, now: now) {
            busy = true
            activateWhenApproved = false
            updateMenu()
            do {
                try await controller.deactivate()
                active = false
                lastSafetyReason = reason
                safetyPolicy.reset()
                logger.notice("Sleep restored by limit: \(reason.rawValue, privacy: .public)")
            } catch {
                await refreshState()
                logger.error("Limit reached but sleep restoration failed: \(error.localizedDescription, privacy: .public)")
            }
            busy = false
        }
        updateMenu()
        if honorQuitRequest() { return }
        if activateWhenApproved, SupportService.enabled {
            activateWhenApproved = false
            if !active, activationBlock == nil { toggleSleep() }
        }
    }

    private var activationBlock: SafetyReason? {
        SafetyPolicy.activationBlock(snapshot, limits: preferences.limits)
    }

    private var batteryDescription: String {
        let value = snapshot.batteryPercent.map { "\(Int($0.rounded()))%" } ?? Strings.text("limit.unavailable")
        let power = Strings.text(snapshot.powerSupply == .adapter ? "limit.adapter" :
            (snapshot.powerSupply == .battery ? "limit.onBattery" : "limit.powerUnknown"))
        return "\(value) · \(power)"
    }

    private var temperatureDescription: String {
        guard let value = snapshot.temperatureCelsius else { return Strings.text("limit.unavailable") }
        return "CPU / GPU: \(Int(value.rounded())) °C"
    }

    private func updateMenu() {
        lidMonitor.setEnabled(active && !busy && !terminating)
        toggleView.update(active: pendingActive ?? active,
                          available: pendingActive != nil || active || activationBlock == nil,
                          busy: busy, reason: active ? nil : activationBlock?.message)
        batteryView.update(step: preferences.batteryStep, current: batteryDescription, enabled: !terminating)
        temperatureView.update(step: preferences.temperatureStep, current: temperatureDescription, enabled: !terminating)
        let loginStatus = SMAppService.mainApp.status
        // The switch shows the requested choice; pending approval is explained
        // in its tooltip and accessibility help, and can still be cancelled.
        loginView.update(active: loginStatus == .enabled || loginStatus == .requiresApproval,
                         available: !terminating, busy: updatingLogin,
                         reason: loginStatus == .requiresApproval ? Strings.text("login.approval.message") : nil)
        quitView.update(enabled: !terminating)
        let description = "Caffelid — " + Strings.text(active ? "state.active" : "state.inactive")
        let image = NSImage(systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer",
                            accessibilityDescription: description)
        image?.isTemplate = true
        statusItem?.button?.image = image
        let reason = active ? nil : (activationBlock ?? lastSafetyReason)
        statusItem?.button?.toolTip = description + (reason.map { "\n" + $0.message } ?? "")
        statusItem?.button?.setAccessibilityLabel(description)
    }

    private func toggleSleep() {
        guard !busy else { return }
        let wasActive = active
        pendingActive = !wasActive
        busy = true
        updateMenu()
        Task {
            var failure: Error?
            do {
                if wasActive { try await controller.deactivate() }
                else {
                    snapshot = await hardware.sample()
                    if let reason = activationBlock { throw CaffelidError(key: "safety.\(reason.rawValue)") }
                    try lidMonitor.start()
                    try await controller.activate()
                    active = true
                    // Approval or service repair can take time. Check a fresh reading
                    // before confirming activation, even if the lid is already closed.
                    snapshot = await hardware.sample()
                    if let reason = activationBlock {
                        try await controller.deactivate()
                        active = false
                        throw CaffelidError(key: "safety.\(reason.rawValue)")
                    }
                }
                active = !wasActive
                lastSafetyReason = nil
                safetyPolicy.reset()
            } catch {
                await refreshState()
                failure = error
            }
            finishOperation(failure, activateAfterApproval: !wasActive)
        }
    }

    private func toggleLogin() {
        guard !updatingLogin, !terminating else { return }
        updatingLogin = true
        defer { updatingLogin = false; updateMenu() }
        do {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval: try SMAppService.mainApp.unregister()
            default:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    let alert = NSAlert()
                    alert.messageText = Strings.text("login.approval.title")
                    alert.informativeText = Strings.text("login.approval.message")
                    alert.addButton(withTitle: Strings.text("openSettings"))
                    alert.addButton(withTitle: Strings.text("close"))
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
                }
            }
        } catch { showError(CaffelidError(key: "error.login")) }
    }

    private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !busy else {
            quitRequested = true
            return .terminateCancel
        }
        guard active else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        terminating = true
        busy = true
        updateMenu()
        Task {
            do {
                try await controller.deactivate()
                active = false
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                terminating = false
                busy = false
                await refreshState()
                showError(error)
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        lidMonitor.stop()
    }

    private func honorQuitRequest() -> Bool {
        guard quitRequested else { return false }
        quitRequested = false
        NSApp.terminate(nil)
        return true
    }

    private func finishOperation(_ failure: Error?, activateAfterApproval: Bool = false) {
        pendingActive = nil
        busy = false
        updateMenu()
        if honorQuitRequest() { return }
        if let failure { showError(failure, activateAfterApproval: activateAfterApproval) }
    }

    private func refreshState() async {
        do { active = try await controller.check() }
        catch { /* Keep the last confirmed state if macOS cannot be queried. */ }
        updateMenu()
    }

    private func showError(_ error: Error, activateAfterApproval: Bool = false) {
        if let approval = error as? SupportApprovalNeeded {
            let alert = NSAlert()
            alert.messageText = Strings.text(approval.needsRepair ? "support.repair.title" : "support.approval.title")
            alert.informativeText = approval.localizedDescription
            alert.addButton(withTitle: Strings.text("openSettings"))
            alert.addButton(withTitle: Strings.text("close"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                activateWhenApproved = activateAfterApproval
                SMAppService.openSystemSettingsLoginItems()
            } else { activateWhenApproved = false }
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Strings.text("error.title")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: Strings.text("close"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
