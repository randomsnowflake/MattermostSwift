import Foundation

// MARK: - Post, post list, search results, reaction, and status-OK models

/// A page of posts for a channel or thread.
public struct MattermostPostList: Decodable, Equatable, Sendable {
    public let order: [String]
    public let posts: [String: MattermostPost]
    public let nextPostID: String?
    public let prevPostID: String?
    public let hasNext: Bool?

    public var orderedPosts: [MattermostPost] {
        order.compactMap { posts[$0] }
    }

    @available(*, deprecated, renamed: "nextPostID")
    public var nextPostId: String? { nextPostID }

    @available(*, deprecated, renamed: "prevPostID")
    public var prevPostId: String? { prevPostID }

    enum CodingKeys: String, CodingKey {
        case order
        case posts
        case nextPostID = "nextPostId"
        case prevPostID = "prevPostId"
        case hasNext
    }

    public init(
        order: [String],
        posts: [String: MattermostPost],
        nextPostID: String?,
        prevPostID: String?,
        hasNext: Bool?
    ) {
        self.order = order
        self.posts = posts
        self.nextPostID = nextPostID
        self.prevPostID = prevPostID
        self.hasNext = hasNext
    }

    @available(*, deprecated, message: "Use init(order:posts:nextPostID:prevPostID:hasNext:)")
    public init(
        order: [String],
        posts: [String: MattermostPost],
        nextPostId: String?,
        prevPostId: String?,
        hasNext: Bool?
    ) {
        self.init(
            order: order,
            posts: posts,
            nextPostID: nextPostId,
            prevPostID: prevPostId,
            hasNext: hasNext
        )
    }
}

/// Search results for team post search.
public struct MattermostPostSearchResults: Decodable, Equatable, Sendable {
    public let order: [String]
    public let posts: [String: MattermostPost]
    public let matches: [String: [String]]?
    public let nextPostID: String?
    public let prevPostID: String?
    public let firstInaccessiblePostTime: Int64?

    public var orderedPosts: [MattermostPost] {
        order.compactMap { posts[$0] }
    }

    public var firstInaccessiblePostDate: Date? {
        firstInaccessiblePostTime.map(Date.init(mattermostMilliseconds:))
    }

    @available(*, deprecated, renamed: "nextPostID")
    public var nextPostId: String? { nextPostID }

    @available(*, deprecated, renamed: "prevPostID")
    public var prevPostId: String? { prevPostID }

    enum CodingKeys: String, CodingKey {
        case order
        case posts
        case matches
        case nextPostID = "nextPostId"
        case prevPostID = "prevPostId"
        case firstInaccessiblePostTime
    }
}

/// Typed subset of the `metadata` payload the server embeds with each post
/// (files and reactions). Lets clients skip the per-post `fileInfos`/`reactions`
/// lookups when the server already delivered them inline.
public struct MattermostPostMetadata: Decodable, Equatable, Hashable, Sendable {
    public let files: [MattermostFileInfo]?
    public let reactions: [MattermostReaction]?

    public init(files: [MattermostFileInfo]? = nil, reactions: [MattermostReaction]? = nil) {
        self.files = files
        self.reactions = reactions
    }
}

