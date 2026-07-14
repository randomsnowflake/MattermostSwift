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
    /// Total posts in the channel, including replies.
    public let totalMsgCount: Int64?
    /// Total root posts in the channel on servers with collapsed reply threads enabled.
    public let totalMsgCountRoot: Int64?
    /// Timestamp of the most recent post, including replies.
    public let lastPostAt: Int64?
    /// Timestamp of the most recent root post on servers with collapsed reply threads enabled.
    public let lastRootPostAt: Int64?

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
        pinnedPostCount = try container.decodeIfPresent(Int64.self, forKey: .pinnedpostCount)
        totalMessageCount = try container.decodeIfPresent(Int64.self, forKey: .totalMsgCount)
    }

    enum CodingKeys: String, CodingKey {
        case channelId
        case memberCount
        case guestCount
        case pinnedpostCount
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
    /// Root-post count last seen by this member on servers with collapsed reply threads enabled.
    public let msgCountRoot: Int?
    /// Root-post mention count for this member on servers with collapsed reply threads enabled.
    public let mentionCountRoot: Int?
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

    public static let notifyDefault = "default"
    public static let notifyAll = "all"
    public static let notifyMention = "mention"
    public static let notifyNone = "none"
    public static let markUnreadAll = "all"
    public static let markUnreadMention = "mention"
    public static let ignoreChannelMentionsDefault = "default"
    public static let ignoreChannelMentionsOff = "off"
    public static let ignoreChannelMentionsOn = "on"

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

    /// Whether these props represent Mattermost's muted-channel behavior.
    ///
    /// `mark_unread=mention` is the core Mattermost mute signal, but clients may
    /// also expose that preference as a standalone "mark unread only for mentions"
    /// setting. Treat it as muted only when it is paired with delivery suppression
    /// or channel-wide mention suppression.
    public var isMuted: Bool {
        guard markUnread == Self.markUnreadMention else { return false }
        return ignoreChannelMentions == Self.ignoreChannelMentionsOn
            || (push == Self.notifyNone && desktop == Self.notifyNone)
    }

    /// Returns a copy with channel mute semantics applied while preserving unknown
    /// server keys and unrelated notification preferences.
    ///
    /// Muting makes the channel visually quiet (`mark_unread=mention`) and prevents
    /// delivery-oriented notifications (`push=none`, `desktop=none`). Unmuting
    /// restores only values this helper previously owns: `mark_unread` goes back
    /// to `all`, and `push`/`desktop` move from `none` to `unmutedNotifyValue`.
    ///
    /// - Parameter isMuted: `true` to mute the channel, `false` to unmute it.
    /// - Parameter unmutedNotifyValue: Notification value to use when unmuting a
    ///   `none` push/desktop value. Defaults to `all`, matching Mattermost's
    ///   channel-level non-muted setting.
    public func settingMuted(
        _ isMuted: Bool,
        unmutedNotifyValue: String = Self.notifyAll
    ) -> MattermostChannelNotifyProps {
        var copy = self
        copy.setMuted(isMuted, unmutedNotifyValue: unmutedNotifyValue)
        return copy
    }

    /// Mutates this value with the same semantics as ``settingMuted(_:unmutedNotifyValue:)``.
    public mutating func setMuted(
        _ isMuted: Bool,
        unmutedNotifyValue: String = Self.notifyAll
    ) {
        if isMuted {
            rawValues[Self.markUnreadKey] = Self.markUnreadMention
            rawValues[Self.pushKey] = Self.notifyNone
            rawValues[Self.desktopKey] = Self.notifyNone
            rawValues[Self.ignoreChannelMentionsKey] = Self.ignoreChannelMentionsOn
        } else {
            rawValues[Self.markUnreadKey] = Self.markUnreadAll
            if push == Self.notifyNone {
                rawValues[Self.pushKey] = unmutedNotifyValue
            }
            if desktop == Self.notifyNone {
                rawValues[Self.desktopKey] = unmutedNotifyValue
            }
            if ignoreChannelMentions == Self.ignoreChannelMentionsOn {
                rawValues[Self.ignoreChannelMentionsKey] = Self.ignoreChannelMentionsOff
            }
        }
    }
}

/// Unread counts for a user in a channel.
public struct MattermostChannelUnread: Decodable, Equatable, Sendable {
    public let teamId: String?
    public let channelId: String
    public let msgCount: Int
    public let mentionCount: Int
    /// Root-post-only unread count sent by servers with collapsed reply threads enabled.
    /// Prefer this over `msgCount` for channel badges when present.
    public let msgCountRoot: Int?
    /// Root-post-only mention count sent by servers with collapsed reply threads enabled.
    public let mentionCountRoot: Int?

    public init(
        teamId: String?,
        channelId: String,
        msgCount: Int,
        mentionCount: Int,
        msgCountRoot: Int? = nil,
        mentionCountRoot: Int? = nil
    ) {
        self.teamId = teamId
        self.channelId = channelId
        self.msgCount = msgCount
        self.mentionCount = mentionCount
        self.msgCountRoot = msgCountRoot
        self.mentionCountRoot = mentionCountRoot
    }
}

/// Result of marking a channel as viewed.
public struct MattermostChannelViewResponse: Decodable, Equatable, Sendable {
    public let status: String
    public let lastViewedAtTimes: [String: Int64]?

    public var isOK: Bool {
        status == "OK"
    }
}
