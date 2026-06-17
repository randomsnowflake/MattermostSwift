import Foundation

// MARK: - Thread request, response, list, and direction models

/// Direction used by Mattermost thread pagination.
public enum MattermostThreadDirection: String, Equatable, Sendable {
    case up
    case down
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
    public let isFollowing: Bool?

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
        case isFollowing
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
        deleteAt: Int64,
        isFollowing: Bool? = nil
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
        self.isFollowing = isFollowing
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
        isFollowing = try container.decodeIfPresent(Bool.self, forKey: .isFollowing)
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
