import Testing
@testable import MattermostSwift

@MainActor
@Test
func boundedConcurrentMapLimitsWidthAndPreservesInputAssociation() async throws {
    var inFlight = 0
    var maximumInFlight = 0

    let results = try await mattermostBoundedConcurrentMap(Array(0..<12)) { value in
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }

        // Finish neighboring inputs in reverse order to prove output association does not
        // depend on task-group completion order.
        try await Task.sleep(for: .milliseconds((8 - value % 8) * 5))
        return "result-\(value)"
    }

    #expect(maximumInFlight == 8)
    #expect(results == (0..<12).map { "result-\($0)" })
}

@MainActor
@Test
func boundedConcurrentMapPropagatesCancellationWithoutStartingQueuedWork() async {
    var startedCount = 0
    let task = Task { @MainActor in
        try await mattermostBoundedConcurrentMap(
            Array(0..<12),
            width: 3
        ) { value in
            startedCount += 1
            try await Task.sleep(for: .seconds(60))
            return value
        }
    }

    while startedCount < 3 {
        await Task.yield()
    }
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Expected bounded fan-out cancellation to propagate.")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Expected CancellationError, got \(error).")
    }

    #expect(startedCount == 3)
}
