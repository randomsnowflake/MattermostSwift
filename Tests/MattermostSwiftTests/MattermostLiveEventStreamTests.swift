import Foundation
import Testing
@testable import MattermostSwift

@Test
func malformedWebSocketFramesEachYieldDecodeFailureAndStreamContinues() async throws {
    let source = MattermostWebSocketFrameSource(frames: [
        Data(#"{"event":"broken""#.utf8),
        Data(#"[]"#.utf8),
        Data(#"{"event":"typing","data":{"channel_id":"channel-1","user_id":"user-1"},"seq":2}"#.utf8),
    ])
    let failures = MattermostRequestLog()
    let events = MattermostRequestLog()
    let stream = try MattermostLiveEventStream(
        configuration: MattermostConfiguration(
            serverURL: #require(URL(string: "https://mattermost.example.com")),
            authentication: .bearerToken("token")
        )
    )

    do {
        try await stream.receiveEvents(
            receiveEnvelope: {
                try await source.nextEnvelope()
            },
            onEventDecodeFailed: { lifecycleEvent in
                guard case .eventDecodeFailed(let failure) = lifecycleEvent else {
                    Issue.record("Expected an eventDecodeFailed lifecycle signal.")
                    return
                }
                failures.append("\(failure.domain):\(failure.code)")
            },
            onEvent: { event in
                events.append("\(event.event):\(event.seq ?? -1)")
            }
        )
        Issue.record("Expected the finite test source to finish the receive loop.")
    } catch MattermostWebSocketFrameSource.EndOfFrames.finished {
        // The sentinel proves the loop requested another frame after the valid event.
    }

    #expect(failures.values.count == 2)
    #expect(events.values == ["typing:2"])
}

private actor MattermostWebSocketFrameSource {
    enum EndOfFrames: Error {
        case finished
    }

    private let frames: [Data]
    private var index = 0

    init(frames: [Data]) {
        self.frames = frames
    }

    func nextEnvelope() throws -> MattermostWebSocketEnvelope {
        guard index < frames.count else {
            throw EndOfFrames.finished
        }
        defer { index += 1 }
        return try mattermostSnakeCaseDecoder.decode(
            MattermostWebSocketEnvelope.self,
            from: frames[index]
        )
    }
}
