import Foundation

/// Everything the closed-lid card shows, derived from state in one place so
/// every combination has a clear message and a next step. Pure and tested.
struct ClosedLidStatus: Equatable {
    enum Tone: Equatable { case ready, neutral, attention }

    enum Action: Equatable {
        case setUp, tryAgain, update, fix, openLoginItems

        var title: String {
            switch self {
            case .setUp: "Set up…"
            case .tryAgain: "Try again…"
            case .update: "Update…"
            case .fix: "Fix…"
            case .openLoginItems: "Open Login Items"
            }
        }
    }

    var title: String
    var detail: String
    var tone: Tone
    var symbol: String
    /// Main button. When nil, the closed-lid toggle is shown instead.
    var action: Action?
    var secondaryAction: Action?

    static func make(installation: HelperService.Installation, busy: Bool,
                     outcome: HelperService.SetupOutcome?, session: DisplayedSession?,
                     closedLidByDefault: Bool) -> ClosedLidStatus {
        if busy {
            return .init(title: "Setting up…", detail: "Enter your Mac password in the window that appears.",
                         tone: .neutral, symbol: "lock", action: nil)
        }

        switch installation {
        case .notInstalled:
            switch outcome {
            case .cancelled:
                return .init(title: "Setup cancelled",
                             detail: "Nothing was changed. Sessions need this one-time setup — it takes one password.",
                             tone: .neutral, symbol: "xmark.circle", action: .setUp)
            case .blockedByMacOS:
                return blocked
            case .failed(let reason):
                return .init(title: "Setup didn’t finish", detail: "\(reason) Try again; your settings are unchanged.",
                             tone: .attention, symbol: "exclamationmark.triangle.fill", action: .tryAgain)
            case nil:
                return .init(title: "Not set up",
                             detail: "Set up once with your Mac password. Then sessions keep running with the lid closed, even if Vigil quits.",
                             tone: .neutral, symbol: "laptopcomputer", action: .setUp)
            }
        case .notResponding:
            return outcome == .blockedByMacOS ? blocked :
                .init(title: "Helper isn’t running",
                      detail: "macOS may have switched it off. Click Fix… to reinstall it with your password.",
                      tone: .attention, symbol: "exclamationmark.triangle.fill", action: .fix,
                      secondaryAction: .openLoginItems)
        case .outdated:
            return .init(title: "Update needed",
                         detail: "This Vigil is newer than its helper. Update once with your password; a running session keeps going.",
                         tone: .attention, symbol: "arrow.triangle.2.circlepath", action: .update)
        case .ready:
            break
        }

        guard let session else {
            return closedLidByDefault
                ? .init(title: "On for your next session", detail: "Start a session, then wait for “Ready to close the lid”.",
                        tone: .neutral, symbol: "clock", action: nil)
                : .init(title: "Off", detail: "Your Mac sleeps when you close the lid. Turn on to keep working with it closed.",
                        tone: .neutral, symbol: "moon", action: nil)
        }
        if session.closedLid && session.closedLidApplied {
            return .init(title: "Ready to close the lid",
                         detail: "Keeps running even if Vigil quits. Stops at your battery limit or if your Mac gets hot.",
                         tone: .ready, symbol: "checkmark.circle.fill", action: nil)
        }
        if session.closedLid {
            return .init(title: "Getting ready", detail: "Keep the lid open for a moment.",
                         tone: .neutral, symbol: "clock", action: nil)
        }
        if let notice = session.notice {
            return .init(title: "Turned off", detail: notice, tone: .attention,
                         symbol: "exclamationmark.triangle.fill", action: nil)
        }
        return .init(title: "Off — keep the lid open", detail: "Your Mac sleeps if you close the lid. Turn on to keep working with it closed.",
                     tone: .neutral, symbol: "moon", action: nil)
    }

    private static let blocked = ClosedLidStatus(
        title: "macOS blocked the helper",
        detail: "In Login Items & Extensions, turn on “app.vigil.Vigil.helper” (under Allow in the Background), then click Fix….",
        tone: .attention, symbol: "exclamationmark.triangle.fill", action: .fix, secondaryAction: .openLoginItems)
}
