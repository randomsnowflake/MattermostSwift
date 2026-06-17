import Foundation

// MARK: - Internal Encodable request DTOs

struct MattermostUserStatusUpdateRequest: Encodable, Equatable, Sendable {
    let userId: String
    let status: String
    let dndEndTime: Int64?
}

struct MattermostMobileDeviceRequest: Encodable, Equatable, Sendable {
    let deviceId: String
}

struct MattermostCreatePostRequest: Encodable, Sendable {
    let channelId: String
    let message: String
    let rootId: String?
    let fileIds: [String]
    let props: [String: MattermostJSONValue]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channelId, forKey: .channelId)
        try container.encode(message, forKey: .message)
        if let rootId, !rootId.isEmpty {
            try container.encode(rootId, forKey: .rootId)
        }
        if !fileIds.isEmpty {
            try container.encode(fileIds, forKey: .fileIds)
        }
        if !props.isEmpty {
            try container.encode(props, forKey: .props)
        }
    }

    enum CodingKeys: String, CodingKey {
        case channelId
        case message
        case rootId
        case fileIds
        case props
    }
}

struct MattermostPatchPostRequest: Encodable, Sendable {
    let message: String
    let props: [String: MattermostJSONValue]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(props, forKey: .props)
    }

    enum CodingKeys: String, CodingKey {
        case message
        case props
    }
}

struct MattermostReactionRequest: Encodable, Sendable {
    let userId: String
    let postId: String
    let emojiName: String
}

struct MattermostPostSearchRequest: Encodable, Sendable {
    let terms: String
    let isOrSearch: Bool
    let timeZoneOffset: Int
    let includeDeletedChannels: Bool
    let page: Int
    let perPage: Int

    init(
        terms: String,
        isOrSearch: Bool,
        timeZoneOffset: Int,
        includeDeletedChannels: Bool,
        page: Int,
        perPage: Int
    ) {
        self.terms = terms
        self.isOrSearch = isOrSearch
        self.timeZoneOffset = timeZoneOffset
        self.includeDeletedChannels = includeDeletedChannels
        self.page = max(0, page)
        self.perPage = max(1, perPage)
    }
}

struct MattermostCreateChannelRequest: Encodable, Sendable {
    let teamId: String
    let name: String
    let displayName: String
    let purpose: String?
    let header: String?
    let type: String
}

struct MattermostPatchChannelRequest: Encodable, Sendable {
    let name: String?
    let displayName: String?
    let purpose: String?
    let header: String?
}

struct MattermostAddChannelMembersRequest: Encodable, Sendable {
    let userId: String?
    let userIds: [String]?
    let postRootId: String?

    init(userId: String? = nil, userIds: [String]? = nil, postRootId: String? = nil) {
        self.userId = userId
        self.userIds = userIds
        self.postRootId = postRootId
    }
}

struct MattermostUserSearchRequest: Encodable, Sendable {
    let term: String
    let teamId: String?
    let notInTeamId: String?
    let inChannelId: String?
    let notInChannelId: String?
    let allowInactive: Bool
    let withoutTeam: Bool
    let limit: Int

    init(
        term: String,
        teamId: String? = nil,
        notInTeamId: String? = nil,
        inChannelId: String? = nil,
        notInChannelId: String? = nil,
        allowInactive: Bool = false,
        withoutTeam: Bool = false,
        limit: Int = 20
    ) {
        self.term = term
        self.teamId = teamId
        self.notInTeamId = notInTeamId
        self.inChannelId = inChannelId
        self.notInChannelId = notInChannelId
        self.allowInactive = allowInactive
        self.withoutTeam = withoutTeam
        self.limit = max(1, limit)
    }
}

struct MattermostChannelSearchRequest: Encodable, Sendable {
    let term: String
    let teamIds: [String]
    let excludeDefaultChannels: Bool
    let deleted: Bool
    let page: Int
    let perPage: Int
    let includeSearchById: Bool

    init(
        term: String,
        teamIds: [String],
        excludeDefaultChannels: Bool,
        deleted: Bool,
        page: Int,
        perPage: Int,
        includeSearchById: Bool
    ) {
        self.term = term
        self.teamIds = teamIds
        self.excludeDefaultChannels = excludeDefaultChannels
        self.deleted = deleted
        self.page = max(0, page)
        self.perPage = max(1, perPage)
        self.includeSearchById = includeSearchById
    }
}

struct MattermostTeamChannelSearchRequest: Encodable, Sendable {
    let term: String
}

struct MattermostViewChannelRequest: Encodable, Sendable {
    let channelId: String
    let prevChannelId: String?
}

struct MattermostSidebarCategoryRequest: Encodable, Sendable {
    let id: String?
    let userId: String
    let teamId: String
    let displayName: String
    let type: String
    let channelIds: [String]
    let sorting: String
}

struct MattermostTypingRequest: Encodable, Sendable {
    let channelId: String
    let parentId: String?
}

struct MattermostEmojiSearchRequest: Encodable, Sendable {
    let term: String
    let prefixOnly: Bool
}

struct MattermostLoginRequest: Encodable, Sendable {
    let loginId: String
    let password: String
    let token: String?
    let deviceId: String?
    let ldapOnly: Bool?
}
