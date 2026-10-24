import Foundation
import Testing
@testable import MattermostSwift

private let lifecycleTestPolicy = MattermostLiveEventReconnectPolicy(initialDelay: .milliseconds(1), maxRetries: 3)

private func typingEvent(_ seq: Int) -> MattermostLiveEvent {
    MattermostLiveEvent(event: "typing", data: [:], broadcast: nil, seq: seq)
}

@Test
func lifecycleOverflowTerminatesWithGapAfterDraining() async throws {
    // The producer overfills a tiny queue without a consumer; the reconnect yield then hits the
    // same full queue. Draining must still end in `liveEventGap` instead of suspending forever.
    let stream = MattermostLiveEventStream.lifecycleEvents(
        policy: lifecycleTestPolicy,
        bufferLimit: 4
    ) { onConnected, _, _, onEvent in
        try await onConnected()
        for seq in 0..<10 { try await onEvent(typingEvent(seq)) }
    }

    let outcome = try await withDeadline(.seconds(5)) {
        do {
            for try await _ in stream {}
            return "finished"
        } catch MattermostError.liveEventGap {
            return "gap"
        }
    }
    #expect(outcome == "gap")
}

@Test
func lifecycleCleanCloseWithoutReconnectFinishes() async throws {
    let policy = MattermostLiveEventReconnectPolicy(reconnectAfterCleanClose: false)
    let stream = MattermostLiveEventStream.lifecycleEvents(policy: policy) { onConnected, _, _, onEvent in
        try await onConnected()
        try await onEvent(typingEvent(1))
    }

    let records = try await withDeadline(.seconds(5)) {
        var records: [String] = []
        for try await record in stream { records.append("\(record)") }
        return records.count
    }
    #expect(records == 3)
}

@Test
func lifecycleCancellationStopsConnection() async throws {
    let stream = MattermostLiveEventStream.lifecycleEvents(policy: lifecycleTestPolicy) { onConnected, _, _, _ in
        try await onConnected()
        try await Task.sleep(for: .seconds(60))
    }
    let consumer = Task {
        for try await _ in stream {}
    }
    try await Task.sleep(for: .milliseconds(50))
    consumer.cancel()
    try await withDeadline(.seconds(5)) { _ = try? await consumer.value }
}

private func withDeadline<T: Sendable>(
    _ limit: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw CancellationError()
        }
        defer { group.cancelAll() }
        return try #require(try await group.next())
    }
}
