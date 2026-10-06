import AppKit
import CaffelidIPC
import ServiceManagement

// Read-only hardware diagnostic; does not query or register background services.
if CommandLine.arguments.contains("--sensors") {
    Task {
        let snapshot = await HardwareMonitor().sample()
        let preferences = SafetyPreferences()
        print("Battery: \(snapshot.batteryPercent.map { String($0) } ?? "unavailable")%")
        print("Power source: \(snapshot.powerSupply)")
        print("CPU/GPU maximum: \(snapshot.temperatureCelsius.map { String($0) } ?? "unavailable") °C")
        print("Temperature sensors: \(snapshot.temperatureSensorCount)")
        print("Battery limit: \(preferences.limits.batteryPercent.map { String($0) } ?? "disabled")")
        print("Temperature limit: \(preferences.limits.temperatureCelsius.map { String($0) } ?? "disabled")")
        print("Activation blocked: \(SafetyPolicy.activationBlock(snapshot, limits: preferences.limits)?.rawValue ?? "no")")
        exit(0)
    }
    RunLoop.main.run()
}

// Explicit, opt-in live diagnostic; always restores sleep before returning.
if CommandLine.arguments.contains("--test-cycle") {
    let controller = SleepController()
    Task {
        do {
            guard LidMonitor.currentLidClosed() == false,
                  try !SleepController.systemSleepDisabled(),
                  !(NSRunningApplication.runningApplications(withBundleIdentifier: "app.caffelid.desktop")
                    + NSRunningApplication.runningApplications(withBundleIdentifier: "app.caffelid.mac"))
                    .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) else {
                fputs("Open the lid, deactivate and quit Caffelid before this live test.\n", stderr)
                exit(1)
            }
            if CommandLine.arguments.contains("--repair-support") {
                try await SupportService.repairRegistration()
                print("Support registration refreshed")
            }
            try await controller.activate()
            print("Activation confirmed: SleepDisabled=1")
            try await controller.deactivate()
            print("Deactivation confirmed: SleepDisabled=0")
            exit(0)
        } catch {
            try? await controller.deactivate()
            fputs("Live test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    RunLoop.main.run()
}

if CommandLine.arguments.contains("--check") {
    do {
        let state = try SleepController.systemSleepDisabled()
        print("Build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")")
        print("App identifier: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("SleepDisabled=\(state ? 1 : 0)")
        print("Helper bundled: \(Bundle.main.url(forAuxiliaryExecutable: "CaffelidHelper") != nil)")
        print("Apple signing team available: \(caffelid_signing_team_available() == 1)")
        print("Sleep support approved: \(SupportService.enabled)")
        print("Launch at Login enabled: \(SMAppService.mainApp.status == .enabled)")
        print("Locale: \(Bundle.main.preferredLocalizations.joined(separator: ", "))")
        print("Lid closed: \(LidMonitor.currentLidClosed().map(String.init) ?? "unknown")")
        let monitor = LidMonitor()
        try monitor.start()
        print("Lid notifications: available")
        monitor.stop()
        print("Menu: Caffelid, \(Strings.text("toggle.disabled")) / \(Strings.text("toggle.enabled")), \(Strings.text("limit.battery")), \(Strings.text("limit.temperature")), \(Strings.text("launchAtLogin")), \(Strings.text("quit"))")
        exit(0)
    } catch {
        fputs("Cannot read the system sleep setting.\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
