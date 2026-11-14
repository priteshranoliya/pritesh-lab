import AwakeCore
import Foundation
import VigilIPC

// `vigil` — control Vigil sessions from a terminal, script or agent hook.
// Uses the same helper and the same battery/closed-lid settings as the app.

let usage = """
usage: vigil status
       vigil start [30m | 2h | 1h30m | until HH:MM | forever] [--closed-lid]
       vigil stop
       vigil extend [minutes]
       vigil closed-lid on|off
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func send(_ request: HelperRequest) -> HelperStatus {
    do {
        let response = try HelperClient.send(request)
        if let error = response.error { fail(error) }
        return response.status
    } catch UnixSocket.Failure.unavailable {
        fail("Vigil’s helper isn’t installed or running. Open Vigil and finish the one-time setup.")
    } catch {
        fail(error.localizedDescription)
    }
}

/// Parses `45m`, `2h`, `1h30m` into minutes.
func minutes(from text: String) -> Int? {
    var total = 0, number = ""
    for character in text.lowercased() {
        if character.isNumber { number.append(character); continue }
        guard let value = Int(number) else { return nil }
        switch character {
        case "h": total += value * 60
        case "m": total += value
        default: return nil
        }
        number = ""
    }
    if !number.isEmpty { guard let value = Int(number) else { return nil }; total += value }
    return total > 0 ? total : nil
}

func endDate(_ arguments: [String]) -> Date? {
    guard let first = arguments.first else { return Date().addingTimeInterval(30 * 60) }
    if first == "forever" { return nil }
    if first == "until" {
        guard arguments.count > 1 else { fail("Give a time, e.g. vigil start until 18:30") }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let time = formatter.date(from: arguments[1]),
              let next = SessionEndTime.nextOccurrence(of: time) else { fail("Use 24-hour time, e.g. 18:30") }
        return next
    }
    guard let value = minutes(from: first) else { fail(usage, code: 2) }
    return Date().addingTimeInterval(Double(value) * 60)
}

func describe(_ status: HelperStatus) -> String {
    guard let session = status.session else {
        return "No session running." + (status.lastEnd.map { "\nLast session: \($0)" } ?? "")
    }
    var lines: [String] = []
    if let remaining = session.remainingSeconds(at: Date()), let end = session.endsAt {
        lines.append("Awake — \(Countdown.string(seconds: remaining)) left (until \(end.formatted(date: .omitted, time: .shortened)))")
    } else {
        lines.append("Awake — until you stop it")
    }
    lines.append("Closed lid: " + (status.closedLidApplied ? "on (safe to close the lid)" : session.closedLid ? "starting…" : "off"))
    if let notice = session.notice { lines.append(notice) }
    if let problem = status.problem { lines.append("Problem: \(problem)") }
    return lines.joined(separator: "\n")
}

var arguments = Array(CommandLine.arguments.dropFirst())
let closedLid = arguments.contains("--closed-lid")
arguments.removeAll { $0 == "--closed-lid" }

switch arguments.first {
case "status", nil:
    print(describe(send(.status)))
case "start":
    let rules = SessionRulesDefaults.load(from: UserDefaults(suiteName: VigilIdentity.appBundleID) ?? .standard)
    let request = SessionRequest(endsAt: endDate(Array(arguments.dropFirst())), closedLid: closedLid, rules: rules)
    print(describe(send(.start(request))))
case "stop":
    _ = send(.stop)
    print("Session ended.")
case "extend":
    let value = arguments.count > 1 ? Int(arguments[1]) : 15
    guard let value else { fail(usage, code: 2) }
    print(describe(send(.extend(minutes: value))))
case "closed-lid":
    guard arguments.count > 1, ["on", "off"].contains(arguments[1]) else { fail(usage, code: 2) }
    print(describe(send(.setClosedLid(arguments[1] == "on"))))
case "help", "-h", "--help":
    print(usage)
default:
    fail(usage, code: 2)
}
