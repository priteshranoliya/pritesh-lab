import Foundation

/// The power and closed-lid limits a session runs under. The app sends these
/// to the helper with every session, and the helper validates them again.
public struct SessionRules: Codable, Equatable, Sendable {
    /// Allowed closed-lid limits in hours; `noClosedLidTimeLimit` removes the cap.
    public static let closedLidHourLimits = [1, 2, 4, 6, 8, 12, 24]
    public static let noClosedLidTimeLimit = 0

    public var requiresAdapter: Bool
    /// End the whole session on battery at `batteryCutoff`.
    public var endOnLowBattery: Bool
    public var batteryCutoff: Int
    public var closedLidOnBattery: Bool
    /// Minutes of closed-lid time on battery, or `ClosedLidPolicy.noBatteryTimeLimit`.
    public var closedLidBatteryMinutes: Int
    /// Hours of continuous closed-lid time, or `noClosedLidTimeLimit`.
    public var closedLidMaxHours: Int

    public static let standard = SessionRules(
        requiresAdapter: true, endOnLowBattery: true, batteryCutoff: 30,
        closedLidOnBattery: false, closedLidBatteryMinutes: 30,
        closedLidMaxHours: noClosedLidTimeLimit)

    public init(requiresAdapter: Bool, endOnLowBattery: Bool, batteryCutoff: Int,
                closedLidOnBattery: Bool, closedLidBatteryMinutes: Int, closedLidMaxHours: Int) {
        self.requiresAdapter = requiresAdapter
        self.endOnLowBattery = endOnLowBattery
        self.batteryCutoff = batteryCutoff
        self.closedLidOnBattery = closedLidOnBattery
        self.closedLidBatteryMinutes = closedLidBatteryMinutes
        self.closedLidMaxHours = closedLidMaxHours
    }

    public var isValid: Bool {
        ClosedLidPolicy.batteryCutoffs.contains(batteryCutoff)
            && (closedLidBatteryMinutes == ClosedLidPolicy.noBatteryTimeLimit
                || ClosedLidPolicy.batteryDurations.contains(closedLidBatteryMinutes))
            && (closedLidMaxHours == Self.noClosedLidTimeLimit || Self.closedLidHourLimits.contains(closedLidMaxHours))
    }

    public var sessionPolicy: SessionPowerPolicy {
        SessionPowerPolicy(batteryCutoff: endOnLowBattery ? batteryCutoff : nil, requiresAdapter: requiresAdapter)
    }

    public var closedLidPolicy: ClosedLidPolicy {
        (try? ClosedLidPolicy(allowsBattery: closedLidOnBattery, minimumBatteryPercent: batteryCutoff,
                              maximumBatteryMinutes: closedLidBatteryMinutes)) ?? .standard
    }
}

// MARK: - Shared preference storage

/// One set of keys shared by the app's settings and the `vigil` command.
public enum SessionRulesDefaults {
    public static let requiresAdapter = "requirePowerAdapter"
    public static let endOnLowBattery = "endSessionOnLowBattery"
    public static let batteryCutoff = "closedLidBatteryCutoff"
    public static let closedLidOnBattery = "allowClosedLidOnBattery"
    public static let closedLidBatteryMinutes = "closedLidBatteryMinutes"
    public static let closedLidMaxHours = "closedLidMaxHours"

    public static func register(in defaults: UserDefaults) {
        let standard = SessionRules.standard
        defaults.register(defaults: [
            requiresAdapter: standard.requiresAdapter, endOnLowBattery: standard.endOnLowBattery,
            batteryCutoff: standard.batteryCutoff, closedLidOnBattery: standard.closedLidOnBattery,
            closedLidBatteryMinutes: standard.closedLidBatteryMinutes, closedLidMaxHours: standard.closedLidMaxHours,
        ])
    }

    /// Corrupted values fall back to the standard rules field by field.
    public static func load(from defaults: UserDefaults) -> SessionRules {
        register(in: defaults)
        let standard = SessionRules.standard
        var rules = SessionRules(
            requiresAdapter: defaults.bool(forKey: requiresAdapter),
            endOnLowBattery: defaults.bool(forKey: endOnLowBattery),
            batteryCutoff: defaults.integer(forKey: batteryCutoff),
            closedLidOnBattery: defaults.bool(forKey: closedLidOnBattery),
            closedLidBatteryMinutes: defaults.integer(forKey: closedLidBatteryMinutes),
            closedLidMaxHours: defaults.integer(forKey: closedLidMaxHours))
        if !ClosedLidPolicy.batteryCutoffs.contains(rules.batteryCutoff) { rules.batteryCutoff = standard.batteryCutoff }
        if rules.closedLidBatteryMinutes != ClosedLidPolicy.noBatteryTimeLimit,
           !ClosedLidPolicy.batteryDurations.contains(rules.closedLidBatteryMinutes) {
            rules.closedLidBatteryMinutes = standard.closedLidBatteryMinutes
        }
        if rules.closedLidMaxHours != SessionRules.noClosedLidTimeLimit,
           !SessionRules.closedLidHourLimits.contains(rules.closedLidMaxHours) {
            rules.closedLidMaxHours = standard.closedLidMaxHours
        }
        return rules
    }
}
