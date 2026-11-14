import Foundation
import Testing
@testable import AwakeUI

/// Every state the closed-lid card can be in must say what is happening and
/// offer the next step — the app should never need outside instructions.
@MainActor @Suite struct ClosedLidStatusTests {
    func helperSession(closedLid: Bool, applied: Bool, notice: String? = nil) -> DisplayedSession {
        DisplayedSession(startedAt: .now, endsAt: nil, closedLid: closedLid, closedLidApplied: applied, notice: notice)
    }

    func status(_ installation: HelperService.Installation, busy: Bool = false,
                outcome: HelperService.SetupOutcome? = nil, session: DisplayedSession? = nil,
                closedLidByDefault: Bool = false) -> ClosedLidStatus {
        .make(installation: installation, busy: busy, outcome: outcome, session: session,
              closedLidByDefault: closedLidByDefault)
    }

    @Test func notSetUpOffersSetup() {
        let result = status(.notInstalled)
        #expect(result.action == .setUp && result.tone == .neutral)
        let cancelled = status(.notInstalled, outcome: .cancelled)
        #expect(cancelled.action == .setUp && cancelled.title == "Setup cancelled")
    }

    @Test func failuresAlwaysHaveANextStep() {
        #expect(status(.notInstalled, outcome: .failed("Disk full.")).action == .tryAgain)
        let blocked = status(.notInstalled, outcome: .blockedByMacOS)
        #expect(blocked.action == .fix && blocked.secondaryAction == .openLoginItems)
        let notRunning = status(.notResponding)
        #expect(notRunning.action == .fix && notRunning.secondaryAction == .openLoginItems)
        #expect(status(.outdated(installed: "0.1.0")).action == .update)
    }

    @Test func busyShowsProgressWithoutButtons() {
        let result = status(.notInstalled, busy: true)
        #expect(result.action == nil && result.title == "Setting up…")
    }

    @Test func readyStatesUseTheToggle() {
        #expect(status(.ready).action == nil && status(.ready).title == "Off")
        #expect(status(.ready, closedLidByDefault: true).title == "On for your next session")
        #expect(status(.ready, session: helperSession(closedLid: true, applied: false)).title == "Getting ready")
        let ready = status(.ready, session: helperSession(closedLid: true, applied: true))
        #expect(ready.title == "Ready to close the lid" && ready.tone == .ready)
        let off = status(.ready, session: helperSession(closedLid: false, applied: false))
        #expect(off.detail.contains("sleeps if you close the lid"))
    }

    @Test func safetyStopExplainsWhy() {
        let result = status(.ready, session: helperSession(closedLid: false, applied: false, notice: "Your Mac needs to cool down."))
        #expect(result.title == "Turned off" && result.detail == "Your Mac needs to cool down." && result.tone == .attention)
    }

    @Test func osascriptErrorsBecomeReadable() {
        #expect(HelperService.firstLine(of: "0:120: execution error: Bootstrap failed: 5: Input/output error (1)\n")
                == "Bootstrap failed: 5: Input/output error")
        #expect(HelperService.firstLine(of: "") == "Unknown error.")
    }
}
