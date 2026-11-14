import Foundation

/// What a client asks the helper to run.
public struct SessionRequest: Codable, Equatable, Sendable {
    /// `nil` runs until stopped.
    public var endsAt: Date?
    public var closedLid: Bool
    public var rules: SessionRules

    public init(endsAt: Date?, closedLid: Bool, rules: SessionRules) {
        self.endsAt = endsAt
        self.closedLid = closedLid
        self.rules = rules
    }
}

/// A session owned by the helper. It is persisted, so it survives the app
/// quitting or crashing and the helper restarting; it never survives a reboot.
public struct HelperSession: Codable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public var endsAt: Date?
    public var closedLid: Bool
    public var rules: SessionRules
    public var closedLidSince: Date?
    /// Closed-lid time spent on battery. Plugging in pauses it; it never resets.
    public var closedLidBatterySeconds: Double
    /// Why closed-lid mode turned itself off while the session kept running.
    public var notice: String?

    public func remainingSeconds(at date: Date) -> Int? {
        AwakeSession(startedAt: startedAt, endsAt: endsAt).remainingSeconds(at: date)
    }
}

public struct SessionRejection: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Pure session rules. The helper calls these on its own clock and power
/// readings; nothing here touches the system, so every rule is unit-testable.
public enum SessionEngine {
    /// Longest gap counted between two ticks. A suspended helper must not
    /// charge hours of battery time to one sample.
    public static let maximumTickSeconds: TimeInterval = 5

    public static func start(_ request: SessionRequest, now: Date,
                             power: ClosedLidPowerState) throws -> HelperSession {
        guard request.rules.isValid else { throw SessionRejection(ClosedLidStopReason.invalidPolicy.errorDescription!) }
        if let end = request.endsAt {
            let seconds = end.timeIntervalSince(now)
            guard seconds > 0, seconds <= Double(SessionDuration.maximumMinutes * 60) else {
                throw SessionRejection("Choose 1 minute to 24 hours, or an end time within the next 24 hours.")
            }
        }
        if let reason = request.rules.sessionPolicy.stopReason(for: power) {
            switch reason {
            case .lowBattery(let cutoff): throw SessionRejection("Charge above \(cutoff)% or connect a power adapter to start.")
            default: throw SessionRejection(reason.description)
            }
        }
        var session = HelperSession(id: UUID(), startedAt: now, endsAt: request.endsAt, closedLid: false,
                                    rules: request.rules, closedLidSince: nil, closedLidBatterySeconds: 0)
        if request.closedLid { try setClosedLid(true, session: &session, now: now, power: power) }
        return session
    }

    public static func setClosedLid(_ enabled: Bool, session: inout HelperSession,
                                    now: Date, power: ClosedLidPowerState) throws {
        guard enabled else {
            session.closedLid = false
            session.closedLidSince = nil
            return
        }
        guard !session.closedLid else { return }
        if let reason = session.rules.closedLidPolicy.stopReason(for: power) {
            throw SessionRejection(reason.errorDescription ?? "Closed-lid mode is unavailable right now.")
        }
        session.closedLid = true
        session.closedLidSince = now
        session.closedLidBatterySeconds = 0
        session.notice = nil
    }

    /// Adds minutes to a timed session, never past 24 hours from its start.
    public static func extend(_ session: inout HelperSession, minutes: Int) throws {
        guard let end = session.endsAt else { throw SessionRejection("This session already runs until you stop it.") }
        guard (1...SessionDuration.maximumMinutes).contains(minutes) else { throw SessionRejection("Choose 1 minute to 24 hours.") }
        let maximum = session.startedAt.addingTimeInterval(Double(SessionDuration.maximumMinutes) * 60)
        session.endsAt = min(end.addingTimeInterval(Double(minutes) * 60), maximum)
    }

    /// Applies every limit. Returns a reason when the whole session must end.
    /// Closed-lid limits only turn closed-lid mode off; the session continues.
    public static func tick(_ session: inout HelperSession, now: Date, elapsed: TimeInterval,
                            power: ClosedLidPowerState) -> SessionEndReason? {
        if let end = session.endsAt, now >= end { return .completed }
        if let reason = session.rules.sessionPolicy.stopReason(for: power) { return reason }
        guard session.closedLid else { return nil }
        if power.source == .battery { session.closedLidBatterySeconds += min(max(0, elapsed), maximumTickSeconds) }
        let policy = session.rules.closedLidPolicy
        var stop = policy.stopReason(for: power)
        if stop == nil, session.rules.closedLidMaxHours != SessionRules.noClosedLidTimeLimit,
           let since = session.closedLidSince,
           now.timeIntervalSince(since) >= Double(session.rules.closedLidMaxHours * 3600) {
            stop = .timeLimit
        }
        if stop == nil, power.source == .battery, policy.hasBatteryTimeLimit,
           session.closedLidBatterySeconds >= Double(policy.maximumBatteryMinutes * 60) {
            stop = .batteryTimeLimit(policy.maximumBatteryMinutes)
        }
        if let stop {
            session.closedLid = false
            session.closedLidSince = nil
            session.notice = stop.errorDescription
        }
        return nil
    }
}
