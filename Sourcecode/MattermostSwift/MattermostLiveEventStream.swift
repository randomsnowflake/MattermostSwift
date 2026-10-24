import Foundation

/// A Mattermost WebSocket event stream for one authenticated client.
public struct MattermostLiveEventStream: Sendable {
    private let configuration: MattermostConfiguration
    let urlSession: URLSession
    let heartbeatInterval: Duration
    let heartbeatTimeout: Duration
    /// REST check run when an upgraded socket fails before authenticating. Mattermost upgrades
    /// the socket without a session and then silently closes it on a rejected
    /// `authentication_challenge`, so only a REST 401 can tell a revoked token from a blip.
    var authenticationProbe: (@Sendable () async throws -> Void)?

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
    /// Hosts should cancel the consuming task when its owning scene enters the background and
    /// create a new stream when the scene becomes active.
    /// The queue holds at most 256 events; a slow consumer receives `MattermostError.liveEventGap`
    /// rather than silently observing an incomplete sequence.
    public func events() -> AsyncThrowingStream<MattermostLiveEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            let streamTask = Task {
                do {
                    try await runAuthenticatedConnection(
                        onConnected: {},
                        onHeartbeat: {},
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
    /// Cancelling the consuming task stops pending reconnect work and closes the current socket;
    /// hosts should use that teardown path while backgrounded.
    public func lifecycleEvents(
        policy: MattermostLiveEventReconnectPolicy = .default
    ) -> AsyncThrowingStream<MattermostLiveEventStreamLifecycleEvent, Error> {
        Self.lifecycleEvents(policy: policy) { onConnected, onHeartbeat, onEventDecodeFailed, onEvent in
            try await runAuthenticatedConnection(
                onConnected: onConnected,
                onHeartbeat: onHeartbeat,
                onEventDecodeFailed: onEventDecodeFailed,
                onEvent: onEvent
            )
        }
    }

    typealias LifecycleConnection = @Sendable (
        _ onConnected: @escaping @Sendable () async throws -> Void,
        _ onHeartbeat: @escaping @Sendable () async throws -> Void,
        _ onEventDecodeFailed: @escaping @Sendable (MattermostLiveEventStreamLifecycleEvent) async throws -> Void,
        _ onEvent: @escaping @Sendable (MattermostLiveEvent) async throws -> Void
    ) async throws -> Void

    /// Reconnect loop with an injectable connection. Every exit, including a yield that overflows
    /// the queue, finishes the continuation so a draining consumer can never wait forever.
    static func lifecycleEvents(
        policy: MattermostLiveEventReconnectPolicy,
        bufferLimit: Int = 512,
        connect: @escaping LifecycleConnection
    ) -> AsyncThrowingStream<MattermostLiveEventStreamLifecycleEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(bufferLimit)) { continuation in
            let streamTask = Task {
                do {
                    try await runLifecycle(policy: policy, connect: connect, continuation: continuation)
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

    private static func runLifecycle(
        policy: MattermostLiveEventReconnectPolicy,
        connect: LifecycleConnection,
        continuation: AsyncThrowingStream<MattermostLiveEventStreamLifecycleEvent, Error>.Continuation
    ) async throws {
        var attempt = 0

        while !Task.isCancelled {
            try yield(.connecting(attempt: attempt), to: continuation)

            let connectedAt = ContinuousClock.now
            let currentAttempt = attempt
            do {
                try await connect(
                    { try yield(.connected(attempt: currentAttempt), to: continuation) },
                    { try yield(.heartbeat, to: continuation) },
                    { try yield($0, to: continuation) },
                    { event in try yield(.event(event), to: continuation) }
                )

                if connectionWasStable(since: connectedAt) { attempt = 0 }
                guard policy.reconnectAfterCleanClose, policy.canRetry(attempt: attempt) else { return }
            } catch let error as MattermostError where error.isUnauthorized || error.isForbidden {
                // A rejected credential cannot heal by reconnecting; surface it so the
                // host can end the session instead of retrying a dead token forever.
                throw error
            } catch is CancellationError {
                return
            } catch {
                let failure = MattermostLiveEventStreamFailure(error: error)
                if connectionWasStable(since: connectedAt) { attempt = 0 }
                guard policy.canRetry(attempt: attempt) else { throw error }
                let delay = policy.delay(for: attempt)
                // An overflowed queue throws `liveEventGap` here too; it ends the stream above.
                try yield(.reconnecting(attempt: attempt, delay: delay, failure: failure), to: continuation)
                try await Task.sleep(for: delay)
                attempt += 1
                continue
            }

            let delay = policy.delay(for: attempt)
            try yield(.reconnecting(attempt: attempt, delay: delay), to: continuation)
            try await Task.sleep(for: delay)
            attempt += 1
        }
    }

    private func runAuthenticatedConnection(
        onConnected: @escaping @Sendable () async throws -> Void,
        onHeartbeat: @escaping @Sendable () async throws -> Void,
        onEventDecodeFailed: @escaping @Sendable (MattermostLiveEventStreamLifecycleEvent) async throws -> Void,
        onEvent: @escaping @Sendable (MattermostLiveEvent) async throws -> Void
    ) async throws {
        let webSocketTask = urlSession.webSocketTask(with: makeWebSocketRequest())
        webSocketTask.delegate = MattermostRedirectGuard.shared
        webSocketTask.resume()
        defer {
            webSocketTask.cancel(with: .goingAway, reason: nil)
        }

        let pendingEvents: [MattermostLiveEvent]
        do {
            pendingEvents = try await authenticate(webSocketTask)
        } catch {
            let upgradeStatusCode = (webSocketTask.response as? HTTPURLResponse)?.statusCode
            throw await Self.authenticationFailure(
                for: error,
                upgradeStatusCode: upgradeStatusCode,
                probe: authenticationProbe
            ) ?? error
        }
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
                    try await self.keepConnectionAlive(
                        webSocketTask,
                        onHeartbeat: onHeartbeat
                    )
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

    private func keepConnectionAlive(
        _ webSocketTask: URLSessionWebSocketTask,
        onHeartbeat: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await runHeartbeatLoop(
            sleep: { duration in
                try await Task.sleep(for: duration)
            },
            performHeartbeat: {
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
            },
            onHeartbeat: onHeartbeat
        )
    }

    func runHeartbeatLoop(
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        performHeartbeat: @escaping @Sendable () async throws -> Void,
        onHeartbeat: @escaping @Sendable () async throws -> Void
    ) async throws {
        guard isHeartbeatEnabled else { return }
        while !Task.isCancelled {
            try await sleep(heartbeatInterval)
            try Task.checkCancellation()
            try await performHeartbeat()
            try await onHeartbeat()
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

    /// Classifies a failure before WebSocket authentication completed. Returns an HTTP 401/403
    /// `MattermostError` only when the credential itself was rejected: by the upgrade response,
    /// or, after a successful upgrade, by the REST probe. Everything else stays retryable.
    static func authenticationFailure(
        for error: any Error,
        upgradeStatusCode: Int?,
        probe: (@Sendable () async throws -> Void)?
    ) async -> MattermostError? {
        if error is CancellationError || Task.isCancelled { return nil }
        if let upgradeStatusCode, upgradeStatusCode == 401 || upgradeStatusCode == 403 {
            return .httpStatus(
                code: upgradeStatusCode,
                message: "Mattermost WebSocket upgrade was rejected.",
                apiError: nil
            )
        }
        // Without a completed upgrade the server was never reached; probing would only add
        // REST timeouts to an ordinary network outage.
        guard upgradeStatusCode == 101, let probe else { return nil }
        do {
            try await probe()
            return nil
        } catch let probeError as MattermostError where probeError.isUnauthorized {
            return probeError
        } catch {
            return nil
        }
    }

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
