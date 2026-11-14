import Foundation
import Testing
@testable import AwakeCore

@Suite struct SessionEngineTests {
    let origin = Date(timeIntervalSince1970: 1_800_000_000)
    let charger = ClosedLidPowerState(source: .adapter, batteryPercent: 90)
    let battery80 = ClosedLidPowerState(source: .battery, batteryPercent: 80)

    func rules(_ change: (inout SessionRules) -> Void = { _ in }) -> SessionRules {
        var rules = SessionRules.standard
        change(&rules)
        return rules
    }

    @Test func startsTimedAndOpenEndedSessions() throws {
        let timed = try SessionEngine.start(.init(endsAt: origin.addingTimeInterval(3600), closedLid: false, rules: rules()),
                                            now: origin, power: charger)
        #expect(timed.endsAt == origin.addingTimeInterval(3600) && !timed.closedLid)
        let open = try SessionEngine.start(.init(endsAt: nil, closedLid: true, rules: rules()), now: origin, power: charger)
        #expect(open.endsAt == nil && open.closedLid && open.closedLidSince == origin)
    }

    @Test(arguments: [-1.0, 0.0, 24.0 * 3600 + 1])
    func rejectsEndTimesOutsideTheNext24Hours(offset: Double) {
        #expect(throws: SessionRejection.self) {
            try SessionEngine.start(.init(endsAt: origin.addingTimeInterval(offset), closedLid: false, rules: rules()),
                                    now: origin, power: charger)
        }
    }

    @Test func rejectsTamperedRules() {
        let bad = rules { $0.batteryCutoff = 3 }
        #expect(throws: SessionRejection.self) {
            try SessionEngine.start(.init(endsAt: nil, closedLid: false, rules: bad), now: origin, power: charger)
        }
        let badHours = rules { $0.closedLidMaxHours = 5 }
        #expect(throws: SessionRejection.self) {
            try SessionEngine.start(.init(endsAt: nil, closedLid: false, rules: badHours), now: origin, power: charger)
        }
    }

    @Test func refusesToStartOnBatteryWhenAdapterRequired() {
        #expect(throws: SessionRejection.self) {
            try SessionEngine.start(.init(endsAt: nil, closedLid: false, rules: rules()), now: origin, power: battery80)
        }
    }

    @Test func completesAtItsEndTime() throws {
        var session = try SessionEngine.start(.init(endsAt: origin.addingTimeInterval(60), closedLid: true, rules: rules()),
                                              now: origin, power: charger)
        #expect(SessionEngine.tick(&session, now: origin.addingTimeInterval(59), elapsed: 1, power: charger) == nil)
        #expect(SessionEngine.tick(&session, now: origin.addingTimeInterval(60), elapsed: 1, power: charger) == .completed)
    }

    @Test func runsIndefinitelyWithoutAnyHeartbeat() throws {
        // No client contact is required: the session is owned by the helper.
        var session = try SessionEngine.start(.init(endsAt: nil, closedLid: true, rules: rules()), now: origin, power: charger)
        for second in 1...(48 * 3600) where second % 600 == 0 {
            #expect(SessionEngine.tick(&session, now: origin.addingTimeInterval(Double(second)), elapsed: 1, power: charger) == nil)
        }
        #expect(session.closedLid)
    }

    @Test func unpluggingEndsTheSessionWhenAdapterRequired() throws {
        var session = try SessionEngine.start(.init(endsAt: nil, closedLid: true, rules: rules()), now: origin, power: charger)
        #expect(SessionEngine.tick(&session, now: origin, elapsed: 1, power: battery80) == .powerRequired)
    }

    @Test func batteryCutoffEndsTheSession() throws {
        let onBattery = rules { $0.requiresAdapter = false; $0.closedLidOnBattery = true; $0.batteryCutoff = 40 }
        var session = try SessionEngine.start(.init(endsAt: nil, closedLid: true, rules: onBattery), now: origin, power: battery80)
        let low = ClosedLidPowerState(source: .battery, batteryPercent: 40)
        #expect(SessionEngine.tick(&session, now: origin, elapsed: 1, power: low) == .lowBattery(40))
    }

    @Test func heatTurnsOffClosedLidButKeepsTheSession() throws {
        var session = try SessionEngine.start(.init(endsAt: nil, closedLid: true, rules: rules()), now: origin, power: charger)
        let hot = ClosedLidPowerState(source: .adapter, batteryPercent: 90, thermalSafe: false)
        #expect(SessionEngine.tick(&session, now: origin, elapsed: 1, power: hot) == nil)
        #expect(!session.closedLid && session.notice == ClosedLidStopReason.thermalPressure.errorDescription)
        // It never turns itself back on once cool.
        #expect(SessionEngine.tick(&session, now: origin, elapsed: 1, power: charger) == nil)
        #expect(!session.closedLid)
    }

    @Test func refusesClosedLidWhileHot() throws {
        var session = try SessionEngine.start(.init(endsAt: nil, closedLid: false, rules: rules()), now: origin, power: charger)
        let hot = ClosedLidPowerState(source: .adapter, batteryPercent: 90, thermalSafe: false)
        #expect(throws: SessionRejection.self) {
            try SessionEngine.setClosedLid(true, session: &session, now: origin, power: hot)
        }
    }

    @Test func closedLidTimeLimitIsOptional() throws {
        var limited = try SessionEngine.start(.init(endsAt: nil, closedLid: true, rules: rules { $0.closedLidMaxHours = 2 }),
                                              now: origin, power: charger)
        _ = SessionEngine.tick(&limited, now: origin.addingTimeInterval(2 * 3600 - 1), elapsed: 1, power: charger)
        #expect(limited.closedLid)
        _ = SessionEngine.tick(&limited, now: origin.addingTimeInterval(2 * 3600), elapsed: 1, power: charger)
        #expect(!limited.closedLid && limited.notice == ClosedLidStopReason.timeLimit.errorDescription)

        var unlimited = try SessionEngine.start(.init(endsAt: nil, closedLid: true, rules: rules()), now: origin, power: charger)
        _ = SessionEngine.tick(&unlimited, now: origin.addingTimeInterval(30 * 3600), elapsed: 1, power: charger)
        #expect(unlimited.closedLid)
    }

    @Test func batteryBudgetAccumulatesAndCapsLargeGaps() throws {
        let onBattery = rules { $0.requiresAdapter = false; $0.closedLidOnBattery = true; $0.closedLidBatteryMinutes = 15 }
        var session = try SessionEngine.start(.init(endsAt: nil, closedLid: true, rules: onBattery), now: origin, power: battery80)
        // A suspended helper waking after an hour counts at most a few seconds.
        _ = SessionEngine.tick(&session, now: origin, elapsed: 3600, power: battery80)
        #expect(session.closedLidBatterySeconds == SessionEngine.maximumTickSeconds)
        // Charger time pauses the budget without resetting it.
        _ = SessionEngine.tick(&session, now: origin, elapsed: 1, power: .init(source: .adapter, batteryPercent: 81))
        #expect(session.closedLidBatterySeconds == SessionEngine.maximumTickSeconds)
        for _ in 0..<(15 * 60) { _ = SessionEngine.tick(&session, now: origin, elapsed: 1, power: battery80) }
        #expect(!session.closedLid && session.notice == ClosedLidStopReason.batteryTimeLimit(15).errorDescription)
    }

    @Test func extendStopsAt24HoursFromStart() throws {
        var session = try SessionEngine.start(.init(endsAt: origin.addingTimeInterval(23.9 * 3600), closedLid: false, rules: rules()),
                                              now: origin, power: charger)
        try SessionEngine.extend(&session, minutes: 60)
        #expect(session.endsAt == origin.addingTimeInterval(24 * 3600))
        var open = try SessionEngine.start(.init(endsAt: nil, closedLid: false, rules: rules()), now: origin, power: charger)
        #expect(throws: SessionRejection.self) { try SessionEngine.extend(&open, minutes: 15) }
    }
}

@Suite struct SessionRulesDefaultsTests {
    @Test func storesAndRepairsEachField() throws {
        let suite = "VigilTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SessionRulesDefaults.load(from: defaults) == .standard)
        defaults.set(55, forKey: SessionRulesDefaults.batteryCutoff)
        defaults.set(7, forKey: SessionRulesDefaults.closedLidMaxHours)
        defaults.set(13, forKey: SessionRulesDefaults.closedLidBatteryMinutes)
        let loaded = SessionRulesDefaults.load(from: defaults)
        #expect(loaded.batteryCutoff == 55)
        #expect(loaded.closedLidMaxHours == SessionRules.standard.closedLidMaxHours)
        #expect(loaded.closedLidBatteryMinutes == SessionRules.standard.closedLidBatteryMinutes)
        #expect(loaded.isValid)
    }
}
