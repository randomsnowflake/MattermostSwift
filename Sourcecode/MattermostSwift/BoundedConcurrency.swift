import Foundation

private struct MattermostIndexedTaskResult<Value: Sendable>: Sendable {
    let index: Int
    let value: Value
}

/// Runs an async transform with manual task-group backpressure and returns results in input order.
///
/// This stays internal so SDK fan-out uses one concurrency policy without exposing scheduling as
/// public API. The operation is main-actor isolated because current consumers coordinate
/// `MattermostStore` mutations there; each operation can still overlap while suspended on HTTP.
@MainActor
func mattermostBoundedConcurrentMap<Input: Sendable, Output: Sendable>(
    _ inputs: [Input],
    width: Int = 8,
    operation: @escaping @MainActor @Sendable (Input) async throws -> Output
) async throws -> [Output] {
    let maximumInFlight = max(1, width)

    return try await withThrowingTaskGroup(
        of: MattermostIndexedTaskResult<Output>.self
    ) { group in
        var iterator = inputs.enumerated().makeIterator()
        var inFlight = 0
        var indexedResults: [MattermostIndexedTaskResult<Output>] = []
        indexedResults.reserveCapacity(inputs.count)

        func fill() {
            while inFlight < maximumInFlight, let input = iterator.next() {
                inFlight += 1
                group.addTask {
                    let value = try await operation(input.element)
                    return MattermostIndexedTaskResult(index: input.offset, value: value)
                }
            }
        }

        fill()
        while let result = try await group.next() {
            indexedResults.append(result)
            inFlight -= 1
            fill()
        }

        return indexedResults
            .sorted { $0.index < $1.index }
            .map(\.value)
    }
}
