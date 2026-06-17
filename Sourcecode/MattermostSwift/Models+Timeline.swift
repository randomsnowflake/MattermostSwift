import Foundation

// MARK: - Timeline target, request, page, and sync-result models

/// A unified timeline target for channel timelines and thread timelines.
public enum MattermostTimelineTarget: Equatable, Sendable {
    case channel(id: String)
    case thread(rootPostID: String)

    public var cacheScope: String {
        switch self {
        case .channel(let id):
            "channel-posts:\(id)"
        case .thread(let rootPostID):
            "thread-posts:\(rootPostID)"
        }
    }
}

/// Pagination options for loading a channel or thread timeline.
public struct MattermostTimelineRequest: Equatable, Sendable {
    public var page: Int
    public var perPage: Int
    public var since: Int64?
    public var before: String?
    public var after: String?
    public var fromPost: String?
    public var fromCreateAt: Int64?
    public var direction: MattermostThreadDirection?
    public var skipFetchThreads: Bool?
    public var collapsedThreads: Bool?
    public var collapsedThreadsExtended: Bool?

    public init(
        page: Int = 0,
        perPage: Int = 60,
        since: Int64? = nil,
        before: String? = nil,
        after: String? = nil,
        fromPost: String? = nil,
        fromCreateAt: Int64? = nil,
        direction: MattermostThreadDirection? = nil,
        skipFetchThreads: Bool? = nil,
        collapsedThreads: Bool? = nil,
        collapsedThreadsExtended: Bool? = nil
    ) {
        self.page = max(0, page)
        self.perPage = max(0, perPage)
        self.since = since
        self.before = before
        self.after = after
        self.fromPost = fromPost
        self.fromCreateAt = fromCreateAt
        self.direction = direction
        self.skipFetchThreads = skipFetchThreads
        self.collapsedThreads = collapsedThreads
        self.collapsedThreadsExtended = collapsedThreadsExtended
    }
}

/// A loaded page for either a channel timeline or a thread timeline.
public struct MattermostTimelinePage: Equatable, Sendable {
    public let target: MattermostTimelineTarget
    public let postList: MattermostPostList

    public var posts: [MattermostPost] {
        postList.orderedPosts
    }

    public init(target: MattermostTimelineTarget, postList: MattermostPostList) {
        self.target = target
        self.postList = postList
    }
}

/// Summary of a timeline cache sync pass.
public struct MattermostTimelineSyncResult: Equatable, Sendable {
    public let target: MattermostTimelineTarget
    public let posts: [MattermostPost]
    public let pageCount: Int
    public let cursorLastSyncAt: Int64
    public let cursorLastItemID: String?

    public init(
        target: MattermostTimelineTarget,
        posts: [MattermostPost],
        pageCount: Int,
        cursorLastSyncAt: Int64,
        cursorLastItemID: String?
    ) {
        self.target = target
        self.posts = posts
        self.pageCount = pageCount
        self.cursorLastSyncAt = cursorLastSyncAt
        self.cursorLastItemID = cursorLastItemID
    }
}
