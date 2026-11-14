import AppKit
import AwakeCore
import Foundation
import Observation
import VigilIPC

/// The helper's running session as the UI shows it.
struct DisplayedSession: Equatable {
    var startedAt: Date
    var endsAt: Date?
    var closedLid: Bool
    var closedLidApplied: Bool
    var notice: String?

    func remainingSeconds(at date: Date) -> Int? {
        AwakeSession(startedAt: startedAt, endsAt: endsAt).remainingSeconds(at: date)
    }
}

enum SessionMode: String, CaseIterable, Identifiable {
    case duration, untilTime, untilStopped
    var id: Self { self }
    var label: String {
        switch self {
        case .duration: "For a duration"
        case .untilTime: "Until a specific time"
        case .untilStopped: "Until I stop it"
        }
    }
}

/// Every session runs in the helper, so it survives Vigil quitting or
/// crashing. Until the helper is set up, starting a session sets it up first.
@MainActor @Observable
final class AwakeModel {
    let preferences: Preferences
    let helper = HelperService()
    var durationDraft: DurationDraft
    var sessionMode = SessionMode.duration
    var sessionEndDate = Date.now.addingTimeInterval(30 * 60)
    var isPopoverVisible = false
    private(set) var blockedStartAttempts = 0
    private(set) var errorMessage: String?
    private(set) var isSending = false

    @ObservationIgnored private let display = DisplayAwakeAssertion()
    @ObservationIgnored private var pollTimer: Timer?

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        durationDraft = DurationDraft(totalMinutes: preferences.initialMinutes)
    }

    func start() {
        schedulePolling()
        Task { await refresh() }
    }

    func shutdown() {
        // The session itself belongs to the helper and keeps running.
        pollTimer?.invalidate()
        display.set(false)
    }

    func popoverVisibilityChanged(_ visible: Bool) {
        isPopoverVisible = visible
        schedulePolling()
        if visible { Task { await refresh() } }
    }

    private func schedulePolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: isPopoverVisible ? 1.5 : 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func refresh() async {
        await helper.refresh()
        syncDisplayAssertion()
    }

    // MARK: State

    /// Starting a session first needs the one-time helper setup.
    var needsSetupToStart: Bool { !helper.isReady }

    var current: DisplayedSession? {
        guard let status = helper.status, let session = status.session else { return nil }
        return DisplayedSession(startedAt: session.startedAt, endsAt: session.endsAt,
                                closedLid: session.closedLid, closedLidApplied: status.closedLidApplied,
                                notice: session.notice)
    }

    var isActive: Bool { current != nil }

    var statusMessage: String? {
        if let errorMessage { return errorMessage }
        return helper.status?.problem ?? (isActive ? nil : helper.status?.lastEnd)
    }

    var requestedSession: SessionDuration? {
        switch sessionMode {
        case .duration: durationDraft.duration
        case .untilTime: .until(Calendar.current.dateInterval(of: .minute, for: sessionEndDate)?.start ?? sessionEndDate)
        case .untilStopped: .indefinitely
        }
    }

    // MARK: Actions

    /// Without the helper, "Set up & start" installs it, then starts.
    func startSession() {
        guard !isActive, !isSending, !helper.isBusy, let duration = requestedSession else { return }
        errorMessage = nil
        guard helper.isReady else {
            Task {
                guard await helper.install() else { await refresh(); return }
                preferences.closedLidByDefault = true
                startSession()
            }
            return
        }
        let endsAt: Date?
        switch duration {
        case .minutes(let minutes): endsAt = Date.now.addingTimeInterval(Double(minutes) * 60)
        case .until(let date): endsAt = date
        case .indefinitely: endsAt = nil
        }
        let request = SessionRequest(endsAt: endsAt, closedLid: preferences.closedLidByDefault,
                                     rules: preferences.sessionRules)
        perform(.start(request)) { [weak self] in self?.preferences.remember(duration) }
    }

    func endSession() {
        errorMessage = nil
        perform(.stop)
    }

    func extendSession() { perform(.extend(minutes: 15)) }

    /// Before a session: the default for new sessions. During one: applies now.
    func setClosedLid(_ enabled: Bool) {
        preferences.closedLidByDefault = enabled
        if isActive { perform(.setClosedLid(enabled)) }
    }

    var closedLidToggleValue: Bool {
        current?.closedLid ?? preferences.closedLidByDefault
    }

    /// On battery while a charger is still required, or while closed-lid mode
    /// wants to run but battery use is off. The popover offers one-tap Allow.
    var batteryBlocks: Bool {
        guard SystemPowerState.snapshot.source == .battery else { return false }
        if preferences.requirePowerAdapter && !isActive { return true }
        return closedLidToggleValue && !preferences.allowClosedLidOnBattery
    }

    /// One-tap travel setup: sessions and closed-lid mode may run on battery,
    /// still bounded by the battery cutoff and heat checks. Applies to a
    /// running session too.
    func allowBatteryUse() {
        preferences.setClosedLidBatteryUse(true)
        errorMessage = nil
        if isActive { perform(.updateRules(preferences.sessionRules)) }
    }

    var closedLidStatus: ClosedLidStatus {
        ClosedLidStatus.make(installation: helper.installation, busy: helper.isBusy, outcome: helper.setupOutcome,
                             session: current, closedLidByDefault: preferences.closedLidByDefault)
    }

    func perform(_ action: ClosedLidStatus.Action) {
        switch action {
        case .setUp, .tryAgain, .update, .fix: installHelper()
        case .openLoginItems: helper.openLoginItemsSettings()
        }
    }

    func setDisplayAwake(_ enabled: Bool) {
        preferences.keepDisplayAwake = enabled
        syncDisplayAssertion()
    }

    /// Setting up from the closed-lid card means the user wants closed-lid mode.
    func installHelper() {
        Task {
            if await helper.install() { preferences.closedLidByDefault = true }
            await refresh()
        }
    }

    func uninstallHelper() {
        Task {
            await helper.uninstall()
            // Without the helper, closed-lid mode can't run; never imply otherwise.
            if !helper.isInstalled { preferences.closedLidByDefault = false }
            await refresh()
        }
    }

    private func perform(_ request: HelperRequest, onSuccess: (() -> Void)? = nil) {
        isSending = true
        Task {
            defer { isSending = false }
            do {
                if let error = try await helper.send(request) {
                    errorMessage = error
                    if request.command == .start { blockedStartAttempts += 1 }
                } else {
                    errorMessage = nil
                    onSuccess?()
                }
            } catch {
                errorMessage = error.localizedDescription
                await helper.refresh()
            }
            syncDisplayAssertion()
        }
    }

    /// Display sleep is a comfort setting held by the app, not a safety guarantee.
    private func syncDisplayAssertion() {
        display.set(preferences.keepDisplayAwake && isActive)
    }
}
