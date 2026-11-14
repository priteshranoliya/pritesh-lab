import AwakeCore
import Foundation

public struct HelperRequest: Codable, Equatable, Sendable {
    public enum Command: String, Codable, Sendable { case status, start, stop, extend, setClosedLid, updateRules }

    public var command: Command
    public var session: SessionRequest?
    public var minutes: Int?
    public var closedLid: Bool?
    public var rules: SessionRules?

    public static let status = HelperRequest(command: .status)
    public static let stop = HelperRequest(command: .stop)
    public static func start(_ session: SessionRequest) -> HelperRequest { HelperRequest(command: .start, session: session) }
    public static func extend(minutes: Int) -> HelperRequest { HelperRequest(command: .extend, minutes: minutes) }
    public static func setClosedLid(_ enabled: Bool) -> HelperRequest { HelperRequest(command: .setClosedLid, closedLid: enabled) }
    public static func updateRules(_ rules: SessionRules) -> HelperRequest { HelperRequest(command: .updateRules, rules: rules) }

    public init(command: Command, session: SessionRequest? = nil, minutes: Int? = nil, closedLid: Bool? = nil,
                rules: SessionRules? = nil) {
        self.command = command
        self.session = session
        self.minutes = minutes
        self.closedLid = closedLid
        self.rules = rules
    }
}

public struct HelperStatus: Codable, Equatable, Sendable {
    public var version: String
    public var protocolVersion: Int
    public var session: HelperSession?
    /// True only after the kernel confirms sleep is disabled for closed-lid mode.
    public var closedLidApplied: Bool
    /// Why the last session ended, when it was not stopped by a person.
    public var lastEnd: String?
    /// A system problem the helper is still retrying, such as restoring sleep.
    public var problem: String?

    public init(version: String, protocolVersion: Int, session: HelperSession?, closedLidApplied: Bool,
                lastEnd: String?, problem: String?) {
        self.version = version
        self.protocolVersion = protocolVersion
        self.session = session
        self.closedLidApplied = closedLidApplied
        self.lastEnd = lastEnd
        self.problem = problem
    }
}

public struct HelperResponse: Codable, Equatable, Sendable {
    public var error: String?
    public var status: HelperStatus

    public init(error: String?, status: HelperStatus) {
        self.error = error
        self.status = status
    }
}

public enum HelperCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
