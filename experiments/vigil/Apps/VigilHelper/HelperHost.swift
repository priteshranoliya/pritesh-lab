import AwakeCore
import Foundation
import IOKit.pwr_mgt
import OSLog
import VigilIPC

/// Owns the one session on this Mac. The app is only a remote control: if it
/// quits, crashes or hangs, the session and its safety limits keep running here.
@MainActor
final class HelperHost {
    private let store: any StateStoring
    private let sleep: any SleepSettingControlling
    private let assertion: any IdleAssertionHolding
    private let power: () -> ClosedLidPowerState
    private let clock: () -> Date
    private let uptime: () -> TimeInterval
    private let log = Logger(subsystem: VigilIdentity.helperLabel, category: "Session")
    private var state: PersistedState
    private var closedLidApplied = false
    private var problem: String?
    private var lastTick: TimeInterval
    private var lastPersist: TimeInterval
    private var timer: DispatchSourceTimer?

    init(store: any StateStoring, sleep: any SleepSettingControlling = SystemSleepSetting(),
         assertion: any IdleAssertionHolding = IdleSleepAssertion(), bootSession boot: String = BootSession.current,
         power: @escaping () -> ClosedLidPowerState = { SystemPowerState.snapshot },
         clock: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.store = store
        self.sleep = sleep
        self.assertion = assertion
        self.power = power
        self.clock = clock
        self.uptime = uptime
        lastTick = uptime()
        lastPersist = lastTick
        var loaded: PersistedState?
        do { loaded = try store.load() } catch {
            // Without a trustworthy journal, normal sleep is the safe value to restore.
            Logger(subsystem: VigilIdentity.helperLabel, category: "Session")
                .error("State unreadable, restoring normal sleep: \(error.localizedDescription, privacy: .public)")
            loaded = PersistedState(bootSession: boot, previousSleepDisabled: false, session: nil, lastEnd: nil)
        }
        var state = loaded ?? PersistedState(bootSession: boot, previousSleepDisabled: nil, session: nil, lastEnd: nil)
        if state.bootSession != boot {
            if state.session != nil { state.lastEnd = "Session ended when your Mac restarted." }
            state.session = nil
            state.bootSession = boot
        }
        self.state = state
    }

    func start() {
        persist()
        reconcile()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { MainActor.assumeIsolated { self.tick() } }
        timer.resume()
        self.timer = timer
    }

    // MARK: Requests

    func handle(_ body: Data) -> Data {
        let response: HelperResponse
        do {
            let request = try HelperCoding.decoder().decode(HelperRequest.self, from: body)
            response = HelperResponse(error: try perform(request), status: status)
        } catch {
            response = HelperResponse(error: error.localizedDescription, status: status)
        }
        return (try? HelperCoding.encoder().encode(response)) ?? Data("{}".utf8)
    }

    /// Returns a non-fatal message, or throws when the request was rejected.
    private func perform(_ request: HelperRequest) throws -> String? {
        let now = clock(), power = power()
        switch request.command {
        case .status:
            return nil
        case .start:
            guard let wanted = request.session else { throw SessionRejection("Missing session details.") }
            guard state.session == nil else { throw SessionRejection("A session is already running.") }
            state.session = try SessionEngine.start(wanted, now: now, power: power)
            state.lastEnd = nil
            log.info("Session started (closed lid: \(wanted.closedLid))")
        case .stop:
            end(.stopped)
            return nil
        case .extend:
            guard var session = state.session else { throw SessionRejection("No session is running.") }
            try SessionEngine.extend(&session, minutes: request.minutes ?? 15)
            state.session = session
        case .updateRules:
            guard var session = state.session else { throw SessionRejection("No session is running.") }
            guard let rules = request.rules, rules.isValid else {
                throw SessionRejection(ClosedLidStopReason.invalidPolicy.errorDescription!)
            }
            // New limits apply from the next safety check; nothing restarts.
            session.rules = rules
            state.session = session
        case .setClosedLid:
            guard var session = state.session else { throw SessionRejection("No session is running.") }
            try SessionEngine.setClosedLid(request.closedLid ?? false, session: &session, now: now, power: power)
            state.session = session
        }
        persist()
        reconcile()
        return state.session?.notice
    }

