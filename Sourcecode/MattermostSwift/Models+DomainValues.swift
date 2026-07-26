import Foundation

// MARK: - Forward-compatible string-backed domain values

/// A Mattermost channel type.
///
/// Known values are available as static members. Unknown server values remain valid and
/// preserve their raw string through Codable round trips for forward compatibility.
public struct MattermostChannelType: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let open = Self(rawValue: "O")
    public static let `private` = Self(rawValue: "P")
    public static let direct = Self(rawValue: "D")
    public static let group = Self(rawValue: "G")
    public static let space = Self(rawValue: "S")
    public static let openBoard = Self(rawValue: "BO")
    public static let privateBoard = Self(rawValue: "BP")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A Mattermost user presence status.
///
/// Unknown server values remain valid and preserve their raw string through Codable round trips.
public struct MattermostUserStatusValue: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let online = Self(rawValue: "online")
    public static let away = Self(rawValue: "away")
    public static let dnd = Self(rawValue: "dnd")
    public static let doNotDisturb = dnd
    public static let offline = Self(rawValue: "offline")
    public static let outOfOffice = Self(rawValue: "ooo")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A Mattermost post type.
///
/// An empty raw value is a regular user post. Mattermost and plugins may add more post types;
/// unknown values remain valid and preserve their raw string through Codable round trips.
public struct MattermostPostType: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let standard = Self(rawValue: "")
    public static let `default` = standard
    public static let slackAttachment = Self(rawValue: "slack_attachment")
    public static let messageAttachment = slackAttachment
    public static let systemGeneric = Self(rawValue: "system_generic")
    public static let systemJoinLeave = Self(rawValue: "system_join_leave")
    public static let systemJoinChannel = Self(rawValue: "system_join_channel")
    public static let systemGuestJoinChannel = Self(rawValue: "system_guest_join_channel")
    public static let systemLeaveChannel = Self(rawValue: "system_leave_channel")
    public static let systemJoinTeam = Self(rawValue: "system_join_team")
    public static let systemLeaveTeam = Self(rawValue: "system_leave_team")
    public static let systemAutoResponder = Self(rawValue: "system_auto_responder")
    public static let systemAutotranslation = Self(rawValue: "system_autotranslation")
    public static let systemAddRemove = Self(rawValue: "system_add_remove")
    public static let systemAddToChannel = Self(rawValue: "system_add_to_channel")
    public static let systemAddGuestToChannel = Self(rawValue: "system_add_guest_to_chan")
    public static let systemRemoveFromChannel = Self(rawValue: "system_remove_from_channel")
    public static let systemMoveChannel = Self(rawValue: "system_move_channel")
    public static let systemAddToTeam = Self(rawValue: "system_add_to_team")
    public static let systemRemoveFromTeam = Self(rawValue: "system_remove_from_team")
    public static let systemTeamAccessControlRemoval = Self(rawValue: "system_team_abac_removal")
    public static let systemTeamAccessControlAddition = Self(rawValue: "system_team_abac_addition")
    public static let systemHeaderChange = Self(rawValue: "system_header_change")
    public static let systemDisplayNameChange = Self(rawValue: "system_displayname_change")
    public static let systemConvertChannel = Self(rawValue: "system_convert_channel")
    public static let systemPurposeChange = Self(rawValue: "system_purpose_change")
    public static let systemChannelDeleted = Self(rawValue: "system_channel_deleted")
    public static let systemChannelRestored = Self(rawValue: "system_channel_restored")
    public static let systemEphemeral = Self(rawValue: "system_ephemeral")
    public static let systemChangeChannelPrivacy = Self(rawValue: "system_change_chan_privacy")
    public static let systemWrangler = Self(rawValue: "system_wrangler")
    public static let systemGroupMessageConvertedToChannel = Self(rawValue: "system_gm_to_channel")
    public static let addBotTeamsChannels = Self(rawValue: "add_bot_teams_channels")
    public static let me = Self(rawValue: "me")
    public static let reminder = Self(rawValue: "reminder")
    public static let burnOnRead = Self(rawValue: "burn_on_read")
    public static let card = Self(rawValue: "card")
    public static let systemSharedChannelState = Self(rawValue: "system_shared_chan_state")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A Mattermost sidebar category type.
///
/// Unknown server values remain valid and preserve their raw string through Codable round trips.
public struct MattermostSidebarCategoryType: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let favorites = Self(rawValue: "favorites")
    public static let channels = Self(rawValue: "channels")
    public static let directMessages = Self(rawValue: "direct_messages")
    public static let custom = Self(rawValue: "custom")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A Mattermost sidebar category sorting mode.
///
/// Unknown server values remain valid and preserve their raw string through Codable round trips.
public struct MattermostSidebarCategorySorting: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let manual = Self(rawValue: "manual")
    public static let recent = Self(rawValue: "recent")
    public static let alphabetical = Self(rawValue: "alpha")
    public static let alpha = alphabetical

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
