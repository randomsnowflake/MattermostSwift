import Foundation

// MARK: - Channel, stats, membership, notify props, unread, and view-response models

/// Mattermost channel metadata.
public struct MattermostChannel: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createAt: Int64?
    public let updateAt: Int64?
    public let teamId: String?
    public let name: String
    public let displayName: String
    public let type: String
    public let header: String?
    public let purpose: String?
    public let deleteAt: Int64?

    public var isDeleted: Bool {
        (deleteAt ?? 0) > 0
    }

    public var cacheTimestamp: Int64 {
        max(createAt ?? 0, updateAt ?? 0, deleteAt ?? 0)
    }
}

/// Result of channel search across teams.
public struct MattermostChannelSearchResults: Decodable, Equatable, Sendable {
    public let channels: [MattermostChannel]
    public let totalCount: Int?

    public init(from decoder: Decoder) throws {
        if let channels = try? [MattermostChannel](from: decoder) {
            self.channels = channels
            totalCount = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        channels = try container.decodeIfPresent([MattermostChannel].self, forKey: .channels) ?? []
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount)
    }

    enum CodingKeys: String, CodingKey {
        case channels
        case totalCount
    }
}

/// Aggregate statistics for a channel.
public struct MattermostChannelStats: Decodable, Equatable, Sendable {
    public let channelId: String?
    public let memberCount: Int64?
    public let guestCount: Int64?
    public let pinnedPostCount: Int64?
    public let totalMessageCount: Int64?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
        memberCount = try container.decodeIfPresent(Int64.self, forKey: .memberCount)
        guestCount = try container.decodeIfPresent(Int64.self, forKey: .guestCount)
        pinnedPostCount = try container.decodeIfPresent(Int64.self, forKey: .pinnedPostCount)
        totalMessageCount = try container.decodeIfPresent(Int64.self, forKey: .totalMsgCount)
    }

    enum CodingKeys: String, CodingKey {
        case channelId
        case memberCount
        case guestCount
        case pinnedPostCount
        case totalMsgCount
    }
}

/// Membership and notification state for a user in a channel.
public struct MattermostChannelMember: Decodable, Equatable, Sendable {
    public let channelId: String
    public let userId: String
    public let roles: String?
    public let lastViewedAt: Int64?
    public let msgCount: Int?
    public let mentionCount: Int?
    public let notifyProps: [String: String]?
    public let lastUpdateAt: Int64?

    public var channelNotifyProps: MattermostChannelNotifyProps {
        MattermostChannelNotifyProps(notifyProps ?? [:])
    }
}

/// Typed per-channel notification settings with access to unknown server keys.
public struct MattermostChannelNotifyProps: Equatable, Sendable {
    public static let desktopKey = "desktop"
    public static let emailKey = "email"
    public static let markUnreadKey = "mark_unread"
    public static let pushKey = "push"
    public static let ignoreChannelMentionsKey = "ignore_channel_mentions"

    public var rawValues: [String: String]

    public init(
        desktop: String? = nil,
        email: String? = nil,
        markUnread: String? = nil,
        push: String? = nil,
        ignoreChannelMentions: String? = nil,
        rawValues: [String: String] = [:]
    ) {
        var values = rawValues
        values[Self.desktopKey] = desktop
        values[Self.emailKey] = email
        values[Self.markUnreadKey] = markUnread
        values[Self.pushKey] = push
        values[Self.ignoreChannelMentionsKey] = ignoreChannelMentions
        self.rawValues = values
    }

    public init(_ rawValues: [String: String]) {
        self.rawValues = rawValues
    }

    public var desktop: String? {
        rawValues[Self.desktopKey]
    }

    public var email: String? {
        rawValues[Self.emailKey]
    }

    public var markUnread: String? {
        rawValues[Self.markUnreadKey]
    }

    public var push: String? {
        rawValues[Self.pushKey]
    }

    public var ignoreChannelMentions: String? {
        rawValues[Self.ignoreChannelMentionsKey]
    }

    public subscript(key: String) -> String? {
        rawValues[key]
    }
}

/// Unread counts for a user in a channel.
public struct MattermostChannelUnread: Decodable, Equatable, Sendable {
    public let teamId: String?
    public let channelId: String
    public let msgCount: Int
    public let mentionCount: Int
}

/// Result of marking a channel as viewed.
public struct MattermostChannelViewResponse: Decodable, Equatable, Sendable {
    public let status: String
    public let lastViewedAtTimes: [String: Int64]?

    public var isOK: Bool {
        status == "OK"
    }
}
