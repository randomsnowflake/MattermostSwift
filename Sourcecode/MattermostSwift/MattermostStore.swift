import Foundation
import SwiftData

/// Plain JSON coders reused for cached post props/metadata round-trips (no key strategy:
/// keys are arbitrary server JSON and must survive verbatim). Shared to avoid per-call allocation.
private let mattermostCachedPostEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()
private let mattermostCachedPostDecoder = JSONDecoder()

/// SwiftData-backed cache for Mattermost objects used by app targets and the CLI.
@MainActor
public final class MattermostStore {
    public static var schema: Schema {
        Schema([
            MattermostCachedUser.self,
            MattermostCachedUserStatus.self,
            MattermostCachedTeam.self,
            MattermostCachedChannel.self,
            MattermostCachedChannelMember.self,
            MattermostCachedChannelUnread.self,
            MattermostCachedThread.self,
            MattermostCachedPost.self,
            MattermostCachedReaction.self,
            MattermostCachedFile.self,
            MattermostCachedSidebarCategory.self,
            MattermostSyncCursor.self,
        ])
    }

    public let container: ModelContainer
    public let context: ModelContext

    public init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    public convenience init(inMemory: Bool = false, url: URL? = nil) throws {
        let schema = Self.schema
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                "MattermostSwift",
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "MattermostSwift",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }

        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.init(container: container)
    }

    public func save() throws {
        try context.save()
    }

    @discardableResult
    public func upsert(user: MattermostUser) throws -> MattermostCachedUser {
        if let cached = try cachedUser(id: user.id) {
            cached.apply(user)
            return cached
        }

        let cached = MattermostCachedUser(user)
        context.insert(cached)
        return cached
    }

    public func upsert(users: [MattermostUser]) throws {
        for user in users {
            try upsert(user: user)
        }
    }

    @discardableResult
    public func upsert(status: MattermostUserStatus) throws -> MattermostCachedUserStatus {
        if let cached = try cachedUserStatus(userID: status.userId) {
            cached.apply(status)
            return cached
        }

        let cached = MattermostCachedUserStatus(status)
        context.insert(cached)
        return cached
    }

    public func upsert(statuses: [MattermostUserStatus]) throws {
        for status in statuses {
            try upsert(status: status)
        }
    }

    @discardableResult
    public func upsert(team: MattermostTeam) throws -> MattermostCachedTeam {
        if let cached = try cachedTeam(id: team.id) {
            cached.apply(team)
            return cached
        }

        let cached = MattermostCachedTeam(team)
        context.insert(cached)
        return cached
    }

    public func upsert(teams: [MattermostTeam]) throws {
        for team in teams {
            try upsert(team: team)
        }
    }

    @discardableResult
    public func upsert(channel: MattermostChannel) throws -> MattermostCachedChannel {
        if let cached = try cachedChannel(id: channel.id) {
            cached.apply(channel)
            return cached
        }

        let cached = MattermostCachedChannel(channel)
        context.insert(cached)
        return cached
    }

    public func upsert(channels: [MattermostChannel]) throws {
        for channel in channels {
            try upsert(channel: channel)
        }
    }

    public func markChannelDeleted(id: String, at deletedAt: Int64 = Int64(Date.now.timeIntervalSince1970 * 1000)) throws {
        if let cached = try cachedChannel(id: id) {
            cached.markDeleted(at: deletedAt)
        }
    }

    public func markPostDeleted(id: String, at deletedAt: Int64 = Int64(Date.now.timeIntervalSince1970 * 1000)) throws {
        if let cached = try cachedPost(id: id) {
            cached.markDeleted(at: deletedAt)
        }
    }

    @discardableResult
    public func upsert(member: MattermostChannelMember) throws -> MattermostCachedChannelMember {
        let id = MattermostCachedChannelMember.cacheID(
            channelID: member.channelId,
            userID: member.userId
        )
        if let cached = try cachedChannelMember(id: id) {
            cached.apply(member)
            return cached
        }

        let cached = MattermostCachedChannelMember(member)
        context.insert(cached)
        return cached
    }

    public func upsert(members: [MattermostChannelMember]) throws {
        for member in members {
            try upsert(member: member)
        }
    }

    @discardableResult
    public func upsert(unread: MattermostChannelUnread, userID: String) throws -> MattermostCachedChannelUnread {
        let id = MattermostCachedChannelUnread.cacheID(
            channelID: unread.channelId,
            userID: userID
        )
        if let cached = try cachedChannelUnread(id: id) {
            cached.apply(unread, userID: userID)
            return cached
        }

        let cached = MattermostCachedChannelUnread(unread, userID: userID)
        context.insert(cached)
        return cached
    }

    @discardableResult
    public func upsert(post: MattermostPost) throws -> MattermostCachedPost {
        let propsJSON = try MattermostCachedPost.encodedJSON(post.props)
        let metadataJSON = try MattermostCachedPost.encodedJSON(post.metadata)

        if let cached = try cachedPost(id: post.id) {
            cached.apply(post, propsJSON: propsJSON, metadataJSON: metadataJSON)
            return cached
        }

        let cached = MattermostCachedPost(post, propsJSON: propsJSON, metadataJSON: metadataJSON)
        context.insert(cached)
        return cached
    }

    public func upsert(postList: MattermostPostList) throws {
        for post in postList.orderedPosts {
            try upsert(post: post)
        }
    }

    @discardableResult
    public func upsert(thread: MattermostThreadResponse, userID: String, teamID: String) throws -> MattermostCachedThread {
        if let post = thread.post {
            try upsert(post: post)
        }
        try upsert(users: thread.participants)

        let id = MattermostCachedThread.cacheID(rootID: thread.id, userID: userID, teamID: teamID)
        if let cached = try cachedThreadState(id: id) {
            cached.apply(thread, userID: userID, teamID: teamID)
            return cached
        }

        let cached = MattermostCachedThread(thread, userID: userID, teamID: teamID)
        context.insert(cached)
        return cached
    }

    public func upsert(threads: MattermostThreadList, userID: String, teamID: String) throws {
        for thread in threads.threads {
            try upsert(thread: thread, userID: userID, teamID: teamID)
        }
    }

    @discardableResult
    public func upsert(reaction: MattermostReaction) throws -> MattermostCachedReaction {
        let id = MattermostCachedReaction.cacheID(
            userID: reaction.userId,
            postID: reaction.postId,
            emojiName: reaction.emojiName
        )
        if let cached = try cachedReaction(id: id) {
            cached.apply(reaction)
            return cached
        }

        let cached = MattermostCachedReaction(reaction)
        context.insert(cached)
        return cached
    }

    public func upsert(reactions: [MattermostReaction]) throws {
        for reaction in reactions {
            try upsert(reaction: reaction)
        }
    }

    @discardableResult
    public func upsert(file: MattermostFileInfo) throws -> MattermostCachedFile {
        if let cached = try cachedFile(id: file.id) {
            cached.apply(file)
            return cached
        }

        let cached = MattermostCachedFile(file)
        context.insert(cached)
        return cached
    }

    public func upsert(files: [MattermostFileInfo]) throws {
        for file in files {
            try upsert(file: file)
        }
    }

    @discardableResult
    public func upsert(sidebarCategory: MattermostSidebarCategory) throws -> MattermostCachedSidebarCategory {
        if let cached = try cachedSidebarCategory(id: sidebarCategory.id) {
            cached.apply(sidebarCategory)
            return cached
        }

        let cached = MattermostCachedSidebarCategory(sidebarCategory)
        context.insert(cached)
        return cached
    }

    public func upsert(sidebarCategories: [MattermostSidebarCategory]) throws {
        for sidebarCategory in sidebarCategories {
            try upsert(sidebarCategory: sidebarCategory)
        }
    }

    public func cachedUser(id: String) throws -> MattermostCachedUser? {
        var descriptor = FetchDescriptor<MattermostCachedUser>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedUserStatus(userID: String) throws -> MattermostCachedUserStatus? {
        var descriptor = FetchDescriptor<MattermostCachedUserStatus>(
            predicate: #Predicate { $0.userId == userID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedUsers() throws -> [MattermostCachedUser] {
        try context.fetch(
            FetchDescriptor(sortBy: [SortDescriptor(\MattermostCachedUser.username)])
        )
    }

    public func cachedTeam(id: String) throws -> MattermostCachedTeam? {
        var descriptor = FetchDescriptor<MattermostCachedTeam>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedTeams() throws -> [MattermostCachedTeam] {
        try context.fetch(
            FetchDescriptor(sortBy: [SortDescriptor(\MattermostCachedTeam.displayName)])
        )
    }

    public func cachedChannel(id: String) throws -> MattermostCachedChannel? {
        var descriptor = FetchDescriptor<MattermostCachedChannel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedChannels(teamID: String? = nil) throws -> [MattermostCachedChannel] {
        let sort = [SortDescriptor(\MattermostCachedChannel.displayName)]
        if let teamID {
            return try context.fetch(
                FetchDescriptor(
                    predicate: #Predicate { $0.teamId == teamID },
                    sortBy: sort
                )
            )
        }

        return try context.fetch(FetchDescriptor(sortBy: sort))
    }

    public func cachedChannelMember(channelID: String, userID: String) throws -> MattermostCachedChannelMember? {
        try cachedChannelMember(id: MattermostCachedChannelMember.cacheID(channelID: channelID, userID: userID))
    }

    public func cachedChannelMember(id: String) throws -> MattermostCachedChannelMember? {
        var descriptor = FetchDescriptor<MattermostCachedChannelMember>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedChannelMembers(userID: String? = nil) throws -> [MattermostCachedChannelMember] {
        let sort = [SortDescriptor(\MattermostCachedChannelMember.channelId)]
        if let userID {
            return try context.fetch(
                FetchDescriptor(
                    predicate: #Predicate { $0.userId == userID },
                    sortBy: sort
                )
            )
        }

        return try context.fetch(FetchDescriptor(sortBy: sort))
    }

    public func cachedChannelUnread(channelID: String, userID: String) throws -> MattermostCachedChannelUnread? {
        try cachedChannelUnread(id: MattermostCachedChannelUnread.cacheID(channelID: channelID, userID: userID))
    }

    public func cachedChannelUnread(id: String) throws -> MattermostCachedChannelUnread? {
        var descriptor = FetchDescriptor<MattermostCachedChannelUnread>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedChannelUnreads(userID: String? = nil) throws -> [MattermostCachedChannelUnread] {
        let sort = [SortDescriptor(\MattermostCachedChannelUnread.channelId)]
        if let userID {
            return try context.fetch(
                FetchDescriptor(
                    predicate: #Predicate { $0.userId == userID },
                    sortBy: sort
                )
            )
        }

        return try context.fetch(FetchDescriptor(sortBy: sort))
    }

    public func cachedPost(id: String) throws -> MattermostCachedPost? {
        var descriptor = FetchDescriptor<MattermostCachedPost>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedPosts(
        channelID: String,
        limit: Int? = nil,
        includeDeleted: Bool = true
    ) throws -> [MattermostCachedPost] {
        var descriptor = FetchDescriptor<MattermostCachedPost>(
            predicate: #Predicate { $0.channelId == channelID },
            sortBy: [SortDescriptor(\MattermostCachedPost.createAt, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        let posts = try context.fetch(descriptor)
        guard !includeDeleted else {
            return posts
        }
        return posts.filter { !$0.isDeleted }
    }

    public func cachedThread(rootID: String, includeDeleted: Bool = true) throws -> [MattermostCachedPost] {
        let posts = try context.fetch(
            FetchDescriptor(
                predicate: #Predicate { $0.id == rootID || $0.rootId == rootID },
                sortBy: [SortDescriptor(\MattermostCachedPost.createAt)]
            )
        )
        guard !includeDeleted else {
            return posts
        }
        return posts.filter { !$0.isDeleted }
    }

    public func cachedThreadState(rootID: String, userID: String, teamID: String) throws -> MattermostCachedThread? {
        try cachedThreadState(id: MattermostCachedThread.cacheID(rootID: rootID, userID: userID, teamID: teamID))
    }

    public func cachedThreadState(id: String) throws -> MattermostCachedThread? {
        var descriptor = FetchDescriptor<MattermostCachedThread>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedThreadStates(userID: String? = nil, teamID: String? = nil, unreadOnly: Bool = false) throws -> [MattermostCachedThread] {
        let threads = try context.fetch(
            FetchDescriptor(sortBy: [SortDescriptor(\MattermostCachedThread.lastReplyAt, order: .reverse)])
        )
        return threads.filter { thread in
            if let userID, thread.userId != userID {
                return false
            }
            if let teamID, thread.teamId != teamID {
                return false
            }
            if unreadOnly, !thread.isUnread {
                return false
            }
            return true
        }
    }

    public func cachedTimeline(
        _ target: MattermostTimelineTarget,
        limit: Int? = nil,
        includeDeleted: Bool = true
    ) throws -> [MattermostCachedPost] {
        switch target {
        case .channel(let channelID):
            return try cachedPosts(channelID: channelID, limit: limit, includeDeleted: includeDeleted)
        case .thread(let rootPostID):
            var descriptor = FetchDescriptor<MattermostCachedPost>(
                predicate: #Predicate { $0.id == rootPostID || $0.rootId == rootPostID },
                sortBy: [SortDescriptor(\MattermostCachedPost.createAt)]
            )
            if let limit {
                descriptor.fetchLimit = limit
            }
            let posts = try context.fetch(descriptor)
            guard !includeDeleted else {
                return posts
            }
            return posts.filter { !$0.isDeleted }
        }
    }

    public func cachedReaction(id: String) throws -> MattermostCachedReaction? {
        var descriptor = FetchDescriptor<MattermostCachedReaction>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedReactions(postID: String) throws -> [MattermostCachedReaction] {
        try context.fetch(
            FetchDescriptor(
                predicate: #Predicate { $0.postId == postID },
                sortBy: [SortDescriptor(\MattermostCachedReaction.emojiName)]
            )
        )
    }

    public func deleteCachedReaction(id: String) throws {
        if let reaction = try cachedReaction(id: id) {
            context.delete(reaction)
        }
    }

    public func cachedFile(id: String) throws -> MattermostCachedFile? {
        var descriptor = FetchDescriptor<MattermostCachedFile>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedFiles(postID: String) throws -> [MattermostCachedFile] {
        try context.fetch(
            FetchDescriptor(
                predicate: #Predicate { $0.postId == postID },
                sortBy: [SortDescriptor(\MattermostCachedFile.name)]
            )
        )
    }

    public func cachedSidebarCategory(id: String) throws -> MattermostCachedSidebarCategory? {
        var descriptor = FetchDescriptor<MattermostCachedSidebarCategory>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedSidebarCategories(teamID: String? = nil) throws -> [MattermostCachedSidebarCategory] {
        let sort = [SortDescriptor(\MattermostCachedSidebarCategory.sortOrder)]
        if let teamID {
            return try context.fetch(
                FetchDescriptor(
                    predicate: #Predicate { $0.teamId == teamID },
                    sortBy: sort
                )
            )
        }

        return try context.fetch(FetchDescriptor(sortBy: sort))
    }

    public func cachedSyncCursor(scope: String) throws -> MattermostSyncCursor? {
        var descriptor = FetchDescriptor<MattermostSyncCursor>(
            predicate: #Predicate { $0.scope == scope }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public func setSyncCursor(
        scope: String,
        lastSyncAt: Int64,
        lastItemID: String? = nil
    ) throws -> MattermostSyncCursor {
        if let cursor = try cachedSyncCursor(scope: scope) {
            cursor.lastSyncAt = lastSyncAt
            cursor.lastItemID = lastItemID
            return cursor
        }

        let cursor = MattermostSyncCursor(scope: scope, lastSyncAt: lastSyncAt, lastItemID: lastItemID)
        context.insert(cursor)
        return cursor
    }

    @discardableResult
    public func apply(liveEvent: MattermostLiveEvent) throws -> MattermostTypedLiveEvent {
        let typedEvent = try liveEvent.typedEvent()

        switch typedEvent {
        case .posted(let post), .postEdited(let post):
            try upsert(post: post)
        case .postDeleted(let post):
            if let post {
                try upsert(post: post)
            } else if let postID = liveEvent.stringData("post_id") ?? liveEvent.stringData("postId") {
                let deletedAt = liveEvent.int64Data("delete_at")
                    ?? liveEvent.int64Data("deleteAt")
                    ?? liveEvent.int64Data("update_at")
                    ?? liveEvent.int64Data("updateAt")
                    ?? Int64(Date.now.timeIntervalSince1970 * 1000)
                try markPostDeleted(id: postID, at: deletedAt)
            }
        case .reactionAdded(let reaction):
            if let reaction {
                try upsert(reaction: reaction)
            }
        case .reactionRemoved(let reaction):
            if let reaction {
                let id = MattermostCachedReaction.cacheID(
                    userID: reaction.userId,
                    postID: reaction.postId,
                    emojiName: reaction.emojiName
                )
                try deleteCachedReaction(id: id)
            }
        case .statusChange(let statusChange):
            if let userID = statusChange.userID, let status = statusChange.status {
                let cachedStatus = MattermostCachedUserStatus(
                    userId: userID,
                    status: status,
                    manual: statusChange.manual
                )
                if let existing = try cachedUserStatus(userID: userID) {
                    existing.status = cachedStatus.status
                    existing.manual = cachedStatus.manual
                } else {
                    context.insert(cachedStatus)
                }
            }
        case .channelCreated(let channel), .channelUpdated(let channel):
            if let channel {
                try upsert(channel: channel)
            }
        case .channelDeleted(let channel, let channelID):
            if let channel {
                try upsert(channel: channel)
                try markChannelDeleted(id: channel.id, at: channel.deleteAt ?? Int64(Date.now.timeIntervalSince1970 * 1000))
            } else if let channelID {
                try markChannelDeleted(id: channelID)
            }
        case .channelMemberUpdated(let member):
            if let member {
                try upsert(member: member)
            }
        case .userUpdated(let user):
            if let user {
                try upsert(user: user)
            }
        case .hello,
             .typing,
             .channelViewed,
             .preferencesChanged,
             .preferencesDeleted,
             .postUnread,
             .response,
             .threadUpdated,
             .threadFollowChanged,
             .threadReadChanged,
             .cacheInvalidated,
             .unknown:
            break
        }

        return typedEvent
    }
}

@Model
public final class MattermostCachedUser {
    @Attribute(.unique) public var id: String = ""
    public var username: String = ""
    public var email: String?
    public var firstName: String?
    public var lastName: String?
    public var nickname: String?
    public var position: String?
    public var locale: String?

    init(_ user: MattermostUser) {
        self.id = user.id
        self.username = user.username
        email = user.email
        firstName = user.firstName
        lastName = user.lastName
        nickname = user.nickname
        position = user.position
        locale = user.locale
    }

    func apply(_ user: MattermostUser) {
        username = user.username
        email = user.email
        firstName = user.firstName
        lastName = user.lastName
        nickname = user.nickname
        position = user.position
        locale = user.locale
    }
}

@Model
public final class MattermostCachedUserStatus {
    @Attribute(.unique) public var userId: String = ""
    public var status: String = ""
    public var manual: Bool?
    public var lastActivityAt: Int64?
    public var activeChannel: String?
    public var dndEndTime: Int64?

    public init(
        userId: String,
        status: String,
        manual: Bool? = nil,
        lastActivityAt: Int64? = nil,
        activeChannel: String? = nil,
        dndEndTime: Int64? = nil
    ) {
        self.userId = userId
        self.status = status
        self.manual = manual
        self.lastActivityAt = lastActivityAt
        self.activeChannel = activeChannel
        self.dndEndTime = dndEndTime
    }

    init(_ status: MattermostUserStatus) {
        userId = status.userId
        self.status = status.status
        manual = status.manual
        lastActivityAt = status.lastActivityAt
        activeChannel = status.activeChannel
        dndEndTime = status.dndEndTime
    }

    func apply(_ status: MattermostUserStatus) {
        self.status = status.status
        manual = status.manual
        lastActivityAt = status.lastActivityAt
        activeChannel = status.activeChannel
        dndEndTime = status.dndEndTime
    }
}

@Model
public final class MattermostCachedTeam {
    @Attribute(.unique) public var id: String = ""
    public var name: String = ""
    public var displayName: String = ""
    public var descriptionText: String?
    public var type: String?

    init(_ team: MattermostTeam) {
        id = team.id
        name = team.name
        displayName = team.displayName
        descriptionText = team.description
        type = team.type
    }

    func apply(_ team: MattermostTeam) {
        name = team.name
        displayName = team.displayName
        descriptionText = team.description
        type = team.type
    }
}

@Model
public final class MattermostCachedChannel {
    @Attribute(.unique) public var id: String = ""
    public var createAt: Int64?
    public var updateAt: Int64?
    public var teamId: String?
    public var name: String = ""
    public var displayName: String = ""
    public var type: String = ""
    public var header: String?
    public var purpose: String?
    public var deleteAt: Int64?

    init(_ channel: MattermostChannel) {
        id = channel.id
        createAt = channel.createAt
        updateAt = channel.updateAt
        teamId = channel.teamId
        name = channel.name
        displayName = channel.displayName
        type = channel.type
        header = channel.header
        purpose = channel.purpose
        deleteAt = channel.deleteAt
    }

    func apply(_ channel: MattermostChannel) {
        guard shouldApply(channel) else {
            return
        }

        createAt = channel.createAt
        updateAt = channel.updateAt
        teamId = channel.teamId
        name = channel.name
        displayName = channel.displayName
        type = channel.type
        header = channel.header
        purpose = channel.purpose
        deleteAt = channel.deleteAt
    }

    func markDeleted(at deletedAt: Int64) {
        deleteAt = max(deleteAt ?? 0, deletedAt)
    }

    var cacheTimestamp: Int64 {
        max(createAt ?? 0, updateAt ?? 0, deleteAt ?? 0)
    }

    private func shouldApply(_ channel: MattermostChannel) -> Bool {
        let incomingTimestamp = channel.cacheTimestamp
        guard incomingTimestamp > 0, cacheTimestamp > 0 else {
            return true
        }
        return incomingTimestamp >= cacheTimestamp
    }
}

@Model
public final class MattermostCachedChannelMember {
    @Attribute(.unique) public var id: String = ""
    public var channelId: String = ""
    public var userId: String = ""
    public var roles: String?
    public var lastViewedAt: Int64?
    public var msgCount: Int?
    public var mentionCount: Int?
    public var notifyProps: [String: String] = [:]
    public var lastUpdateAt: Int64?

    public var channelNotifyProps: MattermostChannelNotifyProps {
        MattermostChannelNotifyProps(notifyProps)
    }

    init(_ member: MattermostChannelMember) {
        id = Self.cacheID(channelID: member.channelId, userID: member.userId)
        channelId = member.channelId
        userId = member.userId
        roles = member.roles
        lastViewedAt = member.lastViewedAt
        msgCount = member.msgCount
        mentionCount = member.mentionCount
        notifyProps = member.notifyProps ?? [:]
        lastUpdateAt = member.lastUpdateAt
    }

    public static func cacheID(channelID: String, userID: String) -> String {
        "\(channelID):\(userID)"
    }

    func apply(_ member: MattermostChannelMember) {
        channelId = member.channelId
        userId = member.userId
        roles = member.roles
        lastViewedAt = member.lastViewedAt
        msgCount = member.msgCount
        mentionCount = member.mentionCount
        notifyProps = member.notifyProps ?? [:]
        lastUpdateAt = member.lastUpdateAt
    }
}

@Model
public final class MattermostCachedChannelUnread {
    @Attribute(.unique) public var id: String = ""
    public var teamId: String?
    public var channelId: String = ""
    public var userId: String = ""
    public var msgCount: Int = 0
    public var mentionCount: Int = 0

    init(_ unread: MattermostChannelUnread, userID: String) {
        id = Self.cacheID(channelID: unread.channelId, userID: userID)
        teamId = unread.teamId
        channelId = unread.channelId
        self.userId = userID
        msgCount = unread.msgCount
        mentionCount = unread.mentionCount
    }

    public static func cacheID(channelID: String, userID: String) -> String {
        "\(channelID):\(userID)"
    }

    func apply(_ unread: MattermostChannelUnread, userID: String) {
        teamId = unread.teamId
        channelId = unread.channelId
        self.userId = userID
        msgCount = unread.msgCount
        mentionCount = unread.mentionCount
    }
}

@Model
public final class MattermostCachedThread {
    @Attribute(.unique) public var id: String = ""
    public var rootId: String = ""
    public var userId: String = ""
    public var teamId: String = ""
    public var replyCount: Int64 = 0
    public var lastReplyAt: Int64 = 0
    public var lastViewedAt: Int64 = 0
    public var unreadReplies: Int64 = 0
    public var unreadMentions: Int64 = 0
    public var isUrgent: Bool = false
    public var deleteAt: Int64 = 0
    public var participantIds: [String] = []

    public var isUnread: Bool {
        unreadReplies > 0 || unreadMentions > 0
    }

    init(_ thread: MattermostThreadResponse, userID: String, teamID: String) {
        id = Self.cacheID(rootID: thread.id, userID: userID, teamID: teamID)
        rootId = thread.id
        userId = userID
        self.teamId = teamID
        replyCount = thread.replyCount
        lastReplyAt = thread.lastReplyAt
        lastViewedAt = thread.lastViewedAt
        unreadReplies = thread.unreadReplies
        unreadMentions = thread.unreadMentions
        isUrgent = thread.isUrgent
        deleteAt = thread.deleteAt
        participantIds = thread.participants.map(\.id)
    }

    public static func cacheID(rootID: String, userID: String, teamID: String) -> String {
        "\(teamID):\(userID):\(rootID)"
    }

    func apply(_ thread: MattermostThreadResponse, userID: String, teamID: String) {
        guard shouldApply(thread) else {
            return
        }

        rootId = thread.id
        self.userId = userID
        self.teamId = teamID
        replyCount = thread.replyCount
        lastReplyAt = thread.lastReplyAt
        lastViewedAt = thread.lastViewedAt
        unreadReplies = thread.unreadReplies
        unreadMentions = thread.unreadMentions
        isUrgent = thread.isUrgent
        deleteAt = thread.deleteAt
        participantIds = thread.participants.map(\.id)
    }

    var cacheTimestamp: Int64 {
        max(lastReplyAt, lastViewedAt, deleteAt)
    }

    private func shouldApply(_ thread: MattermostThreadResponse) -> Bool {
        let incomingTimestamp = max(thread.lastReplyAt, thread.lastViewedAt, thread.deleteAt)
        guard incomingTimestamp > 0, cacheTimestamp > 0 else {
            return true
        }
        return incomingTimestamp >= cacheTimestamp
    }
}

@Model
public final class MattermostCachedPost {
    @Attribute(.unique) public var id: String = ""
    public var createAt: Int64 = 0
    public var updateAt: Int64 = 0
    public var editAt: Int64 = 0
    public var deleteAt: Int64 = 0
    public var userId: String = ""
    public var channelId: String = ""
    public var rootId: String = ""
    public var originalId: String?
    public var message: String = ""
    public var type: String = ""
    public var hashtags: String?
    public var pendingPostId: String?
    public var fileIds: [String] = []
    public var hasReactions: Bool?
    public var propsJSON: String?
    public var metadataJSON: String?

    init(_ post: MattermostPost, propsJSON: String?, metadataJSON: String?) {
        id = post.id
        createAt = post.createAt
        updateAt = post.updateAt
        editAt = post.editAt
        deleteAt = post.deleteAt
        userId = post.userId
        channelId = post.channelId
        rootId = post.rootId
        originalId = post.originalId
        message = post.message
        type = post.type
        hashtags = post.hashtags
        pendingPostId = post.pendingPostId
        fileIds = post.fileIds ?? []
        hasReactions = post.hasReactions
        self.propsJSON = propsJSON
        self.metadataJSON = metadataJSON
    }

    public static func encodedJSON(_ value: [String: MattermostJSONValue]?) throws -> String? {
        guard let value else {
            return nil
        }

        let data = try mattermostCachedPostEncoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    public func decodedProps() throws -> [String: MattermostJSONValue]? {
        try Self.decodedJSON(propsJSON)
    }

    public func decodedMetadata() throws -> [String: MattermostJSONValue]? {
        try Self.decodedJSON(metadataJSON)
    }

    public var isDeleted: Bool {
        deleteAt > 0
    }

    func apply(_ post: MattermostPost, propsJSON: String?, metadataJSON: String?) {
        guard shouldApply(post) else {
            return
        }

        createAt = post.createAt
        updateAt = post.updateAt
        editAt = post.editAt
        deleteAt = post.deleteAt
        userId = post.userId
        channelId = post.channelId
        rootId = post.rootId
        originalId = post.originalId
        message = post.message
        type = post.type
        hashtags = post.hashtags
        pendingPostId = post.pendingPostId
        fileIds = post.fileIds ?? []
        hasReactions = post.hasReactions
        self.propsJSON = propsJSON
        self.metadataJSON = metadataJSON
    }

    var cacheTimestamp: Int64 {
        max(createAt, updateAt, editAt, deleteAt)
    }

    private static func decodedJSON(_ string: String?) throws -> [String: MattermostJSONValue]? {
        guard let string else {
            return nil
        }

        return try mattermostCachedPostDecoder.decode([String: MattermostJSONValue].self, from: Data(string.utf8))
    }

    func markDeleted(at deletedAt: Int64) {
        deleteAt = max(deleteAt, deletedAt)
    }

    private func shouldApply(_ post: MattermostPost) -> Bool {
        let incomingTimestamp = post.cacheTimestamp
        guard incomingTimestamp > 0, cacheTimestamp > 0 else {
            return true
        }
        return incomingTimestamp >= cacheTimestamp
    }
}

@Model
public final class MattermostCachedReaction {
    @Attribute(.unique) public var id: String = ""
    public var userId: String = ""
    public var postId: String = ""
    public var emojiName: String = ""
    public var createAt: Int64?

    init(_ reaction: MattermostReaction) {
        id = Self.cacheID(
            userID: reaction.userId,
            postID: reaction.postId,
            emojiName: reaction.emojiName
        )
        userId = reaction.userId
        postId = reaction.postId
        emojiName = reaction.emojiName
        createAt = reaction.createAt
    }

    public static func cacheID(userID: String, postID: String, emojiName: String) -> String {
        "\(postID):\(userID):\(emojiName)"
    }

    func apply(_ reaction: MattermostReaction) {
        userId = reaction.userId
        postId = reaction.postId
        emojiName = reaction.emojiName
        createAt = reaction.createAt
    }
}

@Model
public final class MattermostCachedFile {
    @Attribute(.unique) public var id: String = ""
    public var userId: String?
    public var postId: String?
    public var createAt: Int64?
    public var updateAt: Int64?
    public var deleteAt: Int64?
    public var name: String = ""
    public var extensionName: String?
    public var size: Int64?
    public var mimeType: String?
    public var width: Int?
    public var height: Int?
    public var hasPreviewImage: Bool?

    init(_ file: MattermostFileInfo) {
        id = file.id
        userId = file.userId
        postId = file.postId
        createAt = file.createAt
        updateAt = file.updateAt
        deleteAt = file.deleteAt
        name = file.name
        extensionName = file.extensionName
        size = file.size
        mimeType = file.mimeType
        width = file.width
        height = file.height
        hasPreviewImage = file.hasPreviewImage
    }

    func apply(_ file: MattermostFileInfo) {
        userId = file.userId
        postId = file.postId
        createAt = file.createAt
        updateAt = file.updateAt
        deleteAt = file.deleteAt
        name = file.name
        extensionName = file.extensionName
        size = file.size
        mimeType = file.mimeType
        width = file.width
        height = file.height
        hasPreviewImage = file.hasPreviewImage
    }
}

@Model
public final class MattermostCachedSidebarCategory {
    @Attribute(.unique) public var id: String = ""
    public var userId: String?
    public var teamId: String?
    public var displayName: String = ""
    public var type: String = ""
    public var sortOrder: Int?
    public var channelIds: [String] = []
    public var sorting: String?
    public var muted: Bool?
    public var collapsed: Bool?

    init(_ category: MattermostSidebarCategory) {
        id = category.id
        userId = category.userId
        teamId = category.teamId
        displayName = category.displayName
        type = category.type
        sortOrder = category.sortOrder
        channelIds = category.channelIds
        sorting = category.sorting
        muted = category.muted
        collapsed = category.collapsed
    }

    func apply(_ category: MattermostSidebarCategory) {
        userId = category.userId
        teamId = category.teamId
        displayName = category.displayName
        type = category.type
        sortOrder = category.sortOrder
        channelIds = category.channelIds
        sorting = category.sorting
        muted = category.muted
        collapsed = category.collapsed
    }
}

@Model
public final class MattermostSyncCursor {
    @Attribute(.unique) public var scope: String = ""
    public var lastSyncAt: Int64 = 0
    public var lastItemID: String?

    public init(scope: String, lastSyncAt: Int64, lastItemID: String? = nil) {
        self.scope = scope
        self.lastSyncAt = lastSyncAt
        self.lastItemID = lastItemID
    }
}
