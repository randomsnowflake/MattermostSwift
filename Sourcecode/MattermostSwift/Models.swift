import Foundation

/// Basic server health and client capability metadata.
public struct MattermostServerInfo: Equatable, Sendable {
    public let ping: MattermostServerPing
    public let clientConfig: MattermostClientConfig
}

/// Mattermost server health response.
public struct MattermostServerPing: Decodable, Equatable, Sendable {
    public let status: String
    public let activeSearchBackend: String?
    public let databaseStatus: String?
    public let filestoreStatus: String?
    public let iosLatestVersion: String?
    public let iosMinVersion: String?
    public let androidLatestVersion: String?
    public let androidMinVersion: String?

    enum CodingKeys: String, CodingKey {
        case status
        case activeSearchBackend = "ActiveSearchBackend"
        case databaseStatus
        case filestoreStatus
        case iosLatestVersion = "IosLatestVersion"
        case iosMinVersion = "IosMinVersion"
        case androidLatestVersion = "AndroidLatestVersion"
        case androidMinVersion = "AndroidMinVersion"
    }
}

/// Public client configuration values useful for SDK capability checks.
public struct MattermostClientConfig: Decodable, Equatable, Sendable {
    public let buildNumber: String?
    public let buildHash: String?
    public let buildDate: String?
    public let buildEnterpriseReady: String?
    public let collapsedThreads: String?
    public let enableFile: String?
    public let enableFileAttachments: String?
    public let enableCustomEmoji: String?
    public let enableIncomingWebhooks: String?
    public let enableOutgoingWebhooks: String?
    public let enablePostUsernameOverride: String?
    public let enablePostIconOverride: String?
    public let siteName: String?

    enum CodingKeys: String, CodingKey {
        case buildNumber = "BuildNumber"
        case buildHash = "BuildHash"
        case buildDate = "BuildDate"
        case buildEnterpriseReady = "BuildEnterpriseReady"
        case collapsedThreads = "CollapsedThreads"
        case enableFile = "EnableFile"
        case enableFileAttachments = "EnableFileAttachments"
        case enableCustomEmoji = "EnableCustomEmoji"
        case enableIncomingWebhooks = "EnableIncomingWebhooks"
        case enableOutgoingWebhooks = "EnableOutgoingWebhooks"
        case enablePostUsernameOverride = "EnablePostUsernameOverride"
        case enablePostIconOverride = "EnablePostIconOverride"
        case siteName = "SiteName"
    }
}

/// Authenticated Mattermost user profile data.
public struct MattermostUser: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let nickname: String?
    public let position: String?
    public let locale: String?
    public let timezone: [String: String]?
}

/// Source used to extract a session token from a successful Mattermost login response.
public enum MattermostSessionTokenSource: String, Equatable, Sendable {
    case responseHeader
    case authCookie
}

/// User and session token returned by Mattermost username/password login.
public struct MattermostSession: Equatable, Sendable {
    public let user: MattermostUser
    public let token: String
    public let tokenSource: MattermostSessionTokenSource

    public init(
        user: MattermostUser,
        token: String,
        tokenSource: MattermostSessionTokenSource = .responseHeader
    ) {
        self.user = user
        self.token = token
        self.tokenSource = tokenSource
    }

    public func client(serverURL: URL, urlSession: URLSession = .shared) throws -> MattermostClient {
        try MattermostClient(serverURL: serverURL, token: token, urlSession: urlSession)
    }
}

@available(*, deprecated, renamed: "MattermostSession")
public typealias MattermostLoginSession = MattermostSession

/// Presence status for a Mattermost user.
public struct MattermostUserStatus: Codable, Equatable, Sendable {
    public let userId: String
    public let status: String
    public let manual: Bool?
    public let lastActivityAt: Int64?
    public let activeChannel: String?
    public let dndEndTime: Int64?
}

/// User autocomplete buckets returned by Mattermost for composer/member pickers.
public struct MattermostUserAutocomplete: Decodable, Equatable, Sendable {
    public let users: [MattermostUser]
    public let inChannel: [MattermostUser]
    public let outOfChannel: [MattermostUser]

    public var allUsers: [MattermostUser] {
        var seen = Set<String>()
        return (users + inChannel + outOfChannel).filter { user in
            seen.insert(user.id).inserted
        }
    }

    public init(
        users: [MattermostUser] = [],
        inChannel: [MattermostUser] = [],
        outOfChannel: [MattermostUser] = []
    ) {
        self.users = users
        self.inChannel = inChannel
        self.outOfChannel = outOfChannel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.decodeIfPresent([MattermostUser].self, forKey: .users) ?? []
        inChannel = try container.decodeIfPresent([MattermostUser].self, forKey: .inChannel) ?? []
        outOfChannel = try container.decodeIfPresent([MattermostUser].self, forKey: .outOfChannel) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case users
        case inChannel
        case outOfChannel
    }
}

