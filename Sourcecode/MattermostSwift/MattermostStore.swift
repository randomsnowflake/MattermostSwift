import Foundation
import SwiftData

/// SwiftData-backed cache for Mattermost objects used by app targets and the CLI.
///
/// Host apps own retention policy. Use pruning helpers such as
/// `prunePosts(channelID:keepCount:)` and `deleteChannelContent(channelID:)` during
/// background maintenance or channel lifecycle events to keep long-lived stores bounded.
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
        if let cached = try cachedPost(id: post.id) {
            try cached.apply(post)
            return cached
        }

        let propsJSON = try MattermostCachedPost.encodedJSON(post.props)
        let metadataJSON = try MattermostCachedPost.encodedJSON(post.metadata)
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

    public func cachedUsersCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedUser>())
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

    public func cachedTeamsCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedTeam>())
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

    public func cachedChannelsCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedChannel>())
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

    public func cachedChannelMembersCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedChannelMember>())
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

    public func cachedChannelUnreadsCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedChannelUnread>())
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
        var descriptor = FetchDescriptor<MattermostCachedThread>(
            sortBy: [SortDescriptor(\MattermostCachedThread.lastReplyAt, order: .reverse)]
        )
        if let userID, let teamID {
            descriptor.predicate = #Predicate { $0.userId == userID && $0.teamId == teamID }
        } else if let userID {
            descriptor.predicate = #Predicate { $0.userId == userID }
        } else if let teamID {
            descriptor.predicate = #Predicate { $0.teamId == teamID }
        }
        let threads = try context.fetch(descriptor)
        return unreadOnly ? threads.filter(\.isUnread) : threads
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

    public func prunePosts(channelID: String, keepCount: Int = 200) throws {
        let keepCount = max(0, keepCount)
        let posts = try cachedPosts(channelID: channelID)
        for post in posts.dropFirst(keepCount) {
            context.delete(post)
        }
    }

    public func deleteChannelContent(channelID: String) throws {
        let posts = try cachedPosts(channelID: channelID)
        let postIDs = posts.map(\.id)

        for post in posts {
            context.delete(post)
        }
        for unread in try context.fetch(FetchDescriptor<MattermostCachedChannelUnread>(
            predicate: #Predicate { $0.channelId == channelID }
        )) {
            context.delete(unread)
        }
        guard !postIDs.isEmpty else {
            return
        }
        for reaction in try context.fetch(FetchDescriptor<MattermostCachedReaction>()) where postIDs.contains(reaction.postId) {
            context.delete(reaction)
        }
        for file in try context.fetch(FetchDescriptor<MattermostCachedFile>()) where file.postId.map(postIDs.contains) == true {
            context.delete(file)
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
                try deleteChannelContent(channelID: channel.id)
            } else if let channelID {
                try markChannelDeleted(id: channelID)
                try deleteChannelContent(channelID: channelID)
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
