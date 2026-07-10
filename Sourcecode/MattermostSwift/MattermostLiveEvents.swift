import Foundation

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

    /// First non-nil string across the given (snake/camel) data keys, then the broadcast fallback.
    func anyString(_ keys: String..., broadcast path: KeyPath<MattermostLiveBroadcast, String?>? = nil) -> String? {
        for key in keys {
            if let value = stringData(key) {
                return value
            }
        }
        return path.flatMap { broadcast?[keyPath: $0] }
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
        if let channelID = anyString("channel_id", "channelId", broadcast: \.channelId) {
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
            userID: anyString("user_id", "userId", broadcast: \.userId),
            channelID: anyString("channel_id", "channelId", broadcast: \.channelId),
            parentID: anyString("parent_id", "parentId", "root_id", "rootId")
        )
    }

    /// Returns typed presence data for `status_change` events.
    public func decodedStatusChange() -> MattermostStatusChangeEvent? {
        guard event == MattermostLiveEventName.statusChange.rawValue else {
            return nil
        }

        return MattermostStatusChangeEvent(
            userID: anyString("user_id", "userId", broadcast: \.userId),
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
            userID: anyString("user_id", "userId", broadcast: \.userId),
            channelID: anyString("channel_id", "channelId", broadcast: \.channelId),
            previousChannelID: anyString("prev_channel_id", "prevChannelId")
        )
    }

    /// Returns generic channel/user invalidation data for events such as `post_unread`.
    public func decodedCacheInvalidation() -> MattermostCacheInvalidationEvent {
        MattermostCacheInvalidationEvent(
            event: event,
            userID: anyString("user_id", "userId", broadcast: \.userId),
            channelID: anyString("channel_id", "channelId", broadcast: \.channelId),
            teamID: anyString("team_id", "teamId", broadcast: \.teamId),
            postID: anyString("post_id", "postId")
        )
    }

    /// Returns tolerant thread-update data for `response` and collapsed-thread WebSocket events.
    public func decodedThreadEvent() throws -> MattermostThreadEvent {
        let post = try decodedPost()
        let postRootID = post?.rootId.isEmpty == false ? post?.rootId : nil
        return MattermostThreadEvent(
            event: event,
            userID: anyString("user_id", "userId", broadcast: \.userId) ?? post?.userId,
            channelID: anyString("channel_id", "channelId", broadcast: \.channelId) ?? post?.channelId,
            teamID: anyString("team_id", "teamId", broadcast: \.teamId),
            postID: anyString("post_id", "postId") ?? post?.id,
            rootID: anyString("root_id", "rootId") ?? postRootID,
            threadID: anyString("thread_id", "threadId") ?? postRootID ?? post?.id
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
            try decodedChannelDeletedEvent()
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

    private func decodedChannelDeletedEvent() throws -> MattermostTypedLiveEvent {
        let channel = try decodedChannel()
        let channelID = if let id = channel?.id { id } else { try decodedChannelID() }
        return .channelDeleted(channel, channelID: channelID)
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

    private enum SnakeCodingKeys: String, CodingKey {
        case omitUsers = "omit_users"
        case userId = "user_id"
        case channelId = "channel_id"
        case teamId = "team_id"
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
        let snakeContainer = try decoder.container(keyedBy: SnakeCodingKeys.self)
        omitUsers = Self.decodeStringArray(from: container, forKey: .omitUsers)
            ?? Self.decodeStringArray(from: snakeContainer, forKey: .omitUsers)
        userId = Self.decodeString(from: container, forKey: .userId)
            ?? Self.decodeString(from: snakeContainer, forKey: .userId)
        channelId = Self.decodeString(from: container, forKey: .channelId)
            ?? Self.decodeString(from: snakeContainer, forKey: .channelId)
        teamId = Self.decodeString(from: container, forKey: .teamId)
            ?? Self.decodeString(from: snakeContainer, forKey: .teamId)
    }

    private static func decodeString<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> String? {
        try? container.decodeIfPresent(String.self, forKey: key)
    }

    private static func decodeStringArray<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> [String]? {
        if let value = try? container.decodeIfPresent([String].self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return [value]
        }
        return nil
    }
}

/// Generic JSON value used for tolerant Mattermost JSON payloads.
public enum MattermostJSONValue: Codable, Equatable, Sendable {
    case string(String)
    /// A signed JSON integer preserved without converting through `Double`.
    case integer(Int64)
    /// An unsigned JSON integer preserved without converting through `Double`.
    case unsignedInteger(UInt64)
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
        case .integer(let value):
            return value
        case .unsignedInteger(let value):
            return Int64(exactly: value)
        case .number(let value):
            // `Int64(Double)` traps on a finite value outside Int64's range, so bound the
            // magnitude (< 2^63) as well as guarding NaN/infinity before converting.
            guard value.isFinite,
                  value >= -9_223_372_036_854_775_808.0,
                  value < 9_223_372_036_854_775_808.0,
                  value.rounded(.towardZero) == value else {
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
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
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
        case .integer(let value):
            try container.encode(value)
        case .unsignedInteger(let value):
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
        case .integer(let value):
            value
        case .unsignedInteger(let value):
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
