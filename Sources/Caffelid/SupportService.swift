import Foundation
import ServiceManagement
import CaffelidIPC
import OSLog

struct SupportApprovalNeeded: LocalizedError, Sendable {
    var needsRepair = false
    var errorDescription: String? {
        Strings.text(needsRepair ? "support.repair.message" : "support.approval.message")
    }
}

@MainActor
enum SupportService {
    static let plistName = "app.caffelid.desktop.sleep-service.plist"
    private static let logger = Logger(subsystem: "app.caffelid.desktop", category: "support")
    private static var service: SMAppService { .daemon(plistName: plistName) }

    static var enabled: Bool { service.status == .enabled }

    static func ensureReady() throws {
        guard caffelid_signing_team_available() == 1 else { throw CaffelidError(key: "error.signing") }
        let daemon = service
        if daemon.status == .enabled { return }
        if daemon.status == .requiresApproval { throw SupportApprovalNeeded() }
        try register(daemon)
    }

    private static func register(_ daemon: SMAppService) throws {
        do { try daemon.register() }
        catch {
            // register may throw "not permitted" while correctly awaiting user approval.
            if daemon.status == .requiresApproval { throw SupportApprovalNeeded() }
            let details = error as NSError
            logger.error("Support registration failed: \(details.domain, privacy: .public) / \(details.code)")
            if details.domain == "SMAppServiceErrorDomain", details.code == 1,
               daemon.status == .notRegistered {
                throw SupportApprovalNeeded(needsRepair: true)
            }
            throw CaffelidError(key: "error.registration")
        }
        if daemon.status == .requiresApproval { throw SupportApprovalNeeded() }
        guard daemon.status == .enabled else { throw CaffelidError(key: "error.registration") }
    }

    static func repairRegistration() async throws {
        // Approval describes eligibility, not whether launchd can still resolve
        // the executable after the app has been deleted and copied back.
        let daemon = service
        if daemon.status == .requiresApproval { throw SupportApprovalNeeded() }
        guard daemon.status == .enabled else {
            try ensureReady()
            return
        }
        logger.notice("Approved support did not respond; refreshing its registration")
        do {
            // The async variant waits for termination before re-registration.
            try await daemon.unregister()
        } catch {
            let details = error as NSError
            logger.error("Support unregistration failed: \(details.domain, privacy: .public) / \(details.code)")
            throw CaffelidError(key: "error.registration")
        }
        // macOS may still reject an immediate register after completion. Apple
        // DTS documents this race; allow background permission updates to settle.
        try await Task.sleep(for: .seconds(2))
        try register(daemon)
    }
}