/// Mattermost post/message metadata.
public struct MattermostPost: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let createAt: Int64
    public let updateAt: Int64
    public let editAt: Int64
    public let deleteAt: Int64
    public let userID: String
    public let channelID: String
    public let rootID: String
    public let originalID: String?
    public let message: String
    public let type: MattermostPostType
    public let hashtags: String?
    public let pendingPostID: String?
    public let fileIDs: [String]?
    public let hasReactions: Bool?
    public let props: [String: MattermostJSONValue]?
    /// Untyped metadata exactly as delivered by Mattermost.
    public let rawMetadata: [String: MattermostJSONValue]?
    /// Typed files and reactions decoded from the post's `metadata` object.
    ///
    /// Unsupported or malformed embedded fields produce `nil` without failing
    /// decoding of the surrounding post; inspect ``rawMetadata`` when needed.
    public let metadata: MattermostPostMetadata?
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
        case userID = "userId"
        case channelID = "channelId"
        case rootID = "rootId"
        case originalID = "originalId"
        case message
        case type
        case hashtags
        case pendingPostID = "pendingPostId"
        case fileIDs = "fileIds"
        case hasReactions
        case props
        case rawMetadata = "metadata"
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
        userID: String,
        channelID: String,
        rootID: String,
        originalID: String?,
        message: String,
        type: MattermostPostType,
        hashtags: String?,
        pendingPostID: String?,
        fileIDs: [String]?,
        hasReactions: Bool?,
        props: [String: MattermostJSONValue]? = nil,
        rawMetadata: [String: MattermostJSONValue]? = nil,
        metadata: MattermostPostMetadata? = nil,
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
        self.userID = userID
        self.channelID = channelID
        self.rootID = rootID
        self.originalID = originalID
        self.message = message
        self.type = type
        self.hashtags = hashtags
        self.pendingPostID = pendingPostID
        self.fileIDs = fileIDs
        self.hasReactions = hasReactions
        self.props = props
        self.rawMetadata = rawMetadata
        self.metadata = metadata
        self.isPinned = isPinned
        self.replyCount = replyCount
        self.lastReplyAt = lastReplyAt
        self.isFollowing = isFollowing
    }

    @available(*, deprecated, message: "Use the ID-spelled initializer with rawMetadata:metadata:")
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
        type: MattermostPostType,
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
        self.init(
            id: id,
            createAt: createAt,
            updateAt: updateAt,
            editAt: editAt,
            deleteAt: deleteAt,
            userID: userId,
            channelID: channelId,
            rootID: rootId,
            originalID: originalId,
            message: message,
            type: type,
            hashtags: hashtags,
            pendingPostID: pendingPostId,
            fileIDs: fileIds,
            hasReactions: hasReactions,
            props: props,
            rawMetadata: metadata,
            metadata: postMetadata,
            isPinned: isPinned,
            replyCount: replyCount,
            lastReplyAt: lastReplyAt,
            isFollowing: isFollowing
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createAt = try container.decode(Int64.self, forKey: .createAt)
        updateAt = try container.decode(Int64.self, forKey: .updateAt)
        editAt = try container.decode(Int64.self, forKey: .editAt)
        deleteAt = try container.decode(Int64.self, forKey: .deleteAt)
        userID = try container.decode(String.self, forKey: .userID)
        channelID = try container.decode(String.self, forKey: .channelID)
        rootID = try container.decode(String.self, forKey: .rootID)
        originalID = try container.decodeIfPresent(String.self, forKey: .originalID)
        message = try container.decode(String.self, forKey: .message)
        type = try container.decode(MattermostPostType.self, forKey: .type)
        hashtags = try container.decodeIfPresent(String.self, forKey: .hashtags)
        pendingPostID = try container.decodeIfPresent(String.self, forKey: .pendingPostID)
        fileIDs = try container.decodeIfPresent([String].self, forKey: .fileIDs)
        hasReactions = try container.decodeIfPresent(Bool.self, forKey: .hasReactions)
        props = try container.decodeIfPresent([String: MattermostJSONValue].self, forKey: .props)
        rawMetadata = try container.decodeIfPresent(
            [String: MattermostJSONValue].self,
            forKey: .rawMetadata
        )
        metadata = try Self.decodeMetadataTolerantly(from: container)
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
        rootID.isEmpty
    }

    public var cacheTimestamp: Int64 {
        max(createAt, updateAt, editAt, deleteAt)
    }

    public var createdAt: Date { Date(mattermostMilliseconds: createAt) }
    public var updatedAt: Date { Date(mattermostMilliseconds: updateAt) }
    public var editedAt: Date? { editAt > 0 ? Date(mattermostMilliseconds: editAt) : nil }
    public var deletedAt: Date? { deleteAt > 0 ? Date(mattermostMilliseconds: deleteAt) : nil }
    public var lastReplyDate: Date? {
        lastReplyAt > 0 ? Date(mattermostMilliseconds: lastReplyAt) : nil
    }

    @available(*, deprecated, renamed: "userID")
    public var userId: String { userID }
    @available(*, deprecated, renamed: "channelID")
    public var channelId: String { channelID }
    @available(*, deprecated, renamed: "rootID")
    public var rootId: String { rootID }
    @available(*, deprecated, renamed: "originalID")
    public var originalId: String? { originalID }
    @available(*, deprecated, renamed: "pendingPostID")
    public var pendingPostId: String? { pendingPostID }
    @available(*, deprecated, renamed: "fileIDs")
    public var fileIds: [String]? { fileIDs }
    @available(*, deprecated, renamed: "metadata")
    public var postMetadata: MattermostPostMetadata? { metadata }

    private static func decodeMetadataTolerantly(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> MattermostPostMetadata? {
        guard container.contains(.rawMetadata),
              (try container.decodeNil(forKey: .rawMetadata)) == false else {
            return nil
        }
        do {
            return try container.decode(MattermostPostMetadata.self, forKey: .rawMetadata)
        } catch is DecodingError {
            return nil
        }
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
public struct MattermostReaction: Codable, Equatable, Hashable, Sendable {
    public let userID: String
    public let postID: String
    public let emojiName: String
    public let createAt: Int64?

    public init(userID: String, postID: String, emojiName: String, createAt: Int64? = nil) {
        self.userID = userID
        self.postID = postID
        self.emojiName = emojiName
        self.createAt = createAt
    }

    @available(*, deprecated, message: "Use init(userID:postID:emojiName:createAt:)")
    public init(userId: String, postId: String, emojiName: String, createAt: Int64? = nil) {
        self.init(userID: userId, postID: postId, emojiName: emojiName, createAt: createAt)
    }

    @available(*, deprecated, renamed: "userID")
    public var userId: String { userID }
    @available(*, deprecated, renamed: "postID")
    public var postId: String { postID }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case postID = "postId"
        case emojiName
        case createAt
    }

    public var createdAt: Date? {
        createAt.map(Date.init(mattermostMilliseconds:))
    }
}
