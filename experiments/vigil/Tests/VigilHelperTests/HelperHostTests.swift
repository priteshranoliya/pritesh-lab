import AwakeCore
import Foundation
import Testing
import VigilIPC
@testable import VigilHelper

final class FakeSleep: SleepSettingControlling {
    var disabled: Bool
    var failWrites = false
    var writes: [Bool] = []
    init(disabled: Bool = false) { self.disabled = disabled }
    func readDisabled() throws -> Bool { disabled }
    func writeDisabled(_ value: Bool) throws {
        if failWrites { throw SessionRejection("pmset failed") }
        writes.append(value)
        disabled = value
    }
}

final class FakeStore: StateStoring {
    var state: PersistedState?
    var corrupt = false
    func load() throws -> PersistedState? {
        if corrupt { throw StateStore.Failure.insecure }
        return state
    }
    func save(_ state: PersistedState) throws { self.state = state }
}

@MainActor
final class FakeAssertion: IdleAssertionHolding {
    var active = false
    func set(active: Bool) { self.active = active }
}

/// Every scenario here is one the app is never involved in: the helper
/// must keep or restore the right state on its own.
@MainActor @Suite struct HelperHostTests {
    let store = FakeStore()
    let sleep = FakeSleep()
    let assertion = FakeAssertion()
    var power = ClosedLidPowerState(source: .adapter, batteryPercent: 90)
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var uptime: TimeInterval = 1000

    func makeHost(boot: String = "boot-1", power: ClosedLidPowerState? = nil) -> HelperHost {
        let reading = power ?? self.power
        let clock = now, up = uptime
        let host = HelperHost(store: store, sleep: sleep, assertion: assertion, bootSession: boot,
                              power: { reading }, clock: { clock }, uptime: { up })
        host.start()
        return host
    }

    func send(_ host: HelperHost, _ request: HelperRequest) throws -> HelperResponse {
        let reply = host.handle(try HelperCoding.encoder().encode(request))
        return try HelperCoding.decoder().decode(HelperResponse.self, from: reply)
    }

    func closedLidRequest(endsIn seconds: Double? = nil) -> HelperRequest {
        .start(SessionRequest(endsAt: seconds.map { now.addingTimeInterval($0) }, closedLid: true, rules: .standard))
    }

    @Test func closedLidJournalsBeforeDisablingSleep() throws {
        let host = makeHost()
        let response = try send(host, closedLidRequest())
        #expect(response.error == nil)
        #expect(response.status.closedLidApplied && sleep.disabled && assertion.active)
        #expect(store.state?.previousSleepDisabled == false)
        #expect(store.state?.session?.closedLid == true)
    }

    @Test func stopRestoresTheOriginalValue() throws {
        sleep.disabled = true // someone had already run `pmset disablesleep 1`
        let host = makeHost()
        _ = try send(host, closedLidRequest())
        _ = try send(host, .stop)
        #expect(sleep.disabled, "the user's own setting must be preserved")
        #expect(store.state?.previousSleepDisabled == nil && store.state?.session == nil && !assertion.active)
    }

    @Test func sessionSurvivesAHelperRestartInTheSameBoot() throws {
        _ = try send(makeHost(), closedLidRequest())
        // launchd restarts a crashed helper; nothing was restored in between.
        let restarted = makeHost(boot: "boot-1")
        #expect(restarted.status.session?.closedLid == true)
        #expect(restarted.status.closedLidApplied && sleep.disabled && assertion.active)
    }

    @Test func rebootEndsTheSessionAndRestoresSleep() throws {
        _ = try send(makeHost(), closedLidRequest())
        let afterReboot = makeHost(boot: "boot-2")
        #expect(afterReboot.status.session == nil)
        #expect(afterReboot.status.lastEnd == "Session ended when your Mac restarted.")
        #expect(!sleep.disabled && store.state?.previousSleepDisabled == nil)
    }

    @Test func unreadableStateFallsBackToNormalSleep() {
        sleep.disabled = true
        store.corrupt = true
        let host = makeHost()
        #expect(host.status.session == nil && !sleep.disabled)
    }

    @Test func failingToDisableSleepTurnsClosedLidOffVisibly() throws {
        sleep.failWrites = true
        let host = makeHost()
        let response = try send(host, closedLidRequest())
        #expect(!response.status.closedLidApplied)
        #expect(response.status.session?.closedLid == false)
        #expect(response.status.session?.notice?.contains("couldn’t start") == true)
        #expect(assertion.active, "the lid-open session still runs")
    }

    @Test func failedRestoreIsRetriedUntilItSucceeds() throws {
        let host = makeHost()
        _ = try send(host, closedLidRequest())
        sleep.failWrites = true
        _ = try send(host, .stop)
        #expect(sleep.disabled && store.state?.previousSleepDisabled == false && host.status.problem != nil)
        sleep.failWrites = false
        host.tick()
        #expect(!sleep.disabled && store.state?.previousSleepDisabled == nil && host.status.problem == nil)
    }

    @Test func systemSleepEndsTheSession() throws {
        let host = makeHost()
        _ = try send(host, closedLidRequest())
        host.systemWillSleep()
        #expect(host.status.session == nil && !sleep.disabled && !assertion.active)
    }

    @Test func shutdownRestoresSleepButKeepsTheSessionForRestart() throws {
        let host = makeHost()
        _ = try send(host, closedLidRequest())
        host.shutdown()
        #expect(!sleep.disabled && !assertion.active)
        #expect(store.state?.session != nil && store.state?.session?.closedLid == false)
    }

    @Test func secondStartIsRejected() throws {
        let host = makeHost()
        _ = try send(host, closedLidRequest())
        #expect(try send(host, closedLidRequest()).error == "A session is already running.")
    }

    @Test func malformedRequestIsRejectedWithoutChangingState() throws {
        let host = makeHost()
        let reply = host.handle(Data("not json".utf8))
        let response = try HelperCoding.decoder().decode(HelperResponse.self, from: reply)
        #expect(response.error != nil && response.status.session == nil && !sleep.disabled)
    }

    @Test func expiredSessionIsEndedByTheHelperAlone() throws {
        var test = self
        let host = test.makeHost()
        _ = try send(host, closedLidRequest(endsIn: 60))
        test.now = now.addingTimeInterval(61)
        let later = test.makeHost(boot: "boot-1") // reload with a later clock
        later.tick()
        #expect(later.status.session == nil && !sleep.disabled)
    }
}

extension HelperHostTests {
    @Test func allowingBatteryMidSessionAppliesWithoutRestart() throws {
        let host = makeHost()
        _ = try send(host, .start(SessionRequest(endsAt: nil, closedLid: false, rules: .standard)))
        let started = host.status.session?.id
        var travel = SessionRules.standard
        travel.requiresAdapter = false
        travel.closedLidOnBattery = true
        #expect(try send(host, .updateRules(travel)).error == nil)
        #expect(host.status.session?.rules == travel && host.status.session?.id == started)
        var bad = travel
        bad.batteryCutoff = 1
        #expect(try send(host, .updateRules(bad)).error != nil)
        #expect(host.status.session?.rules == travel)
    }
}