/// Mattermost team metadata.
public struct MattermostTeam: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String?
    public let type: String?
}

/// Membership and role state for a user on a Mattermost team.
public struct MattermostTeamMember: Decodable, Equatable, Sendable, Identifiable {
    public let teamId: String
    public let userId: String
    public let roles: String?
    public let deleteAt: Int64?
    public let schemeUser: Bool?
    public let schemeAdmin: Bool?
    public let explicitRoles: String?

    public var id: String {
        "\(teamId):\(userId)"
    }
}

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

/// Sidebar categories and server-provided ordering for a user's team sidebar.
public struct MattermostSidebarCategoryList: Decodable, Equatable, Sendable {
    public let categories: [MattermostSidebarCategory]
    public let order: [String]

    public var orderedCategories: [MattermostSidebarCategory] {
        guard !order.isEmpty else {
            return categories
        }

        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let ordered = order.compactMap { categoriesByID[$0] }
        let orderedIDs = Set(order)
        return ordered + categories.filter { !orderedIDs.contains($0.id) }
    }
}

/// Sidebar category metadata for a user's team sidebar.
public struct MattermostSidebarCategory: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let userId: String?
    public let teamId: String?
    public let displayName: String
    public let type: String
    public let sortOrder: Int?
    public let channelIds: [String]
    public let sorting: String?
    public let muted: Bool?
    public let collapsed: Bool?

    public var isCustom: Bool {
        type == "custom"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case teamId
        case displayName
        case type
        case sortOrder
        case channelIds
        case sorting
        case muted
        case collapsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        teamId = try container.decodeIfPresent(String.self, forKey: .teamId)
        displayName = try container.decode(String.self, forKey: .displayName)
        type = try container.decode(String.self, forKey: .type)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        channelIds = try container.decodeIfPresent([String].self, forKey: .channelIds) ?? []
        sorting = try container.decodeIfPresent(String.self, forKey: .sorting)
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted)
        collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed)
    }
}

/// Server-authoritative result after changing sidebar category channel membership.
public struct MattermostSidebarCategoryMoveResult: Equatable, Sendable {
    public let updatedCategories: [MattermostSidebarCategory]
    public let categories: [MattermostSidebarCategory]

    public var movedCategory: MattermostSidebarCategory? {
        updatedCategories.last
    }
}

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

/// Options for loading per-user Collapsed Reply Threads state.
public struct MattermostThreadListRequest: Equatable, Sendable {
    public var since: Int64?
    public var before: String?
    public var after: String?
    public var perPage: Int
    public var extended: Bool
    public var deleted: Bool
    public var unread: Bool
    public var threadsOnly: Bool
    public var totalsOnly: Bool
    public var excludeDirect: Bool

    public init(
        since: Int64? = nil,
        before: String? = nil,
        after: String? = nil,
        perPage: Int = 30,
        extended: Bool = false,
        deleted: Bool = false,
        unread: Bool = false,
        threadsOnly: Bool = false,
        totalsOnly: Bool = false,
        excludeDirect: Bool = false
    ) {
        self.since = since
        self.before = before
        self.after = after
        self.perPage = max(0, perPage)
        self.extended = extended
        self.deleted = deleted
        self.unread = unread
        self.threadsOnly = threadsOnly
        self.totalsOnly = totalsOnly
        self.excludeDirect = excludeDirect
    }
}

