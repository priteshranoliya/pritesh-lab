import AppKit
import AwakeCore
import Foundation
import Observation
import OSLog
import VigilIPC

/// Talks to the root helper and installs or removes it.
@MainActor @Observable
final class HelperService {
    enum Installation: Equatable {
        /// Not installed: sessions run inside the app (lid open only).
        case notInstalled
        /// Installed and answering.
        case ready
        /// Installed but from a different Vigil build.
        case outdated(installed: String)
        /// Files are present but the helper isn’t answering.
        case notResponding
    }

    /// What happened the last time the user installed or removed the helper.
    enum SetupOutcome: Equatable {
        case cancelled
        /// macOS refused to start the background service (Login Items switch off, or policy).
        case blockedByMacOS
        case failed(String)
    }

    private(set) var installation: Installation = .notInstalled
    private(set) var status: HelperStatus?
    private(set) var isBusy = false
    private(set) var message: String?
    private(set) var setupOutcome: SetupOutcome?

    @ObservationIgnored private let log = Logger(subsystem: VigilIdentity.appBundleID, category: "Helper")
    @ObservationIgnored private var refreshing = false

    var isReady: Bool {
        if case .ready = installation { return true }
        if case .outdated = installation { return status != nil }
        return false
    }

    var isInstalled: Bool { installation != .notInstalled }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let installed = FileManager.default.fileExists(atPath: VigilIdentity.launchDaemonPath)
        do {
            let response = try await Self.request(.status, timeout: 2)
            apply(response.status)
        } catch {
            status = nil
            installation = installed ? .notResponding : .notInstalled
        }
    }

    /// Sends a command. Returns the helper's message when it rejected or adjusted the request.
    func send(_ request: HelperRequest) async throws -> String? {
        let response = try await Self.request(request, timeout: 5)
        apply(response.status)
        return response.error
    }

    private func apply(_ status: HelperStatus) {
        self.status = status
        installation = status.version == VigilIdentity.version && status.protocolVersion == VigilIdentity.protocolVersion
            ? .ready : .outdated(installed: status.version)
    }

    nonisolated private static func request(_ request: HelperRequest, timeout: TimeInterval) async throws -> HelperResponse {
        try await Task.detached(priority: .userInitiated) {
            try HelperClient.send(request, timeout: timeout)
        }.value
    }

    // MARK: Install / remove

    /// Returns true when the helper ended up installed and answering.
    @discardableResult
    func install() async -> Bool {
        await runScript("install", success: "Helper installed.")
        return isReady
    }

    func uninstall() async { await runScript("uninstall", success: "Helper removed. Normal sleep settings are restored.") }

    /// Background services can be switched off in System Settings → General → Login Items & Extensions.
    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Runs the bundled script as root. macOS shows its own password prompt.
    private func runScript(_ action: String, success: String) async {
        guard !isBusy else { return }
        guard let script = Bundle.main.url(forResource: "helper", withExtension: "sh") else {
            message = "This copy of Vigil is missing its helper installer. Rebuild it with script/build.sh."
            return
        }
        isBusy = true
        message = nil
        setupOutcome = nil
        defer { isBusy = false }
        let bundle = Bundle.main.bundleURL.path
        let command = "/bin/bash \(Self.shellQuote(script.path)) \(action) \(Self.shellQuote(bundle))"
        let source = "do shell script \(Self.appleScriptQuote(command)) with prompt \"Vigil needs your password to \(action) its keep-awake helper.\" with administrator privileges"
        let result = await Task.detached { () -> (Int32, String) in
            let process = Process(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, error.localizedDescription) }
            process.waitUntilExit()
            let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return (process.terminationStatus, text)
        }.value
        if result.0 == 0 {
            message = success
            // launchd starts the helper asynchronously; give it a moment to open its socket.
            for _ in 0..<20 {
                await refresh()
                if action == "install" ? isReady : !isInstalled { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            if action == "install" && !isReady {
                setupOutcome = .blockedByMacOS
                message = nil
            }
        } else if result.1.contains("-128") {
            setupOutcome = .cancelled
        } else if result.1.localizedCaseInsensitiveContains("bootstrap") {
            setupOutcome = .blockedByMacOS
            log.error("Helper \(action, privacy: .public) blocked: \(result.1, privacy: .public)")
        } else {
            setupOutcome = .failed(Self.firstLine(of: result.1))
            log.error("Helper \(action, privacy: .public) failed: \(result.1, privacy: .public)")
        }
    }

    /// osascript prefixes errors with "execution error:"; keep only the readable part.
    nonisolated static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let cleaned = line.replacingOccurrences(of: #"^.*execution error: "#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" \(-?\d+\)$"#, with: "", options: .regularExpression)
        return cleaned.isEmpty ? "Unknown error." : cleaned
    }

    nonisolated static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func appleScriptQuote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
