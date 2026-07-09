import Foundation

// MARK: - Post, post list, search results, reaction, and status-OK models

/// A page of posts for a channel or thread.
public struct MattermostPostList: Decodable, Equatable, Sendable {
    public let order: [String]
    public let posts: [String: MattermostPost]
    public let nextPostId: String?
    public let prevPostId: String?
    public let hasNext: Bool?

    public var orderedPosts: [MattermostPost] {
        order.compactMap { posts[$0] }
    }
}

/// Search results for team post search.
public struct MattermostPostSearchResults: Decodable, Equatable, Sendable {
    public let order: [String]
    public let posts: [String: MattermostPost]
    public let matches: [String: [String]]?
    public let nextPostId: String?
    public let prevPostId: String?
    public let firstInaccessiblePostTime: Int64?

    public var orderedPosts: [MattermostPost] {
        order.compactMap { posts[$0] }
    }
}

/// Typed subset of the `metadata` payload the server embeds with each post
/// (files and reactions). Lets clients skip the per-post `fileInfos`/`reactions`
/// lookups when the server already delivered them inline.
public struct MattermostPostMetadata: Decodable, Equatable, Sendable {
    public let files: [MattermostFileInfo]?
    public let reactions: [MattermostReaction]?

    public init(files: [MattermostFileInfo]? = nil, reactions: [MattermostReaction]? = nil) {
        self.files = files
        self.reactions = reactions
    }
}

/// Mattermost post/message metadata.
public struct MattermostPost: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createAt: Int64
    public let updateAt: Int64
    public let editAt: Int64
    public let deleteAt: Int64
    public let userId: String
    public let channelId: String
    public let rootId: String
    public let originalId: String?
    public let message: String
    public let type: String
    public let hashtags: String?
    public let pendingPostId: String?
    public let fileIds: [String]?
    public let hasReactions: Bool?
    public let props: [String: MattermostJSONValue]?
    public let metadata: [String: MattermostJSONValue]?
    public let postMetadata: MattermostPostMetadata?
    public let isPinned: Bool?
    public let replyCount: Int64
    public let lastReplyAt: Int64
    public let isFollowing: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case createAt
        case updateAt
        case editAt
        case deleteAt
        case userId
        case channelId
        case rootId
        case originalId
        case message
        case type
        case hashtags
        case pendingPostId
        case fileIds
        case hasReactions
        case props
        case metadata
        case isPinned
        case replyCount
        case lastReplyAt
        case isFollowing
    }

    public init(
        id: String,
        createAt: Int64,
        updateAt: Int64,
        editAt: Int64,
        deleteAt: Int64,
        userId: String,
        channelId: String,
        rootId: String,
        originalId: String?,
        message: String,
        type: String,
        hashtags: String?,
        pendingPostId: String?,
        fileIds: [String]?,
        hasReactions: Bool?,
        props: [String: MattermostJSONValue]? = nil,
        metadata: [String: MattermostJSONValue]? = nil,
        postMetadata: MattermostPostMetadata? = nil,
        isPinned: Bool? = nil,
        replyCount: Int64 = 0,
        lastReplyAt: Int64 = 0,
        isFollowing: Bool? = nil
    ) {
        self.id = id
        self.createAt = createAt
        self.updateAt = updateAt
        self.editAt = editAt
        self.deleteAt = deleteAt
        self.userId = userId
        self.channelId = channelId
        self.rootId = rootId
        self.originalId = originalId
        self.message = message
        self.type = type
        self.hashtags = hashtags
        self.pendingPostId = pendingPostId
        self.fileIds = fileIds
        self.hasReactions = hasReactions
        self.props = props
        self.metadata = metadata
        self.postMetadata = postMetadata
        self.isPinned = isPinned
        self.replyCount = replyCount
        self.lastReplyAt = lastReplyAt
        self.isFollowing = isFollowing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createAt = try container.decode(Int64.self, forKey: .createAt)
        updateAt = try container.decode(Int64.self, forKey: .updateAt)
        editAt = try container.decode(Int64.self, forKey: .editAt)
        deleteAt = try container.decode(Int64.self, forKey: .deleteAt)
        userId = try container.decode(String.self, forKey: .userId)
        channelId = try container.decode(String.self, forKey: .channelId)
        rootId = try container.decode(String.self, forKey: .rootId)
        originalId = try container.decodeIfPresent(String.self, forKey: .originalId)
        message = try container.decode(String.self, forKey: .message)
        type = try container.decode(String.self, forKey: .type)
        hashtags = try container.decodeIfPresent(String.self, forKey: .hashtags)
        pendingPostId = try container.decodeIfPresent(String.self, forKey: .pendingPostId)
        fileIds = try container.decodeIfPresent([String].self, forKey: .fileIds)
        hasReactions = try container.decodeIfPresent(Bool.self, forKey: .hasReactions)
        props = try container.decodeIfPresent([String: MattermostJSONValue].self, forKey: .props)
        metadata = try container.decodeIfPresent([String: MattermostJSONValue].self, forKey: .metadata)
        // Tolerant second decode of the same key: malformed embedded metadata must
        // never fail post decoding — clients fall back to per-post lookups instead.
        postMetadata = (try? container.decodeIfPresent(MattermostPostMetadata.self, forKey: .metadata)) ?? nil
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
        replyCount = try container.decodeIfPresent(Int64.self, forKey: .replyCount) ?? 0
        lastReplyAt = try container.decodeIfPresent(Int64.self, forKey: .lastReplyAt) ?? 0
        isFollowing = try container.decodeIfPresent(Bool.self, forKey: .isFollowing)
    }

    public var isDeleted: Bool {
        deleteAt > 0
    }

    public var isEdited: Bool {
        editAt > 0
    }

    public var isRootPost: Bool {
        rootId.isEmpty
    }

    public var cacheTimestamp: Int64 {
        max(createAt, updateAt, editAt, deleteAt)
    }
}

/// Standard Mattermost status response.
public struct MattermostStatusOK: Decodable, Equatable, Sendable {
    public let status: String

    public var isOK: Bool {
        status == "OK"
    }
}

/// A reaction attached to a Mattermost post.
public struct MattermostReaction: Codable, Equatable, Sendable {
    public let userId: String
    public let postId: String
    public let emojiName: String
    public let createAt: Int64?
}
