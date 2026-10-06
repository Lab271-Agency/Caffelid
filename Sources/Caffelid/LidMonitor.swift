import AppKit
import CoreGraphics
import IOKit
import CaffelidIPC
import OSLog

struct DisplaySleepPolicy {
    private var requested = false

    mutating func shouldSleep(active: Bool, lidClosed: Bool, hasExternalDisplay: Bool) -> Bool {
        guard active, lidClosed, !hasExternalDisplay else {
            requested = false
            return false
        }
        guard !requested else { return false }
        requested = true
        return true
    }
}

@MainActor
final class LidMonitor {
    private let logger = Logger(subsystem: "app.caffelid.desktop", category: "display")
    private var service: io_service_t = 0
    private var notification: io_object_t = 0
    private var port: IONotificationPortRef?
    private var screenObserver: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    var onLidChange: ((Bool) -> Void)?
    private var lastLidClosed: Bool?
    private var enabled = false
    private var policy = DisplaySleepPolicy()

    func start() throws {
        guard port == nil else { return }
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0, let newPort = IONotificationPortCreate(kIOMainPortDefault) else {
            stop()
            throw CaffelidError(key: "error.lid")
        }
        port = newPort
        IONotificationPortSetDispatchQueue(newPort, DispatchQueue.main)
        let result = IOServiceAddInterestNotification(newPort, service, kIOGeneralInterest,
            Self.receiveInterest, Unmanaged.passUnretained(self).toOpaque(), &notification)
        guard result == KERN_SUCCESS, Self.lidClosed(service: service) != nil else {
            stop()
            throw CaffelidError(key: "error.lid")
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        sample()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        enabled = false
        lastLidClosed = nil
        policy = DisplaySleepPolicy()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if notification != 0 { IOObjectRelease(notification); notification = 0 }
        if let port { IONotificationPortDestroy(port) }
        port = nil
        if service != 0 { IOObjectRelease(service); service = 0 }
    }

    nonisolated static func currentLidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return lidClosed(service: root)
    }

    private nonisolated static func lidClosed(service: io_service_t) -> Bool? {
        guard service != 0, let value = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return value as? Bool
    }

    private nonisolated static let receiveInterest: IOServiceInterestCallback = { reference, _, message, _ in
        guard message == caffelid_clamshell_message(), let reference else { return }
        let monitor = Unmanaged<LidMonitor>.fromOpaque(reference).takeUnretainedValue()
        Task { @MainActor [weak monitor] in monitor?.sample() }
    }

    private var hasExternalDisplay: Bool {
        NSScreen.screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return true // Avoid blanking an unknown display configuration.
            }
            return CGDisplayIsBuiltin(id.uint32Value) == 0
        }
    }

    private func sample() {
        guard let closed = Self.lidClosed(service: service) else { return }
        if lastLidClosed != closed {
            lastLidClosed = closed
            onLidChange?(closed)
        }
        if !enabled || !closed || hasExternalDisplay {
            pending?.cancel()
            pending = nil
        }
        guard policy.shouldSleep(active: enabled, lidClosed: closed, hasExternalDisplay: hasExternalDisplay) else {
            return
        }
        pending?.cancel()
        // Let macOS finish the lid transition; cancel if the lid is reopened meanwhile.
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            guard let self, !Task.isCancelled, self.enabled,
                  Self.lidClosed(service: self.service) == true, !self.hasExternalDisplay else { return }
            let success = await Task.detached(priority: .utility) {
                let command = Process()
                command.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                command.arguments = ["displaysleepnow"]
                command.standardOutput = FileHandle.nullDevice
                command.standardError = FileHandle.nullDevice
                do {
                    try command.run()
                    command.waitUntilExit()
                    return command.terminationStatus == 0
                } catch { return false }
            }.value
            if success { self.logger.info("Display sleep requested after lid closure") }
            else { self.logger.error("macOS rejected display sleep after lid closure") }
        }
    }
}
