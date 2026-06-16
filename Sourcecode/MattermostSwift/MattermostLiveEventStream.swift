import Foundation

/// A Mattermost WebSocket event stream for one authenticated client.
public struct MattermostLiveEventStream: Sendable {
    private let configuration: MattermostConfiguration
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(configuration: MattermostConfiguration, urlSession: URLSession = .mattermost) {
        self.configuration = configuration
        self.urlSession = urlSession

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
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

    /// Yields live events and reconnects with exponential backoff when the socket ends unexpectedly.
    public func reconnectingEvents(
        policy: MattermostLiveEventReconnectPolicy = .default
    ) -> AsyncThrowingStream<MattermostLiveEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            let streamTask = Task {
                var attempt = 0

                while !Task.isCancelled {
                    let connectedAt = ContinuousClock.now
                    do {
                        for try await event in events() {
                            continuation.yield(event)
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

                    do {
                        try await Task.sleep(for: policy.delay(for: attempt))
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
            let payload = try self.encoder.encode(auth)
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

        return try decoder.decode(MattermostWebSocketEnvelope.self, from: data)
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

/// A decoded Mattermost WebSocket event.
public struct MattermostLiveEvent: Decodable, Equatable, Sendable {
    public let event: String
    public let data: [String: MattermostJSONValue]
    public let broadcast: MattermostLiveBroadcast?
    public let seq: Int?

    public var name: MattermostLiveEventName? {
        MattermostLiveEventName(rawValue: event)
    }

    public func stringData(_ key: String) -> String? {
        data[key]?.stringValue
    }

    public func boolData(_ key: String) -> Bool? {
        data[key]?.boolValue
    }

    public func int64Data(_ key: String) -> Int64? {
        data[key]?.int64Value
    }

    public func jsonData(_ key: String) -> Data? {
        data[key]?.jsonData
    }

    /// Decodes the embedded post payload used by post-related WebSocket events.
    public func decodedPost() throws -> MattermostPost? {
        guard let data = jsonData("post") else {
            return nil
        }

        return try mattermostSnakeCaseDecoder.decode(MattermostPost.self, from: data)
    }

    /// Decodes embedded channel payloads used by channel-related WebSocket events when present.
    public func decodedChannel() throws -> MattermostChannel? {
        guard let data = jsonData("channel") else {
            return nil
        }

        return try mattermostSnakeCaseDecoder.decode(MattermostChannel.self, from: data)
    }

    /// Decodes embedded channel membership payloads when present.
    public func decodedChannelMember() throws -> MattermostChannelMember? {
        let payload = jsonData("channel_member") ?? jsonData("channelMember") ?? jsonData("member")
        guard let payload else {
            return nil
        }

        return try mattermostSnakeCaseDecoder.decode(MattermostChannelMember.self, from: payload)
    }

    /// Decodes embedded user payloads used by user-related WebSocket events when present.
    public func decodedUser() throws -> MattermostUser? {
        guard let data = jsonData("user") else {
            return nil
        }

        return try mattermostSnakeCaseDecoder.decode(MattermostUser.self, from: data)
    }

    /// Decodes a reaction payload from reaction WebSocket events when present.
    public func decodedReaction() throws -> MattermostReaction? {
        guard let data = jsonData("reaction") else {
            return nil
        }

        return try mattermostSnakeCaseDecoder.decode(MattermostReaction.self, from: data)
    }

    /// Returns a channel id from event data or broadcast metadata.
    public func decodedChannelID() throws -> String? {
        if let channelID = stringData("channel_id") ?? stringData("channelId") ?? broadcast?.channelId {
            return channelID
        }
        return try decodedChannel()?.id
    }

    /// Returns typed typing-event data for `typing` events.
    public func decodedTyping() -> MattermostTypingEvent? {
        guard event == MattermostLiveEventName.typing.rawValue else {
            return nil
        }

        return MattermostTypingEvent(
            userID: stringData("user_id") ?? stringData("userId") ?? broadcast?.userId,
            channelID: stringData("channel_id") ?? stringData("channelId") ?? broadcast?.channelId,
            parentID: stringData("parent_id") ?? stringData("parentId") ?? stringData("root_id") ?? stringData("rootId")
        )
    }

    /// Returns typed presence data for `status_change` events.
    public func decodedStatusChange() -> MattermostStatusChangeEvent? {
        guard event == MattermostLiveEventName.statusChange.rawValue else {
            return nil
        }

        return MattermostStatusChangeEvent(
            userID: stringData("user_id") ?? stringData("userId") ?? broadcast?.userId,
            status: stringData("status"),
            manual: boolData("manual")
        )
    }

    /// Returns typed channel-view data for `channel_viewed` events.
    public func decodedChannelViewed() -> MattermostChannelViewedEvent? {
        guard event == MattermostLiveEventName.channelViewed.rawValue else {
            return nil
        }

        return MattermostChannelViewedEvent(
            userID: stringData("user_id") ?? stringData("userId") ?? broadcast?.userId,
            channelID: stringData("channel_id") ?? stringData("channelId") ?? broadcast?.channelId,
            previousChannelID: stringData("prev_channel_id") ?? stringData("prevChannelId")
        )
    }

    /// Returns generic channel/user invalidation data for events such as `post_unread`.
    public func decodedCacheInvalidation() -> MattermostCacheInvalidationEvent {
        MattermostCacheInvalidationEvent(
            event: event,
            userID: stringData("user_id") ?? stringData("userId") ?? broadcast?.userId,
            channelID: stringData("channel_id") ?? stringData("channelId") ?? broadcast?.channelId,
            teamID: stringData("team_id") ?? stringData("teamId") ?? broadcast?.teamId,
            postID: stringData("post_id") ?? stringData("postId")
        )
    }

    /// Returns tolerant thread-update data for `response` and collapsed-thread WebSocket events.
    public func decodedThreadEvent() throws -> MattermostThreadEvent {
        let post = try decodedPost()
        let postRootID = post?.rootId.isEmpty == false ? post?.rootId : nil
        return MattermostThreadEvent(
            event: event,
            userID: stringData("user_id") ?? stringData("userId") ?? broadcast?.userId ?? post?.userId,
            channelID: stringData("channel_id") ?? stringData("channelId") ?? broadcast?.channelId ?? post?.channelId,
            teamID: stringData("team_id") ?? stringData("teamId") ?? broadcast?.teamId,
            postID: stringData("post_id") ?? stringData("postId") ?? post?.id,
            rootID: stringData("root_id") ?? stringData("rootId") ?? postRootID,
            threadID: stringData("thread_id") ?? stringData("threadId") ?? postRootID ?? post?.id
        )
    }

    /// Maps common Mattermost WebSocket events into strongly typed cases.
    public func typedEvent() throws -> MattermostTypedLiveEvent {
        switch name {
        case .hello:
            .hello
        case .posted:
            if let post = try decodedPost() {
                .posted(post)
            } else {
                .unknown(self)
            }
        case .postEdited:
            if let post = try decodedPost() {
                .postEdited(post)
            } else {
                .unknown(self)
            }
        case .postDeleted:
            .postDeleted(try decodedPost())
        case .reactionAdded:
            .reactionAdded(try decodedReaction())
        case .reactionRemoved:
            .reactionRemoved(try decodedReaction())
        case .typing:
            if let typing = decodedTyping() {
                .typing(typing)
            } else {
                .unknown(self)
            }
        case .statusChange:
            if let statusChange = decodedStatusChange() {
                .statusChange(statusChange)
            } else {
                .unknown(self)
            }
        case .channelViewed:
            if let channelViewed = decodedChannelViewed() {
                .channelViewed(channelViewed)
            } else {
                .unknown(self)
            }
        case .channelCreated:
            .channelCreated(try decodedChannel())
        case .channelUpdated, .channelConverted:
            .channelUpdated(try decodedChannel())
        case .channelDeleted:
            .channelDeleted(try decodedChannel(), channelID: try decodedChannelID())
        case .channelMemberUpdated:
            .channelMemberUpdated(try decodedChannelMember())
        case .userUpdated, .newUser:
            .userUpdated(try decodedUser())
        case .preferenceChanged, .preferencesChanged:
            .preferencesChanged(self)
        case .preferencesDeleted:
            .preferencesDeleted(self)
        case .postUnread:
            .postUnread(decodedCacheInvalidation())
        case .response:
            .response(try decodedThreadEvent())
        case .threadUpdated:
            .threadUpdated(try decodedThreadEvent())
        case .threadFollowChanged:
            .threadFollowChanged(try decodedThreadEvent())
        case .threadReadChanged:
            .threadReadChanged(try decodedThreadEvent())
        case .userAdded, .userRemoved:
            .cacheInvalidated(self)
        case .none:
            .unknown(self)
        }
    }
}

/// Known Mattermost WebSocket event names.
public enum MattermostLiveEventName: String, Sendable {
    case hello
    case posted
    case postEdited = "post_edited"
    case postDeleted = "post_deleted"
    case postUnread = "post_unread"
    case reactionAdded = "reaction_added"
    case reactionRemoved = "reaction_removed"
    case typing
    case statusChange = "status_change"
    case channelViewed = "channel_viewed"
    case channelCreated = "channel_created"
    case channelUpdated = "channel_updated"
    case channelDeleted = "channel_deleted"
    case channelConverted = "channel_converted"
    case channelMemberUpdated = "channel_member_updated"
    case userUpdated = "user_updated"
    case newUser = "new_user"
    case userAdded = "user_added"
    case userRemoved = "user_removed"
    case preferenceChanged = "preference_changed"
    case preferencesChanged = "preferences_changed"
    case preferencesDeleted = "preferences_deleted"
    case response
    case threadUpdated = "thread_updated"
    case threadFollowChanged = "thread_follow_changed"
    case threadReadChanged = "thread_read_changed"
}

/// Strongly typed view of common Mattermost WebSocket events.
public enum MattermostTypedLiveEvent: Equatable, Sendable {
    case hello
    case posted(MattermostPost)
    case postEdited(MattermostPost)
    case postDeleted(MattermostPost?)
    case reactionAdded(MattermostReaction?)
    case reactionRemoved(MattermostReaction?)
    case typing(MattermostTypingEvent)
    case statusChange(MattermostStatusChangeEvent)
    case channelViewed(MattermostChannelViewedEvent)
    case channelCreated(MattermostChannel?)
    case channelUpdated(MattermostChannel?)
    case channelDeleted(MattermostChannel?, channelID: String?)
    case channelMemberUpdated(MattermostChannelMember?)
    case userUpdated(MattermostUser?)
    case preferencesChanged(MattermostLiveEvent)
    case preferencesDeleted(MattermostLiveEvent)
    case postUnread(MattermostCacheInvalidationEvent)
    case response(MattermostThreadEvent)
    case threadUpdated(MattermostThreadEvent)
    case threadFollowChanged(MattermostThreadEvent)
    case threadReadChanged(MattermostThreadEvent)
    case cacheInvalidated(MattermostLiveEvent)
    case unknown(MattermostLiveEvent)
}

/// Typing indicator payload emitted by Mattermost WebSocket events.
public struct MattermostTypingEvent: Equatable, Sendable {
    public let userID: String?
    public let channelID: String?
    public let parentID: String?
}

/// Presence update payload emitted by Mattermost WebSocket events.
public struct MattermostStatusChangeEvent: Equatable, Sendable {
    public let userID: String?
    public let status: String?
    public let manual: Bool?
}

/// Channel viewed payload emitted by Mattermost WebSocket events.
public struct MattermostChannelViewedEvent: Equatable, Sendable {
    public let userID: String?
    public let channelID: String?
    public let previousChannelID: String?
}

/// Generic cache invalidation payload emitted by channel/user scoped WebSocket events.
public struct MattermostCacheInvalidationEvent: Equatable, Sendable {
    public let event: String
    public let userID: String?
    public let channelID: String?
    public let teamID: String?
    public let postID: String?
}

/// Tolerant thread-update payload emitted by collapsed-thread WebSocket events.
public struct MattermostThreadEvent: Equatable, Sendable {
    public let event: String
    public let userID: String?
    public let channelID: String?
    public let teamID: String?
    public let postID: String?
    public let rootID: String?
    public let threadID: String?
}

/// Broadcast metadata attached to a Mattermost WebSocket event.
public struct MattermostLiveBroadcast: Decodable, Equatable, Sendable {
    public let omitUsers: [String]?
    public let userId: String?
    public let channelId: String?
    public let teamId: String?

    private enum CodingKeys: String, CodingKey {
        case omitUsers
        case userId
        case channelId
        case teamId
    }

    public init(
        omitUsers: [String]? = nil,
        userId: String? = nil,
        channelId: String? = nil,
        teamId: String? = nil
    ) {
        self.omitUsers = omitUsers
        self.userId = userId
        self.channelId = channelId
        self.teamId = teamId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        omitUsers = try? container.decode([String].self, forKey: .omitUsers)
        userId = try? container.decode(String.self, forKey: .userId)
        channelId = try? container.decode(String.self, forKey: .channelId)
        teamId = try? container.decode(String.self, forKey: .teamId)
    }
}

/// Generic JSON value used for tolerant Mattermost JSON payloads.
public enum MattermostJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: MattermostJSONValue])
    case array([MattermostJSONValue])
    case null

    public var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    public var int64Value: Int64? {
        switch self {
        case .number(let value):
            guard value.isFinite else {
                return nil
            }
            return Int64(value)
        case .string(let value):
            return Int64(value)
        default:
            return nil
        }
    }

    public var jsonData: Data? {
        switch self {
        case .string(let value):
            value.data(using: .utf8)
        default:
            try? JSONSerialization.data(withJSONObject: jsonObject)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: MattermostJSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([MattermostJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

private extension MattermostJSONValue {
    var jsonObject: Any {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            value
        case .bool(let value):
            value
        case .object(let value):
            value.mapValues(\.jsonObject)
        case .array(let value):
            value.map(\.jsonObject)
        case .null:
            NSNull()
        }
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

/// Shared snake_case decoder reused by `MattermostLiveEvent` payload decoding to avoid
/// allocating a configured `JSONDecoder` per event on the live hot path.
let mattermostSnakeCaseDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()

