import Foundation
import Testing
@testable import MattermostSwift

@Test
func webSocketHandshakeSendsAuthenticationBeforeReadingHello() async throws {
    let recorder = AuthenticationFrameRecorder()
    let sequence = TestEnvelopeSequence(
        envelopes: [try webSocketEnvelope(#"{"event":"hello","data":{},"seq":0}"#)],
        beforeFirstEnvelope: {
            guard await recorder.count == 1 else {
                throw HandshakeTestError.authenticationWasNotSentFirst
            }
        }
    )

    let pendingEvents = try await MattermostLiveEventStream.performAuthenticationHandshake(
        token: "secret-token",
        envelopes: sequence,
        sendAuthenticationFrame: { await recorder.append($0) }
    )

    let recordedFrame = await recorder.firstFrame()
    let frame = try #require(recordedFrame)
    let authentication = try JSONDecoder().decode(TestAuthenticationFrame.self, from: Data(frame.utf8))
    #expect(authentication.seq == 1)
    #expect(authentication.action == "authentication_challenge")
    #expect(authentication.data.token == "secret-token")
    #expect(pendingEvents.map(\.event) == ["hello"])
}

@Test
func webSocketHandshakePreservesEventsUntilMatchingOKReply() async throws {
    let sequence = TestEnvelopeSequence(envelopes: [
        try webSocketEnvelope(#"{"event":"posted","data":{"channel_id":"channel-1"},"seq":4}"#),
        try webSocketEnvelope(#"{"seq_reply":99,"status":"OK"}"#),
        try webSocketEnvelope(#"{"seq_reply":1,"status":"OK"}"#),
    ])

    let pendingEvents = try await MattermostLiveEventStream.performAuthenticationHandshake(
        token: "token",
        envelopes: sequence,
        sendAuthenticationFrame: { _ in }
    )

    #expect(pendingEvents.map(\.event) == ["posted"])
    #expect(pendingEvents.first?.stringData("channel_id") == "channel-1")
}

@Test
func webSocketHandshakeReportsMatchingAuthenticationFailure() async throws {
    let sequence = TestEnvelopeSequence(envelopes: [
        try webSocketEnvelope(
            #"{"seq_reply":1,"status":"FAIL","error":{"message":"invalid token"}}"#
        ),
    ])

    await #expect(throws: MattermostError.transportFailure(
        "Mattermost WebSocket authentication failed: invalid token"
    )) {
        _ = try await MattermostLiveEventStream.performAuthenticationHandshake(
            token: "token",
            envelopes: sequence,
            sendAuthenticationFrame: { _ in }
        )
    }
}

@Test
func webSocketHandshakeFailsIfEnvelopeSequenceEndsBeforeAuthentication() async throws {
    let sequence = TestEnvelopeSequence(envelopes: [
        try webSocketEnvelope(#"{"seq_reply":2,"status":"OK"}"#),
    ])

    await #expect(throws: MattermostError.transportFailure(
        "Mattermost WebSocket closed before authentication completed."
    )) {
        _ = try await MattermostLiveEventStream.performAuthenticationHandshake(
            token: "token",
            envelopes: sequence,
            sendAuthenticationFrame: { _ in }
        )
    }
}

private func webSocketEnvelope(_ json: String) throws -> MattermostWebSocketEnvelope {
    try mattermostSnakeCaseDecoder.decode(MattermostWebSocketEnvelope.self, from: Data(json.utf8))
}

private struct TestAuthenticationFrame: Decodable {
    let seq: Int
    let action: String
    let data: DataPayload

    struct DataPayload: Decodable {
        let token: String
    }
}

private enum HandshakeTestError: Error, Sendable {
    case authenticationWasNotSentFirst
}

private actor AuthenticationFrameRecorder {
    private var frames: [String] = []

    var count: Int {
        frames.count
    }

    func append(_ frame: String) {
        frames.append(frame)
    }

    func firstFrame() -> String? {
        frames.first
    }
}

private struct TestEnvelopeSequence: AsyncSequence, Sendable {
    typealias Element = MattermostWebSocketEnvelope

    let envelopes: [MattermostWebSocketEnvelope]
    let beforeFirstEnvelope: @Sendable () async throws -> Void

    init(
        envelopes: [MattermostWebSocketEnvelope],
        beforeFirstEnvelope: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.envelopes = envelopes
        self.beforeFirstEnvelope = beforeFirstEnvelope
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            envelopes: envelopes,
            beforeFirstEnvelope: beforeFirstEnvelope
        )
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let envelopes: [MattermostWebSocketEnvelope]
        let beforeFirstEnvelope: @Sendable () async throws -> Void
        var index = 0

        mutating func next() async throws -> MattermostWebSocketEnvelope? {
            if index == 0 {
                try await beforeFirstEnvelope()
            }
            guard index < envelopes.count else { return nil }
            defer { index += 1 }
            return envelopes[index]
        }
    }
}