/// Per-user state for a root post in Mattermost's thread inbox.
public struct MattermostThreadResponse: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let replyCount: Int64
    public let lastReplyAt: Int64
    public let lastViewedAt: Int64
    public let participants: [MattermostUser]
    public let post: MattermostPost?
    public let unreadReplies: Int64
    public let unreadMentions: Int64
    public let isUrgent: Bool
    public let deleteAt: Int64

    public var isUnread: Bool {
        unreadReplies > 0 || unreadMentions > 0
    }

    enum CodingKeys: String, CodingKey {
        case id
        case replyCount
        case lastReplyAt
        case lastViewedAt
        case participants
        case post
        case unreadReplies
        case unreadMentions
        case isUrgent
        case deleteAt
    }

    public init(
        id: String,
        replyCount: Int64,
        lastReplyAt: Int64,
        lastViewedAt: Int64,
        participants: [MattermostUser] = [],
        post: MattermostPost? = nil,
        unreadReplies: Int64,
        unreadMentions: Int64,
        isUrgent: Bool,
        deleteAt: Int64
    ) {
        self.id = id
        self.replyCount = replyCount
        self.lastReplyAt = lastReplyAt
        self.lastViewedAt = lastViewedAt
        self.participants = participants
        self.post = post
        self.unreadReplies = unreadReplies
        self.unreadMentions = unreadMentions
        self.isUrgent = isUrgent
        self.deleteAt = deleteAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        replyCount = try container.decodeIfPresent(Int64.self, forKey: .replyCount) ?? 0
        lastReplyAt = try container.decodeIfPresent(Int64.self, forKey: .lastReplyAt) ?? 0
        lastViewedAt = try container.decodeIfPresent(Int64.self, forKey: .lastViewedAt) ?? 0
        participants = try container.decodeIfPresent([MattermostUser].self, forKey: .participants) ?? []
        post = try container.decodeIfPresent(MattermostPost.self, forKey: .post)
        unreadReplies = try container.decodeIfPresent(Int64.self, forKey: .unreadReplies) ?? 0
        unreadMentions = try container.decodeIfPresent(Int64.self, forKey: .unreadMentions) ?? 0
        isUrgent = try container.decodeIfPresent(Bool.self, forKey: .isUrgent) ?? false
        deleteAt = try container.decodeIfPresent(Int64.self, forKey: .deleteAt) ?? 0
    }
}

/// Thread inbox results for one user/team pair.
public struct MattermostThreadList: Decodable, Equatable, Sendable {
    public let total: Int64
    public let totalUnreadThreads: Int64
    public let totalUnreadMentions: Int64
    public let totalUnreadUrgentMentions: Int64
    public let threads: [MattermostThreadResponse]

    enum CodingKeys: String, CodingKey {
        case total
        case totalUnreadThreads
        case totalUnreadMentions
        case totalUnreadUrgentMentions
        case threads
    }

    public init(
        total: Int64,
        totalUnreadThreads: Int64,
        totalUnreadMentions: Int64,
        totalUnreadUrgentMentions: Int64,
        threads: [MattermostThreadResponse]
    ) {
        self.total = total
        self.totalUnreadThreads = totalUnreadThreads
        self.totalUnreadMentions = totalUnreadMentions
        self.totalUnreadUrgentMentions = totalUnreadUrgentMentions
        self.threads = threads
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decodeIfPresent(Int64.self, forKey: .total) ?? 0
        totalUnreadThreads = try container.decodeIfPresent(Int64.self, forKey: .totalUnreadThreads) ?? 0
        totalUnreadMentions = try container.decodeIfPresent(Int64.self, forKey: .totalUnreadMentions) ?? 0
        totalUnreadUrgentMentions = try container.decodeIfPresent(Int64.self, forKey: .totalUnreadUrgentMentions) ?? 0
        threads = try container.decodeIfPresent([MattermostThreadResponse].self, forKey: .threads) ?? []
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

/// Direction used by Mattermost thread pagination.
public enum MattermostThreadDirection: String, Equatable, Sendable {
    case up
    case down
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
        metadata: [String: MattermostJSONValue]? = nil
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

/// Response returned after uploading one or more files.
public struct MattermostFileUploadResponse: Decodable, Equatable, Sendable {
    public let fileInfos: [MattermostFileInfo]
    public let clientIds: [String]?
}

/// Metadata for an uploaded Mattermost file.
public struct MattermostFileInfo: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let userId: String?
    public let postId: String?
    public let createAt: Int64?
    public let updateAt: Int64?
    public let deleteAt: Int64?
    public let name: String
    public let extensionName: String?
    public let size: Int64?
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let hasPreviewImage: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case postId
        case createAt
        case updateAt
        case deleteAt
        case name
        case extensionName = "extension"
        case size
        case mimeType
        case width
        case height
        case hasPreviewImage
    }
}

/// Metadata for a Mattermost custom emoji.
public struct MattermostCustomEmoji: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let creatorId: String?
    public let name: String
    public let createAt: Int64?
    public let updateAt: Int64?
    public let deleteAt: Int64?
}

/// User preference entry used by Mattermost for client-side settings.
public struct MattermostPreference: Codable, Equatable, Sendable, Identifiable {
    public let userId: String
    public let category: String
    public let name: String
    public let value: String

    public var id: String {
        Self.cacheID(userID: userId, category: category, name: name)
    }

    public init(userId: String, category: String, name: String, value: String) {
        self.userId = userId
        self.category = category
        self.name = name
        self.value = value
    }

    public static func cacheID(userID: String, category: String, name: String) -> String {
        "\(userID):\(category):\(name)"
    }
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