    var status: HelperStatus {
        HelperStatus(version: VigilIdentity.version, protocolVersion: VigilIdentity.protocolVersion,
                     session: state.session, closedLidApplied: closedLidApplied,
                     lastEnd: state.lastEnd, problem: problem)
    }

    // MARK: Safety loop

    func tick() {
        let uptime = uptime()
        let elapsed = uptime - lastTick
        lastTick = uptime
        if var session = state.session {
            let before = session
            if let reason = SessionEngine.tick(&session, now: clock(), elapsed: elapsed, power: power()) {
                end(reason)
            } else {
                state.session = session
                // Battery time changes every tick on battery; save it periodically, other changes at once.
                if session.closedLid != before.closedLid || session.notice != before.notice
                    || uptime - lastPersist >= 15 {
                    if session.notice != before.notice, let notice = session.notice { log.info("\(notice, privacy: .public)") }
                    persist()
                }
            }
        }
        reconcile()
    }

    func systemWillSleep() {
        // Respect a sleep macOS still chose to perform; never restart on wake.
        guard state.session != nil else { return }
        end(.systemSleep)
    }

    private func end(_ reason: SessionEndReason) {
        guard state.session != nil else { return }
        state.session = nil
        state.lastEnd = reason == .stopped || reason == .completed ? nil : reason.description
        log.info("Session ended: \(reason.description, privacy: .public)")
        persist()
        reconcile()
    }

    /// Makes the system match the session. Failed restorations are retried every tick.
    private func reconcile() {
        assertion.set(active: state.session != nil)
        let wantsClosedLid = state.session?.closedLid == true
        do {
            if wantsClosedLid {
                if state.previousSleepDisabled == nil {
                    // Journal first: a crash after this point still restores the original value.
                    state.previousSleepDisabled = try sleep.readDisabled()
                    try store.save(state)
                }
                if try !sleep.readDisabled() { try sleep.writeDisabled(true) }
                closedLidApplied = true
            } else {
                closedLidApplied = false
                if let previous = state.previousSleepDisabled {
                    try sleep.writeDisabled(previous)
                    state.previousSleepDisabled = nil
                    try store.save(state)
                }
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
            log.error("Reconcile failed: \(error.localizedDescription, privacy: .public)")
            if wantsClosedLid {
                // Never report a closed-lid mode that the kernel did not confirm.
                closedLidApplied = false
                state.session?.closedLid = false
                state.session?.closedLidSince = nil
                state.session?.notice = "Closed-lid mode couldn’t start: \(error.localizedDescription)"
                persist()
            }
        }
    }

    /// Called when launchd stops the helper (uninstall, upgrade or shutdown).
    /// Restore sleep now; the session itself stays saved for a same-boot restart.
    func shutdown() {
        assertion.set(active: false)
        if let previous = state.previousSleepDisabled, (try? sleep.writeDisabled(previous)) != nil {
            state.previousSleepDisabled = nil
            if state.session?.closedLid == true {
                state.session?.closedLid = false
                state.session?.closedLidSince = nil
                state.session?.notice = "Closed-lid mode turned off while the helper restarted."
            }
            persist()
        }
    }

    private func persist() {
        do {
            try store.save(state)
            lastPersist = uptime()
        } catch {
            problem = error.localizedDescription
            log.error("Saving state failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor protocol IdleAssertionHolding: AnyObject {
    func set(active: Bool)
}

/// Prevents idle sleep while any session runs, lid open or closed.
@MainActor
final class IdleSleepAssertion: IdleAssertionHolding {
    private var identifier: IOPMAssertionID?

    func set(active: Bool) {
        if active, identifier == nil {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                   IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                   "Vigil keep-awake session" as CFString, &id)
            if result == kIOReturnSuccess { identifier = id }
        } else if !active, let id = identifier {
            IOPMAssertionRelease(id)
            identifier = nil
        }
    }
}
