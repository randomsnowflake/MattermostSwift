import Foundation

/// A Mattermost WebSocket event stream for one authenticated client.
public struct MattermostLiveEventStream: Sendable {
    private let configuration: MattermostConfiguration
    private let urlSession: URLSession
    let heartbeatInterval: Duration
    let heartbeatTimeout: Duration

    public init(
        configuration: MattermostConfiguration,
        urlSession: URLSession = .mattermost,
        heartbeatInterval: Duration = .seconds(25),
        heartbeatTimeout: Duration = .seconds(10)
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
    }

    /// Connects, authenticates, and yields server events until cancelled or the socket fails.
    public func events() -> AsyncThrowingStream<MattermostLiveEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            let streamTask = Task {
                do {
                    try await runAuthenticatedConnection(
                        onConnected: {},
                        onEvent: { continuation.yield($0) }
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
            }
        }
    }

    func makeWebSocketRequest() -> URLRequest {
        var request = URLRequest(url: configuration.webSocketURL)
        MattermostUserAgent.applyBrowserUserAgent(to: &request)
        if case .bearerToken(let token) = configuration.authentication {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Yields connection lifecycle notifications and live events, reconnecting with exponential backoff.
    public func lifecycleEvents(
        policy: MattermostLiveEventReconnectPolicy = .default
    ) -> AsyncThrowingStream<MattermostLiveEventStreamLifecycleEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            let streamTask = Task {
                var attempt = 0

                while !Task.isCancelled {
                    continuation.yield(.connecting(attempt: attempt))

                    let connectedAt = ContinuousClock.now
                    let currentAttempt = attempt
                    do {
                        try await runAuthenticatedConnection(
                            onConnected: {
                                continuation.yield(.connected(attempt: currentAttempt))
                            },
                            onEvent: { event in
                                continuation.yield(.event(event))
                            }
                        )

                        if Self.connectionWasStable(since: connectedAt) { attempt = 0 }
                        guard policy.reconnectAfterCleanClose, policy.canRetry(attempt: attempt) else {
                            continuation.finish()
                            return
                        }
                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch {
                        let failure = MattermostLiveEventStreamFailure(error: error)
                        if Self.connectionWasStable(since: connectedAt) { attempt = 0 }
                        guard policy.canRetry(attempt: attempt) else {
                            continuation.finish(throwing: error)
                            return
                        }
                        let delay = policy.delay(for: attempt)
                        continuation.yield(.reconnecting(attempt: attempt, delay: delay, failure: failure))
                        do {
                            try await Task.sleep(for: delay)
                        } catch {
                            continuation.finish()
                            return
                        }
                        attempt += 1
                        continue
                    }

                    let delay = policy.delay(for: attempt)
                    continuation.yield(.reconnecting(attempt: attempt, delay: delay))
                    do {
                        try await Task.sleep(for: delay)
                    } catch {
                        continuation.finish()
                        return
                    }
                    attempt += 1
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
            }
        }
    }

    private func runAuthenticatedConnection(
        onConnected: @escaping @Sendable () async -> Void,
        onEvent: @escaping @Sendable (MattermostLiveEvent) -> Void
    ) async throws {
        let webSocketTask = urlSession.webSocketTask(with: makeWebSocketRequest())
        webSocketTask.resume()
        defer {
            webSocketTask.cancel(with: .goingAway, reason: nil)
        }

        let pendingEvents = try await authenticate(webSocketTask)
        await onConnected()
        for event in pendingEvents {
            onEvent(event)
        }

        // A non-positive heartbeat configuration explicitly disables pinging; it must not
        // add a child task that returns immediately and tears down an otherwise healthy
        // receive loop through the task-group race below.
        guard isHeartbeatEnabled else {
            try await receiveEvents(from: webSocketTask, onEvent: onEvent)
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.receiveEvents(from: webSocketTask, onEvent: onEvent)
            }
            if isHeartbeatEnabled {
                group.addTask {
                    try await self.keepConnectionAlive(webSocketTask)
                }
            }

            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                webSocketTask.cancel(with: .goingAway, reason: nil)
                group.cancelAll()
                throw error
            }
        }
    }

    private func receiveEvents(
        from webSocketTask: URLSessionWebSocketTask,
        onEvent: @escaping @Sendable (MattermostLiveEvent) -> Void
    ) async throws {
        while !Task.isCancelled {
            if let event = try await receiveEvent(from: webSocketTask) {
                onEvent(event)
            }
        }
    }

