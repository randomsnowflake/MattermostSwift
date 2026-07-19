import Foundation
import Testing
@testable import MattermostSwift

@Test
func pingContinuationCompletesIfCallbackWinsRaceBeforeInstall() async throws {
    let state = MattermostPingContinuation()
    state.finish(MattermostError.transportFailure("ping failed before install"))

    do {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.install(continuation)
        }
        Issue.record("Expected stored ping failure to resume the continuation.")
    } catch MattermostError.transportFailure(let message) {
        #expect(message == "ping failed before install")
    } catch {
        Issue.record("Expected MattermostError.transportFailure, got \(error).")
    }
}

@Test
func pingContinuationIgnoresSecondCompletionAfterInstall() async throws {
    let state = MattermostPingContinuation()

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        state.install(continuation)
        state.finish(nil)
        state.finish(MattermostError.transportFailure("late duplicate"))
    }
}

@Test
func timeoutDoesNotRunTeardownWhenOperationWins() async throws {
    let calls = MattermostRequestLog()

    let value = try await MattermostLiveEventStream.withTimeout(
        .seconds(1),
        timeoutMessage: "should not time out",
        onTimeout: { calls.append("timeout") }
    ) {
        42
    }

    #expect(value == 42)
    #expect(calls.values.isEmpty)
}

@Test
func timeoutRunsTeardownAfterTimerWins() async throws {
    let calls = MattermostRequestLog()

    await #expect(throws: MattermostError.self) {
        _ = try await MattermostLiveEventStream.withTimeout(
            .milliseconds(10),
            timeoutMessage: "expected timeout",
            onTimeout: { calls.append("timeout") }
        ) {
            try await Task.sleep(for: .seconds(1))
            return 42
        }
    }

    #expect(calls.values == ["timeout"])
}

@Test("WebSocket heartbeat accepts only a running URLSession task", arguments: [
    URLSessionTask.State.suspended,
    .canceling,
    .completed,
])
func webSocketHeartbeatRejectsUnavailableTaskStates(_ state: URLSessionTask.State) {
    #expect(throws: MattermostError.self) {
        try MattermostLiveEventStream.validateWebSocketTaskState(state)
    }
}

@Test
func webSocketHeartbeatAcceptsRunningTaskState() throws {
    try MattermostLiveEventStream.validateWebSocketTaskState(.running)
}
