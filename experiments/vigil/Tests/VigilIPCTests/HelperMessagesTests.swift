import AwakeCore
import Darwin
import Foundation
import Testing
@testable import VigilIPC

@Suite struct HelperMessagesTests {
    @Test func requestsRoundTrip() throws {
        let session = SessionRequest(endsAt: Date(timeIntervalSince1970: 1_800_000_000), closedLid: true, rules: .standard)
        for request in [HelperRequest.status, .stop, .start(session), .extend(minutes: 15), .setClosedLid(false)] {
            let data = try HelperCoding.encoder().encode(request)
            #expect(try HelperCoding.decoder().decode(HelperRequest.self, from: data) == request)
        }
    }

    @Test func framingSurvivesSplitWritesAndRejectsOversizedMessages() throws {
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { close(pair[0]); close(pair[1]) }
        try UnixSocket.setTimeout(pair[1], 1)
        let body = Data(#"{"command":"status"}"#.utf8)
        try UnixSocket.writeMessage(body, to: pair[0])
        #expect(try UnixSocket.readMessage(from: pair[1]) == body)

        #expect(throws: UnixSocket.Failure.tooLarge) {
            try UnixSocket.writeMessage(Data(count: UnixSocket.maximumMessageBytes), to: pair[0])
        }
    }

    @Test func missingSocketReportsHelperUnavailable() {
        #expect(throws: UnixSocket.Failure.unavailable) {
            try UnixSocket.send(Data("{}".utf8), to: "/tmp/vigil-missing-\(UUID().uuidString.prefix(8)).sock", timeout: 1)
        }
    }
}
