import AwakeCore
import Foundation
import Observation

@MainActor @Observable
final class Preferences {
    private let defaults: UserDefaults
    var rememberDuration: Bool { didSet { defaults.set(rememberDuration, forKey: "rememberDuration") } }
    var keepDisplayAwake: Bool { didSet { defaults.set(keepDisplayAwake, forKey: "keepDisplayAwake") } }
    /// Start new sessions with closed-lid mode on.
    var closedLidByDefault: Bool { didSet { defaults.set(closedLidByDefault, forKey: "closedLidByDefault") } }
    var allowClosedLidOnBattery: Bool { didSet { defaults.set(allowClosedLidOnBattery, forKey: SessionRulesDefaults.closedLidOnBattery) } }
    var closedLidBatteryCutoff: Int { didSet { defaults.set(closedLidBatteryCutoff, forKey: SessionRulesDefaults.batteryCutoff) } }
    var closedLidBatteryMinutes: Int { didSet { defaults.set(closedLidBatteryMinutes, forKey: SessionRulesDefaults.closedLidBatteryMinutes) } }
    var closedLidMaxHours: Int { didSet { defaults.set(closedLidMaxHours, forKey: SessionRulesDefaults.closedLidMaxHours) } }
    var endSessionOnLowBattery: Bool { didSet { defaults.set(endSessionOnLowBattery, forKey: SessionRulesDefaults.endOnLowBattery) } }
    var requirePowerAdapter: Bool { didSet { defaults.set(requirePowerAdapter, forKey: SessionRulesDefaults.requiresAdapter) } }
    private var savedMinutes: Int { didSet { defaults.set(savedMinutes, forKey: "savedMinutes") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["rememberDuration": true, "savedMinutes": 30,
                                    "keepDisplayAwake": false, "closedLidByDefault": false])
        rememberDuration = defaults.bool(forKey: "rememberDuration")
        keepDisplayAwake = defaults.bool(forKey: "keepDisplayAwake")
        closedLidByDefault = defaults.bool(forKey: "closedLidByDefault")
        savedMinutes = defaults.integer(forKey: "savedMinutes")
        let rules = SessionRulesDefaults.load(from: defaults)
        allowClosedLidOnBattery = rules.closedLidOnBattery
        closedLidBatteryCutoff = rules.batteryCutoff
        closedLidBatteryMinutes = rules.closedLidBatteryMinutes
        closedLidMaxHours = rules.closedLidMaxHours
        endSessionOnLowBattery = rules.endOnLowBattery
        requirePowerAdapter = rules.requiresAdapter
    }

    func setClosedLidBatteryUse(_ enabled: Bool) {
        allowClosedLidOnBattery = enabled
        if enabled { requirePowerAdapter = false }
    }

    var sessionRules: SessionRules {
        SessionRules(requiresAdapter: requirePowerAdapter, endOnLowBattery: endSessionOnLowBattery,
                     batteryCutoff: closedLidBatteryCutoff, closedLidOnBattery: allowClosedLidOnBattery,
                     closedLidBatteryMinutes: closedLidBatteryMinutes, closedLidMaxHours: closedLidMaxHours)
    }

    var sessionPowerPolicy: SessionPowerPolicy { sessionRules.sessionPolicy }
    var closedLidPolicy: ClosedLidPolicy { sessionRules.closedLidPolicy }

    var initialMinutes: Int {
        guard rememberDuration, (1...SessionDuration.maximumMinutes).contains(savedMinutes) else { return 30 }
        return savedMinutes
    }

    func remember(_ duration: SessionDuration) {
        guard rememberDuration else { return }
        if case .minutes(let minutes) = duration { savedMinutes = minutes }
    }
}
