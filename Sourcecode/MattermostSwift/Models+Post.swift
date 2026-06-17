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
    public let isPinned: Bool?

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
        isPinned: Bool? = nil
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
        self.isPinned = isPinned
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
