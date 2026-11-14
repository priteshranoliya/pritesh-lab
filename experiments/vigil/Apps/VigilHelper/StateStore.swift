import AwakeCore
import Darwin
import Foundation

/// Everything the helper must remember across its own restarts.
struct PersistedState: Codable, Equatable {
    /// Identifies the boot this state belongs to. A reboot ends every session.
    var bootSession: String
    /// Recovery journal: the `SleepDisabled` value to restore. Present only
    /// while Vigil has changed the setting, and written before changing it.
    var previousSleepDisabled: Bool?
    var session: HelperSession?
    var lastEnd: String?
}

protocol StateStoring: AnyObject {
    func load() throws -> PersistedState?
    func save(_ state: PersistedState) throws
}

/// Root-only JSON file. Writes are atomic and flushed before the helper
/// touches any system setting, so a crash can always be recovered from.
final class StateStore: StateStoring {
    private let folder: String
    private var file: String { folder + "/state.json" }

    init(folder: String) { self.folder = folder }

    func load() throws -> PersistedState? {
        try prepareDirectory()
        guard try validateFileIfPresent() else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        guard data.count < 64 * 1024 else { throw Failure.insecure }
        return try decoder.decode(PersistedState.self, from: data)
    }

    func save(_ state: PersistedState) throws {
        try prepareDirectory()
        try validateFileIfPresent()
        let data = try encoder.encode(state)
        try data.write(to: URL(fileURLWithPath: file), options: .atomic)
        guard chmod(file, 0o600) == 0 else { throw Failure.insecure }
        try flush(file, flags: O_RDONLY | O_NOFOLLOW)
        try flush(folder, flags: O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private func flush(_ path: String, flags: Int32) throws {
        let fd = open(path, flags)
        guard fd >= 0 else { throw Failure.insecure }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw Failure.insecure }
    }

    private func prepareDirectory() throws {
        guard geteuid() == 0 else { throw Failure.insecure }
        if mkdir(folder, 0o700) < 0 && errno != EEXIST { throw Failure.insecure }
        var info = stat()
        guard lstat(folder, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == 0, info.st_mode & 0o777 == 0o700 else { throw Failure.insecure }
    }

    @discardableResult private func validateFileIfPresent() throws -> Bool {
        var info = stat()
        if lstat(file, &info) < 0 {
            if errno == ENOENT { return false }
            throw Failure.insecure
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == 0, info.st_mode & 0o077 == 0,
              info.st_nlink == 1 else { throw Failure.insecure }
        return true
    }

    enum Failure: LocalizedError {
        case insecure
        var errorDescription: String? { "The helper’s state file could not be secured." }
    }
}

enum BootSession {
    /// Changes on every boot.
    static var current: String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
