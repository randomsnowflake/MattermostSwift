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
