import Foundation

// Callback-to-async bridges used by the WebSocket connection: ping replies and one-shot completions.

/// Bridges URLSessionWebSocketTask.sendPing's callback API to cancellation-aware
/// async code. Both cancellation and the callback may race; only the first one
/// resumes the continuation.
final class MattermostPingContinuation: @unchecked Sendable {
    private enum Completion {
        case success
        case failure(Error)
    }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var completion: Completion?

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        let completion = lock.withLock { () -> Completion? in
            if let completion = self.completion {
                return completion
            }
            self.continuation = continuation
            return nil
        }
        guard let completion else { return }
        switch completion {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func finish(_ error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard completion == nil else { return nil }
            completion = error.map(Completion.failure) ?? .success
            defer { self.continuation = nil }
            return self.continuation
        }
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

final class MattermostOneShotCallback<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (Value) -> Void)?

    init(_ callback: @escaping @Sendable (Value) -> Void) {
        self.callback = callback
    }

    func callAsFunction(_ value: Value) {
        let callback = lock.withLock {
            defer { self.callback = nil }
            return self.callback
        }
        callback?(value)
    }
}
