import Foundation

/// A Mattermost WebSocket event stream for one authenticated client.
public struct MattermostLiveEventStream: Sendable {
    private let configuration: MattermostConfiguration
    let urlSession: URLSession
    let heartbeatInterval: Duration
    let heartbeatTimeout: Duration

    public init(
        configuration: MattermostConfiguration,
        urlSession: URLSession = .mattermostLiveEvents,
        heartbeatInterval: Duration = .seconds(25),
        heartbeatTimeout: Duration = .seconds(10)
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
    }

    /// Connects, authenticates, and yields server events until cancelled or the socket fails.
    /// The queue holds at most 256 events; a slow consumer receives `MattermostError.liveEventGap`
    /// rather than silently observing an incomplete sequence.
    public func events() -> AsyncThrowingStream<MattermostLiveEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            let streamTask = Task {
                do {
                    try await runAuthenticatedConnection(
                        onConnected: {},
                        onEventDecodeFailed: { _ in },
                        onEvent: { try Self.yield($0, to: continuation) }
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
    /// Malformed event frames yield `eventDecodeFailed` and are skipped without closing the connection.
    /// Its queue holds at most 512 lifecycle records. Ingress overflow aborts the current socket
    /// generation and follows the normal reconnect/backfill path instead of hiding a gap.
    public func lifecycleEvents(
        policy: MattermostLiveEventReconnectPolicy = .default
    ) -> AsyncThrowingStream<MattermostLiveEventStreamLifecycleEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(512)) { continuation in
            let streamTask = Task {
                var attempt = 0

                while !Task.isCancelled {
                    try Self.yield(.connecting(attempt: attempt), to: continuation)

                    let connectedAt = ContinuousClock.now
                    let currentAttempt = attempt
                    do {
                        try await runAuthenticatedConnection(
                            onConnected: {
                                try Self.yield(.connected(attempt: currentAttempt), to: continuation)
                            },
                            onEventDecodeFailed: { try Self.yield($0, to: continuation) },
                            onEvent: { event in
                                try Self.yield(.event(event), to: continuation)
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
                        try Self.yield(.reconnecting(attempt: attempt, delay: delay, failure: failure), to: continuation)
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
                    try Self.yield(.reconnecting(attempt: attempt, delay: delay), to: continuation)
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
        onConnected: @escaping @Sendable () async throws -> Void,
        onEventDecodeFailed: @escaping @Sendable (MattermostLiveEventStreamLifecycleEvent) async throws -> Void,
        onEvent: @escaping @Sendable (MattermostLiveEvent) async throws -> Void
    ) async throws {
        let webSocketTask = urlSession.webSocketTask(with: makeWebSocketRequest())
        webSocketTask.resume()
        defer {
            webSocketTask.cancel(with: .goingAway, reason: nil)
        }

        let pendingEvents = try await authenticate(webSocketTask)
        try await onConnected()
        for event in pendingEvents {
            try await onEvent(event)
        }

        // A non-positive heartbeat configuration explicitly disables pinging; it must not
        // add a child task that returns immediately and tears down an otherwise healthy
        // receive loop through the task-group race below.
        guard isHeartbeatEnabled else {
            try await receiveEvents(
                from: webSocketTask,
                onEventDecodeFailed: onEventDecodeFailed,
                onEvent: onEvent
            )
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.receiveEvents(
                    from: webSocketTask,
                    onEventDecodeFailed: onEventDecodeFailed,
                    onEvent: onEvent
                )
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
        onEventDecodeFailed: @escaping @Sendable (MattermostLiveEventStreamLifecycleEvent) async throws -> Void,
        onEvent: @escaping @Sendable (MattermostLiveEvent) async throws -> Void
    ) async throws {
        try await receiveEvents(
            receiveEnvelope: { try await self.receiveEnvelope(from: webSocketTask) },
            onEventDecodeFailed: onEventDecodeFailed,
            onEvent: onEvent
        )
    }

    func receiveEvents(
        receiveEnvelope: @escaping @Sendable () async throws -> MattermostWebSocketEnvelope,
        onEventDecodeFailed: @escaping @Sendable (MattermostLiveEventStreamLifecycleEvent) async throws -> Void,
        onEvent: @escaping @Sendable (MattermostLiveEvent) async throws -> Void
    ) async throws {
        while !Task.isCancelled {
            if let event = try await receiveEvent(
                receiveEnvelope: receiveEnvelope,
                onEventDecodeFailed: onEventDecodeFailed
            ) {
                try await onEvent(event)
            }
        }
    }

    private func keepConnectionAlive(_ webSocketTask: URLSessionWebSocketTask) async throws {
        guard isHeartbeatEnabled else { return }
        while !Task.isCancelled {
            try await Task.sleep(for: heartbeatInterval)
            try Task.checkCancellation()
            // CFNetwork can mark a WebSocket task cancelled after route loss without
            // promptly resuming an outstanding receive or ping callback. Checking the
            // URLSession task state on every heartbeat turns that silent half-dead
            // connection into the normal reconnect path.
            try Self.validateWebSocketTaskState(webSocketTask.state)
            try await Self.withTimeout(
                heartbeatTimeout,
                timeoutMessage: "Mattermost WebSocket ping timed out.",
                onTimeout: {
                    webSocketTask.cancel(with: .goingAway, reason: nil)
                }
            ) {
                try await self.sendPing(to: webSocketTask)
            }
            try Self.validateWebSocketTaskState(webSocketTask.state)
        }
    }

    var isHeartbeatEnabled: Bool {
        heartbeatInterval > .zero && heartbeatTimeout > .zero
    }

    static func validateWebSocketTaskState(_ state: URLSessionTask.State) throws {
        guard state == .running else {
            throw MattermostError.transportFailure(
                "Mattermost WebSocket task became unavailable (state \(state.rawValue))."
            )
        }
    }

    private static func yield<Element: Sendable>(
        _ element: Element,
        to continuation: AsyncThrowingStream<Element, Error>.Continuation
    ) throws {
        switch continuation.yield(element) {
        case .enqueued:
            return
        case .dropped:
            throw MattermostError.liveEventGap
        case .terminated:
            throw CancellationError()
        @unknown default:
            throw MattermostError.liveEventGap
        }
    }

    private func authenticate(_ webSocketTask: URLSessionWebSocketTask) async throws -> [MattermostLiveEvent] {
        // Bound the handshake: a server that upgrades the socket but never sends `hello`
        // or an auth reply would otherwise hang this loop forever.
        try await Self.withTimeout(
            .seconds(15),
            timeoutMessage: "Mattermost WebSocket authentication timed out."
        ) {
            let token: String
            switch self.configuration.authentication {
            case .none:
                throw MattermostError.transportFailure("Mattermost WebSocket authentication requires a token.")
            case .bearerToken(let bearerToken):
                token = bearerToken
            }

            let envelopes = MattermostWebSocketEnvelopeSequence {
                try await self.receiveEnvelope(from: webSocketTask)
            }
            return try await Self.performAuthenticationHandshake(
                token: token,
                envelopes: envelopes
            ) { frame in
                // Must be a TEXT frame: Mattermost silently drops the socket right after
                // `hello` if the authentication_challenge arrives as a binary frame.
                try await self.send(.string(frame), to: webSocketTask)
            }
        }
    }

    static func performAuthenticationHandshake<Envelopes: AsyncSequence & Sendable>(
        token: String,
        authSequence: Int = 1,
        envelopes: Envelopes,
        sendAuthenticationFrame: @escaping @Sendable (String) async throws -> Void
    ) async throws -> [MattermostLiveEvent] where Envelopes.Element == MattermostWebSocketEnvelope {
        let auth = MattermostWebSocketAuthentication(
            seq: authSequence,
            action: "authentication_challenge",
            data: MattermostWebSocketAuthenticationData(token: token)
        )
        let payload = try mattermostSnakeCaseEncoder.encode(auth)
        try await sendAuthenticationFrame(String(decoding: payload, as: UTF8.self))

        var pendingEvents: [MattermostLiveEvent] = []
        for try await envelope in envelopes {
            if let event = envelope.liveEvent {
                try appendPendingHandshakeEvent(event, to: &pendingEvents)
                if event.event == MattermostLiveEventName.hello.rawValue {
                    return pendingEvents
                }
            }

            guard envelope.seqReply == authSequence else { continue }
            if envelope.status == "OK" {
                return pendingEvents
            }

            let message = envelope.error?.message ?? envelope.status ?? "authentication failed"
            throw MattermostError.transportFailure("Mattermost WebSocket authentication failed: \(message)")
        }

        try Task.checkCancellation()
        throw MattermostError.transportFailure(
            "Mattermost WebSocket closed before authentication completed."
        )
    }

    static let maximumPendingHandshakeEvents = 256

    static func appendPendingHandshakeEvent(
        _ event: MattermostLiveEvent,
        to pendingEvents: inout [MattermostLiveEvent]
    ) throws {
        guard pendingEvents.count < maximumPendingHandshakeEvents else {
            throw MattermostError.liveEventGap
        }
        pendingEvents.append(event)
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


    private func receiveEvent(
        receiveEnvelope: @escaping @Sendable () async throws -> MattermostWebSocketEnvelope,
        onEventDecodeFailed: @escaping @Sendable (MattermostLiveEventStreamLifecycleEvent) async throws -> Void
    ) async throws -> MattermostLiveEvent? {
        do {
            return try await receiveEnvelope().liveEvent
        } catch let error as DecodingError {
            try await onEventDecodeFailed(
                .eventDecodeFailed(MattermostLiveEventStreamFailure(error: error))
            )
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

    /// Returns a full-jitter reconnect delay from zero through the capped exponential backoff.
    public func delay(for attempt: Int) -> Duration {
        delay(for: attempt, jitterFraction: .random(in: 0...1))
    }

    func delay(for attempt: Int, jitterFraction: Double) -> Duration {
        let exponent = pow(multiplier, Double(max(0, attempt)))
        let computedSeconds = initialDelaySeconds * exponent
        let baseDelaySeconds = computedSeconds.isFinite
            ? min(maxDelaySeconds, computedSeconds)
            : maxDelaySeconds
        let normalizedJitter = jitterFraction.isFinite
            ? min(1, max(0, jitterFraction))
            : 0
        let delaySeconds = baseDelaySeconds * normalizedJitter
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

private struct MattermostWebSocketEnvelopeSequence: AsyncSequence, Sendable {
    typealias Element = MattermostWebSocketEnvelope

    let nextEnvelope: @Sendable () async throws -> MattermostWebSocketEnvelope?

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(nextEnvelope: nextEnvelope)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let nextEnvelope: @Sendable () async throws -> MattermostWebSocketEnvelope?

        mutating func next() async throws -> MattermostWebSocketEnvelope? {
            try await nextEnvelope()
        }
    }
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
        event = try Self.decodeIfPresent(String.self, from: container, forKey: .event)
        data = try Self.decodeIfPresent([String: MattermostJSONValue].self, from: container, forKey: .data)
        broadcast = try Self.decodeIfPresent(MattermostLiveBroadcast.self, from: container, forKey: .broadcast)
        seq = Self.decodeInt(container, forKey: .seq)
        seqReply = Self.decodeInt(container, forKey: .seqReply)
        status = try Self.decodeIfPresent(String.self, from: container, forKey: .status)
        error = try Self.decodeIfPresent(MattermostWebSocketError.self, from: container, forKey: .error)
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
    ) throws -> Value? {
        do {
            return try container.decodeIfPresent(type, forKey: key)
        } catch is DecodingError {
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

/// Shared JSON coders reused by API and WebSocket payload handling.
let mattermostPlainDecoder = JSONDecoder()

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
