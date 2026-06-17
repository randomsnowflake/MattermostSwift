import Foundation

/// A Mattermost WebSocket event stream for one authenticated client.
public struct MattermostLiveEventStream: Sendable {
    private let configuration: MattermostConfiguration
    private let urlSession: URLSession

    public init(configuration: MattermostConfiguration, urlSession: URLSession = .mattermost) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    /// Connects, authenticates, and yields server events until cancelled or the socket fails.
    public func events() -> AsyncThrowingStream<MattermostLiveEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            let streamTask = Task {
                do {
                    let webSocketTask = urlSession.webSocketTask(with: makeWebSocketRequest())
                    webSocketTask.resume()
                    defer {
                        webSocketTask.cancel(with: .goingAway, reason: nil)
                    }

                    let pendingEvents = try await authenticate(webSocketTask)
                    for event in pendingEvents {
                        continuation.yield(event)
                    }

                    while !Task.isCancelled {
                        if let event = try await receiveEvent(from: webSocketTask) {
                            continuation.yield(event)
                        }
                    }

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
                    do {
                        for try await event in events() {
                            continuation.yield(.event(event))
                        }

                        if Self.connectionWasStable(since: connectedAt) { attempt = 0 }
                        guard policy.reconnectAfterCleanClose, policy.canRetry(attempt: attempt) else {
                            continuation.finish()
                            return
                        }
                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch {
                        if Self.connectionWasStable(since: connectedAt) { attempt = 0 }
                        guard policy.canRetry(attempt: attempt) else {
                            continuation.finish(throwing: error)
                            return
                        }
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

    private func authenticate(_ webSocketTask: URLSessionWebSocketTask) async throws -> [MattermostLiveEvent] {
        // Bound the handshake: a server that upgrades the socket but never sends `hello`
        // or an auth reply would otherwise hang this loop forever.
        try await Self.withTimeout(.seconds(15)) {
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
    private static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw MattermostError.transportFailure("Mattermost WebSocket authentication timed out.")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }


    private func receiveEvent(from webSocketTask: URLSessionWebSocketTask) async throws -> MattermostLiveEvent? {
        try await receiveEnvelope(from: webSocketTask).liveEvent
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

/// Backoff controls for reconnecting Mattermost WebSocket event streams.
public struct MattermostLiveEventReconnectPolicy: Equatable, Sendable {
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
        self.initialDelaySeconds = initialDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.multiplier = multiplier
        self.maxRetries = maxRetries
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
        let delaySeconds = min(maxDelaySeconds, initialDelaySeconds * exponent)
        return .milliseconds(Int(delaySeconds * 1000))
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

private struct MattermostWebSocketEnvelope: Decodable, Sendable {
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
        event = try? container.decode(String.self, forKey: .event)
        data = try? container.decode([String: MattermostJSONValue].self, forKey: .data)
        broadcast = try? container.decode(MattermostLiveBroadcast.self, forKey: .broadcast)
        seq = Self.decodeInt(container, forKey: .seq)
        seqReply = Self.decodeInt(container, forKey: .seqReply)
        status = try? container.decode(String.self, forKey: .status)
        error = try? container.decode(MattermostWebSocketError.self, forKey: .error)
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

private struct MattermostWebSocketError: Decodable, Sendable {
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