    private func keepConnectionAlive(_ webSocketTask: URLSessionWebSocketTask) async throws {
        guard isHeartbeatEnabled else { return }
        while !Task.isCancelled {
            try await Task.sleep(for: heartbeatInterval)
            try Task.checkCancellation()
            try await Self.withTimeout(
                heartbeatTimeout,
                timeoutMessage: "Mattermost WebSocket ping timed out.",
                onTimeout: {
                    webSocketTask.cancel(with: .goingAway, reason: nil)
                }
            ) {
                try await self.sendPing(to: webSocketTask)
            }
        }
    }

    var isHeartbeatEnabled: Bool {
        heartbeatInterval > .zero && heartbeatTimeout > .zero
    }

    private func authenticate(_ webSocketTask: URLSessionWebSocketTask) async throws -> [MattermostLiveEvent] {
        // Bound the handshake: a server that upgrades the socket but never sends `hello`
        // or an auth reply would otherwise hang this loop forever.
        try await Self.withTimeout(
            .seconds(15),
            timeoutMessage: "Mattermost WebSocket authentication timed out."
        ) {
            let authSequence = 1
            let token: String
            switch self.configuration.authentication {
            case .none:
                throw MattermostError.transportFailure("Mattermost WebSocket authentication requires a token.")
            case .bearerToken(let bearerToken):
                token = bearerToken
            }

            let auth = MattermostWebSocketAuthentication(
                seq: authSequence,
                action: "authentication_challenge",
                data: MattermostWebSocketAuthenticationData(token: token)
            )
            // Must be a TEXT frame: Mattermost silently drops the socket right after `hello`
            // if the authentication_challenge arrives as a binary frame.
            let payload = try mattermostSnakeCaseEncoder.encode(auth)
            try await self.send(.string(String(decoding: payload, as: UTF8.self)), to: webSocketTask)

            var pendingEvents: [MattermostLiveEvent] = []
            while !Task.isCancelled {
                let envelope = try await self.receiveEnvelope(from: webSocketTask)

                if let event = envelope.liveEvent {
                    pendingEvents.append(event)
                    if event.event == "hello" {
                        return pendingEvents
                    }
                }

                if envelope.seqReply == authSequence {
                    if envelope.status == "OK" {
                        return pendingEvents
                    }

                    let message = envelope.error?.message ?? envelope.status ?? "authentication failed"
                    throw MattermostError.transportFailure("Mattermost WebSocket authentication failed: \(message)")
                }
            }

            throw CancellationError()
        }
    }

    private static let connectionStabilityWindow: Duration = .seconds(30)

    /// Treats a connection that stayed up at least `connectionStabilityWindow` as a fresh
    /// success, so backoff only escalates for a genuinely flapping server.
    private static func connectionWasStable(since start: ContinuousClock.Instant) -> Bool {
        ContinuousClock.now - start >= connectionStabilityWindow
    }

    /// Runs `operation`, failing with a transport error if it does not finish within `duration`.
    static func withTimeout<T: Sendable>(
        _ duration: Duration,
        timeoutMessage: String,
        onTimeout: @escaping @Sendable () -> Void = {},
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: MattermostTimeoutResult<T>.self) { group in
            group.addTask { .value(try await operation()) }
            group.addTask {
                try await Task.sleep(for: duration)
                return .timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            switch result {
            case .value(let value):
                return value
            case .timedOut:
                // Run the teardown only after the timer is known to be the task group's
                // first completed result. A near-simultaneous successful ping must not
                // spuriously cancel a healthy WebSocket.
                onTimeout()
                throw MattermostError.transportFailure(timeoutMessage)
            }
        }
    }


    private func receiveEvent(from webSocketTask: URLSessionWebSocketTask) async throws -> MattermostLiveEvent? {
        do {
            return try await receiveEnvelope(from: webSocketTask).liveEvent
        } catch is DecodingError {
            return nil
        }
    }

    private func receiveEnvelope(from webSocketTask: URLSessionWebSocketTask) async throws -> MattermostWebSocketEnvelope {
        let message = try await receive(from: webSocketTask)
        let data: Data
        switch message {
        case .data(let messageData):
            data = messageData
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            throw MattermostError.transportFailure("Mattermost WebSocket returned an unsupported message type.")
        }

        return try mattermostSnakeCaseDecoder.decode(MattermostWebSocketEnvelope.self, from: data)
    }

    private func send(_ message: URLSessionWebSocketTask.Message, to webSocketTask: URLSessionWebSocketTask) async throws {
        try await webSocketTask.send(message)
    }

    private func sendPing(to webSocketTask: URLSessionWebSocketTask) async throws {
        let state = MattermostPingContinuation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                webSocketTask.sendPing { error in
                    state.finish(error)
                }
            }
        } onCancel: {
            webSocketTask.cancel(with: .goingAway, reason: nil)
            state.finish(CancellationError())
        }
    }

    private func receive(from webSocketTask: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
        // Cancel the socket on Task cancellation so a suspended receive on a quiet channel
        // tears down promptly instead of waiting for the next server message.
        try await withTaskCancellationHandler {
            try await webSocketTask.receive()
        } onCancel: {
            webSocketTask.cancel(with: .goingAway, reason: nil)
        }
    }
}

