import AwakeCore
import Darwin
import Foundation

protocol SleepSettingControlling: AnyObject {
    func readDisabled() throws -> Bool
    func writeDisabled(_ value: Bool) throws
}

/// Reads and writes the kernel `SleepDisabled` flag (what `pmset disablesleep` sets).
final class SystemSleepSetting: SleepSettingControlling {
    func readDisabled() throws -> Bool {
        try SystemSleepState.readDisabled()
    }
    func writeDisabled(_ value: Bool) throws {
        _ = try pmset(["-a", "disablesleep", value ? "1" : "0"])
        // powerd delivers preference updates to the kernel asynchronously.
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        repeat {
            if try readDisabled() == value { return }
            Thread.sleep(forTimeInterval: 0.05)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw SettingError.unconfirmed
    }
    private func pmset(_ arguments: [String]) throws -> String {
        let task = Process(), pipe = Pipe(), finished = DispatchSemaphore(value: 0)
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { _ in finished.signal() }
        try task.run()
        guard finished.wait(timeout: .now() + 3) == .success else {
            task.terminate()
            if finished.wait(timeout: .now() + 1) != .success { kill(task.processIdentifier, SIGKILL) }
            throw SettingError.command
        }
        guard task.terminationStatus == 0 else { throw SettingError.command }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    enum SettingError: LocalizedError {
        case unconfirmed, command
        var errorDescription: String? {
            switch self {
            case .unconfirmed: "macOS did not confirm the sleep setting change. Keep the lid open."
            case .command: "macOS could not update its sleep setting."
            }
        }
    }
}
