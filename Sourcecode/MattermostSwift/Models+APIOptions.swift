import Foundation

/// Options for loading a page of channel posts.
public struct MattermostPostsOptions: Equatable, Sendable {
    public var page: Int
    public var perPage: Int
    /// Millisecond update cursor for Mattermost's `posts/since` behavior.
    ///
    /// When non-`nil`, MattermostSwift uses the `since` endpoint shape and
    /// intentionally ignores `page`, `perPage`, `before`, and `after`. The
    /// collapsed-thread flags remain applicable.
    public var since: Int64?
    public var before: String?
    public var after: String?
    public var skipFetchThreads: Bool?
    public var collapsedThreads: Bool?
    public var collapsedThreadsExtended: Bool?

    public init(
        page: Int = 0,
        perPage: Int = 60,
        since: Int64? = nil,
        before: String? = nil,
        after: String? = nil,
        skipFetchThreads: Bool? = nil,
        collapsedThreads: Bool? = nil,
        collapsedThreadsExtended: Bool? = nil
    ) {
        self.page = max(0, page)
        self.perPage = max(1, perPage)
        self.since = since
        self.before = before
        self.after = after
        self.skipFetchThreads = skipFetchThreads
        self.collapsedThreads = collapsedThreads
        self.collapsedThreadsExtended = collapsedThreadsExtended
    }
}

/// Options for searching Mattermost users.
public struct MattermostUserSearchOptions: Equatable, Sendable {
    public var term: String
    public var teamID: String?
    public var notInTeamID: String?
    public var inChannelID: String?
    public var notInChannelID: String?
    public var allowInactive: Bool
    public var withoutTeam: Bool
    public var limit: Int

    public init(
        term: String,
        teamID: String? = nil,
        notInTeamID: String? = nil,
        inChannelID: String? = nil,
        notInChannelID: String? = nil,
        allowInactive: Bool = false,
        withoutTeam: Bool = false,
        limit: Int = 20
    ) {
        self.term = term
        self.teamID = teamID
        self.notInTeamID = notInTeamID
        self.inChannelID = inChannelID
        self.notInChannelID = notInChannelID
        self.allowInactive = allowInactive
        self.withoutTeam = withoutTeam
        self.limit = max(1, limit)
    }
}

/// Options for searching Mattermost channels.
public struct MattermostChannelSearchOptions: Equatable, Sendable {
    public var term: String
    public var teamIDs: [String]
    public var excludeDefaultChannels: Bool
    public var includeDeleted: Bool
    public var page: Int
    public var perPage: Int
    public var includeSearchByID: Bool

    public init(
        term: String,
        teamIDs: [String] = [],
        excludeDefaultChannels: Bool = false,
        includeDeleted: Bool = false,
        page: Int = 0,
        perPage: Int = 60,
        includeSearchByID: Bool = false
    ) {
        self.term = term
        self.teamIDs = teamIDs
        self.excludeDefaultChannels = excludeDefaultChannels
        self.includeDeleted = includeDeleted
        self.page = max(0, page)
        self.perPage = max(1, perPage)
        self.includeSearchByID = includeSearchByID
    }
}

/// Options for loading a root post and its replies.
public struct MattermostThreadOptions: Equatable, Sendable {
    public var perPage: Int
    public var fromPost: String?
    public var fromCreateAt: Int64?
    public var direction: MattermostThreadDirection?
    public var skipFetchThreads: Bool?
    public var collapsedThreads: Bool?
    public var collapsedThreadsExtended: Bool?

    public init(
        perPage: Int = 0,
        fromPost: String? = nil,
        fromCreateAt: Int64? = nil,
        direction: MattermostThreadDirection? = nil,
        skipFetchThreads: Bool? = nil,
        collapsedThreads: Bool? = nil,
        collapsedThreadsExtended: Bool? = nil
    ) {
        self.perPage = max(0, perPage)
        self.fromPost = fromPost
        self.fromCreateAt = fromCreateAt
        self.direction = direction
        self.skipFetchThreads = skipFetchThreads
        self.collapsedThreads = collapsedThreads
        self.collapsedThreadsExtended = collapsedThreadsExtended
    }
}