private enum MattermostTimeoutResult<Value: Sendable>: Sendable {
    case value(Value)
    case timedOut
}
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

/// Backoff controls for reconnecting Mattermost WebSocket event streams.
public struct MattermostLiveEventReconnectPolicy: Equatable, Sendable {
    // Keep a margin below `Int.max`: converting a rounded `Double(Int.max)` can
    // otherwise cross the signed-integer boundary on some architectures.
    private static let maximumDelayMilliseconds = Int.max / 2
    private static let maximumDelaySeconds = Double(maximumDelayMilliseconds) / 1_000

    public static let `default` = MattermostLiveEventReconnectPolicy()

    public static let disabled = MattermostLiveEventReconnectPolicy(maxRetries: 0)

    public let initialDelaySeconds: Double
    public let maxDelaySeconds: Double
    public let multiplier: Double
    public let maxRetries: Int?
    public let reconnectAfterCleanClose: Bool

    public init(
        initialDelaySeconds: Double = 1,
        maxDelaySeconds: Double = 60,
        multiplier: Double = 2,
        maxRetries: Int? = nil,
        reconnectAfterCleanClose: Bool = true
    ) {
        let initial = Self.normalizedDelay(initialDelaySeconds, fallback: 1)
        self.initialDelaySeconds = initial
        self.maxDelaySeconds = max(
            initial,
            Self.normalizedDelay(maxDelaySeconds, fallback: 60)
        )
        self.multiplier = multiplier.isFinite && multiplier >= 1 ? multiplier : 1
        self.maxRetries = maxRetries.map { max(0, $0) }
        self.reconnectAfterCleanClose = reconnectAfterCleanClose
    }

    public func canRetry(attempt: Int) -> Bool {
        guard let maxRetries else {
            return true
        }
        return attempt < maxRetries
    }

    public func delay(for attempt: Int) -> Duration {
        let exponent = pow(multiplier, Double(max(0, attempt)))
        let computedSeconds = initialDelaySeconds * exponent
        let delaySeconds = computedSeconds.isFinite
            ? min(maxDelaySeconds, computedSeconds)
            : maxDelaySeconds
        let milliseconds = min(
            Self.maximumDelayMilliseconds,
            max(0, Int(delaySeconds * 1_000))
        )
        return .milliseconds(milliseconds)
    }

    private static func normalizedDelay(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite, value >= 0 else { return fallback }
        return min(value, maximumDelaySeconds)
    }
}

private struct MattermostWebSocketAuthentication: Encodable, Sendable {
    let seq: Int
    let action: String
    let data: MattermostWebSocketAuthenticationData
}

private struct MattermostWebSocketAuthenticationData: Encodable, Sendable {
    let token: String
}

struct MattermostWebSocketEnvelope: Decodable, Sendable {
    let event: String?
    let data: [String: MattermostJSONValue]?
    let broadcast: MattermostLiveBroadcast?
    let seq: Int?
    let seqReply: Int?
    let status: String?
    let error: MattermostWebSocketError?

    private enum CodingKeys: String, CodingKey {
        case event
        case data
        case broadcast
        case seq
        case seqReply
        case status
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = Self.decodeIfPresent(String.self, from: container, forKey: .event)
        data = Self.decodeIfPresent([String: MattermostJSONValue].self, from: container, forKey: .data)
        broadcast = Self.decodeIfPresent(MattermostLiveBroadcast.self, from: container, forKey: .broadcast)
        seq = Self.decodeInt(container, forKey: .seq)
        seqReply = Self.decodeInt(container, forKey: .seqReply)
        status = Self.decodeIfPresent(String.self, from: container, forKey: .status)
        error = Self.decodeIfPresent(MattermostWebSocketError.self, from: container, forKey: .error)
    }

    var liveEvent: MattermostLiveEvent? {
        guard let event else {
            return nil
        }
        return MattermostLiveEvent(
            event: event,
            data: data ?? [:],
            broadcast: broadcast,
            seq: seq
        )
    }

    private static func decodeIfPresent<Value: Decodable>(
        _ type: Value.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Value? {
        do {
            return try container.decodeIfPresent(type, forKey: key)
        } catch {
            return nil
        }
    }

    private static func decodeInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

struct MattermostWebSocketError: Decodable, Sendable {
    let message: String?
}

/// Shared snake_case coders reused by API and WebSocket payload handling.
let mattermostSnakeCaseDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()

let mattermostSnakeCaseEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
}()
