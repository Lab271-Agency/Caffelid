import Foundation
import Darwin
import CaffelidIPC

struct CaffelidError: LocalizedError, Sendable {
    let key: String
    var errorDescription: String? { Strings.text(key) }
}

actor SleepController {
    private var connection: Int32 = -1

    static func systemSleepDisabled() throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8),
              let value = parseSleepDisabled(text) else {
            throw CaffelidError(key: "error.read")
        }
        return value
    }

    static func parseSleepDisabled(_ text: String) -> Bool? {
        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.count == 2, fields[0] == "SleepDisabled" {
                if fields[1] == "1" { return true }
                if fields[1] == "0" { return false }
            }
        }
        return nil
    }

    func resetIfNeeded() async throws {
        guard try Self.systemSleepDisabled() else { return }
        try await SupportService.ensureReady()
        try openConnection()
        defer { cleanUp() }
        guard caffelid_write_line(connection, "RESET\n") == 0, readLine() == "OFF",
              try !Self.systemSleepDisabled() else { throw CaffelidError(key: "error.reset") }
    }

    func activate() async throws {
        guard connection < 0 else { return }
        try await SupportService.ensureReady()
        do {
            try openConnection()
            guard caffelid_write_line(connection, "ON\n") == 0,
                  readLine() == "ON", try Self.systemSleepDisabled() else {
                throw CaffelidError(key: "error.activate")
            }
        } catch {
            cleanUp() // The daemon restores sleep if activation partly succeeded.
            throw error
        }
    }

    private func openConnection() throws {
        cleanUp()
        // Wait briefly for launchd, without revoking approval on connection failure.
        // Registration repair remains an explicit diagnostic.
        for _ in 0..<50 {
            connection = caffelid_connect_service()
            if connection >= 0 { break }
            usleep(100_000)
        }
        guard connection >= 0, readLine() == "READY" else {
            cleanUp()
            throw CaffelidError(key: "error.service")
        }
    }

    func deactivate() async throws {
        if connection >= 0 {
            let sent = caffelid_write_line(connection, "OFF\n") == 0
            let reply = sent ? readLine() : nil
            cleanUp()
            if reply == "OFF", try !Self.systemSleepDisabled() { return }
        }
        try await resetIfNeeded()
    }

    func check() throws -> Bool {
        let disabled = try Self.systemSleepDisabled()
        if !disabled, connection >= 0 {
            _ = caffelid_write_line(connection, "OFF\n")
            _ = readLine()
            cleanUp()
        }
        return disabled
    }

    private func readLine() -> String? {
        var buffer = [CChar](repeating: 0, count: 32)
        guard caffelid_read_line(connection, &buffer, buffer.count, 5_000) == 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func cleanUp() {
        caffelid_close(connection)
        connection = -1
    }

}
