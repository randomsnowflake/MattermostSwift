import Foundation
import SwiftData

/// SwiftData-backed cache for Mattermost objects used by app targets and the CLI.
///
/// Host apps own retention policy. Use pruning helpers such as
/// `prunePosts(channelID:keepCount:)` and `deleteChannelContent(channelID:)` during
/// background maintenance or channel lifecycle events to keep long-lived stores bounded.
@MainActor
public final class MattermostStore {
    private static let batchedFetchIDLimit = 500

    public static var schema: Schema {
        Schema(versionedSchema: MattermostCacheSchemaV1.self)
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

        let container = try ModelContainer(
            for: schema,
            migrationPlan: MattermostCacheMigrationPlan.self,
            configurations: [configuration]
        )
        self.init(container: container)
    }

    public func save() throws {
        try context.save()
    }

    private func fetchInBatches<Model: PersistentModel>(
        ids: [String],
        descriptor: ([String]) -> FetchDescriptor<Model>
    ) throws -> [Model] {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return [] }

        var models: [Model] = []
        var start = 0
        while start < uniqueIDs.count {
            let end = min(start + Self.batchedFetchIDLimit, uniqueIDs.count)
            let chunkIDs = Array(uniqueIDs[start..<end])
            models.append(contentsOf: try context.fetch(descriptor(chunkIDs)))
            start = end
        }
        return models
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
        guard !users.isEmpty else { return }
        let ids = users.map(\.id)
        let existing = try fetchInBatches(ids: ids) { chunkIDs in
            FetchDescriptor<MattermostCachedUser>(predicate: #Predicate { chunkIDs.contains($0.id) })
        }
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for user in users {
            if let cached = byID[user.id] {
                cached.apply(user)
            } else {
                let cached = MattermostCachedUser(user)
                context.insert(cached)
                byID[user.id] = cached
            }
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
        guard !statuses.isEmpty else { return }
        let ids = statuses.map(\.userId)
        let existing = try fetchInBatches(ids: ids) { chunkIDs in
            FetchDescriptor<MattermostCachedUserStatus>(predicate: #Predicate { chunkIDs.contains($0.userId) })
        }
        var byID = Dictionary(existing.map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a })
        for status in statuses {
            if let cached = byID[status.userId] {
                cached.apply(status)
            } else {
                let cached = MattermostCachedUserStatus(status)
                context.insert(cached)
                byID[status.userId] = cached
            }
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
        guard !teams.isEmpty else { return }
        let ids = teams.map(\.id)
        let existing = try fetchInBatches(ids: ids) { chunkIDs in
            FetchDescriptor<MattermostCachedTeam>(predicate: #Predicate { chunkIDs.contains($0.id) })
        }
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for team in teams {
            if let cached = byID[team.id] {
                cached.apply(team)
            } else {
                let cached = MattermostCachedTeam(team)
                context.insert(cached)
                byID[team.id] = cached
            }
        }
    }

    @discardableResult
    public func upsert(channel: MattermostChannel) throws -> MattermostCachedChannel {
        if let cached = try cachedChannel(id: channel.id, includeDeleted: true) {
            cached.apply(channel)
            return cached
        }

        let cached = MattermostCachedChannel(channel)
        context.insert(cached)
        return cached
    }

    public func upsert(channels: [MattermostChannel]) throws {
        guard !channels.isEmpty else { return }
        let ids = channels.map(\.id)
        let existing = try fetchInBatches(ids: ids) { chunkIDs in
            FetchDescriptor<MattermostCachedChannel>(predicate: #Predicate { chunkIDs.contains($0.id) })
        }
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for channel in channels {
            if let cached = byID[channel.id] {
                cached.apply(channel)
            } else {
                let cached = MattermostCachedChannel(channel)
                context.insert(cached)
                byID[channel.id] = cached
            }
        }
    }

    /// Replaces the server-authoritative joined-channel collection for one team.
    /// Rows absent from this proven team scope are removed together with their local content.
    public func replaceJoinedChannels(_ channels: [MattermostChannel], teamID: String) throws {
        try upsert(channels: channels)
        let retained = Set(channels.map(\.id))
        let existing = try context.fetch(FetchDescriptor<MattermostCachedChannel>(
            predicate: #Predicate { $0.teamId == teamID }
        ))
        for channel in existing where !retained.contains(channel.id) {
            let channelID = channel.id
            try deleteChannelContent(channelID: channelID)
            for member in try context.fetch(FetchDescriptor<MattermostCachedChannelMember>(
                predicate: #Predicate { $0.channelId == channelID }
            )) {
                context.delete(member)
            }
            context.delete(channel)
        }
    }

    public func markChannelDeleted(id: String, at deletedAt: Int64 = Int64(Date.now.timeIntervalSince1970 * 1000)) throws {
        if let cached = try cachedChannel(id: id, includeDeleted: true) {
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
        guard !members.isEmpty else { return }
        let ids = members.map {
            MattermostCachedChannelMember.cacheID(channelID: $0.channelId, userID: $0.userId)
        }
        let existing = try fetchInBatches(ids: ids) { chunkIDs in
            FetchDescriptor<MattermostCachedChannelMember>(predicate: #Predicate { chunkIDs.contains($0.id) })
        }
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for member in members {
            let id = MattermostCachedChannelMember.cacheID(channelID: member.channelId, userID: member.userId)
            if let cached = byID[id] {
                cached.apply(member)
            } else {
                let cached = MattermostCachedChannelMember(member)
                context.insert(cached)
                byID[id] = cached
            }
        }
    }

    /// Replaces the active user's memberships for the channels belonging to one team.
    /// The caller must pass a complete response for that user/team; an empty array is meaningful.
    public func replaceChannelMembers(
        _ members: [MattermostChannelMember],
        userID: String,
        teamID: String
    ) throws {
        try upsert(members: members)
        let teamChannelIDs = Set(try context.fetch(FetchDescriptor<MattermostCachedChannel>(
            predicate: #Predicate { $0.teamId == teamID }
        )).map(\.id))
        let retained = Set(members.map(\.channelId))
        let existing = try cachedChannelMembers(userID: userID)
        for member in existing
            where teamChannelIDs.contains(member.channelId) && !retained.contains(member.channelId) {
            context.delete(member)
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
        try upsert(posts: postList.orderedPosts)
    }

    private func upsert(posts: [MattermostPost]) throws {
        guard !posts.isEmpty else { return }
        let ids = posts.map(\.id)
        let existing = try fetchInBatches(ids: ids) { chunkIDs in
            FetchDescriptor<MattermostCachedPost>(predicate: #Predicate { chunkIDs.contains($0.id) })
        }
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for post in posts {
            if let cached = byID[post.id] {
                try cached.apply(post)
            } else {
                let propsJSON = try MattermostCachedPost.encodedJSON(post.props)
                let metadataJSON = try MattermostCachedPost.encodedJSON(post.metadata)
                let cached = MattermostCachedPost(post, propsJSON: propsJSON, metadataJSON: metadataJSON)
                context.insert(cached)
                byID[post.id] = cached
            }
        }
    }

    @discardableResult
    public func upsert(thread: MattermostThreadResponse, userID: String, teamID: String) throws -> MattermostCachedThread {
        if let post = thread.post {
            try upsert(post: post)
        }
        try upsert(users: thread.participants)

        return try upsertThreadState(thread, userID: userID, teamID: teamID)
    }

    public func upsert(threads: MattermostThreadList, userID: String, teamID: String) throws {
        guard !threads.threads.isEmpty else { return }

        let posts = threads.threads.compactMap(\.post)
        let participants = threads.threads.flatMap(\.participants)
        try upsert(posts: posts)
        try upsert(users: participants)

        for thread in threads.threads {
            try upsertThreadState(thread, userID: userID, teamID: teamID)
        }
    }

    @discardableResult
    private func upsertThreadState(_ thread: MattermostThreadResponse, userID: String, teamID: String) throws -> MattermostCachedThread {
        let id = MattermostCachedThread.cacheID(rootID: thread.id, userID: userID, teamID: teamID)
        if let cached = try cachedThreadState(id: id) {
            cached.apply(thread, userID: userID, teamID: teamID)
            return cached
        }

        let cached = MattermostCachedThread(thread, userID: userID, teamID: teamID)
        context.insert(cached)
        return cached
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
        guard !reactions.isEmpty else { return }
        let ids = reactions.map {
            MattermostCachedReaction.cacheID(userID: $0.userId, postID: $0.postId, emojiName: $0.emojiName)
        }
        let existing = try fetchInBatches(ids: ids) { chunkIDs in
            FetchDescriptor<MattermostCachedReaction>(predicate: #Predicate { chunkIDs.contains($0.id) })
        }
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for reaction in reactions {
            let id = MattermostCachedReaction.cacheID(userID: reaction.userId, postID: reaction.postId, emojiName: reaction.emojiName)
            if let cached = byID[id] {
                cached.apply(reaction)
            } else {
                let cached = MattermostCachedReaction(reaction)
                context.insert(cached)
                byID[id] = cached
            }
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
        guard !files.isEmpty else { return }
        let ids = files.map(\.id)
        let existing = try fetchInBatches(ids: ids) { chunkIDs in
            FetchDescriptor<MattermostCachedFile>(predicate: #Predicate { chunkIDs.contains($0.id) })
        }
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for file in files {
            if let cached = byID[file.id] {
                cached.apply(file)
            } else {
                let cached = MattermostCachedFile(file)
                context.insert(cached)
                byID[file.id] = cached
            }
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
        guard !sidebarCategories.isEmpty else { return }
        let ids = sidebarCategories.map(\.id)
        let existing = try fetchInBatches(ids: ids) { chunkIDs in
            FetchDescriptor<MattermostCachedSidebarCategory>(predicate: #Predicate { chunkIDs.contains($0.id) })
        }
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for sidebarCategory in sidebarCategories {
            if let cached = byID[sidebarCategory.id] {
                cached.apply(sidebarCategory)
            } else {
                let cached = MattermostCachedSidebarCategory(sidebarCategory)
                context.insert(cached)
                byID[sidebarCategory.id] = cached
            }
        }
    }

    /// Replaces one user's server-authoritative sidebar categories for a team.
    public func replaceSidebarCategories(
        _ categories: [MattermostSidebarCategory],
        userID: String,
        teamID: String
    ) throws {
        try upsert(sidebarCategories: categories)
        let retained = Set(categories.map(\.id))
        let existing = try context.fetch(FetchDescriptor<MattermostCachedSidebarCategory>(
            predicate: #Predicate { $0.userId == userID && $0.teamId == teamID }
        ))
        for category in existing where !retained.contains(category.id) {
            context.delete(category)
        }
    }

    /// Removes unread rows for channels no longer present in an authoritative team response.
    public func reconcileChannelUnreads(userID: String, teamID: String, channelIDs: [String]) throws {
        let retained = Set(channelIDs)
        let existing = try context.fetch(FetchDescriptor<MattermostCachedChannelUnread>(
            predicate: #Predicate { $0.userId == userID && $0.teamId == teamID }
        ))
        for unread in existing where !retained.contains(unread.channelId) {
            context.delete(unread)
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

    /// Returns immutable user values that can safely be retained or sent to another actor.
    public func cachedUserSnapshots() throws -> [MattermostCachedUserSnapshot] {
        try cachedUsers().map(MattermostCachedUserSnapshot.init)
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

    public func cachedChannel(id: String, includeDeleted: Bool = false) throws -> MattermostCachedChannel? {
        var descriptor: FetchDescriptor<MattermostCachedChannel>
        if includeDeleted {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.id == id })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate {
                $0.id == id && ($0.deleteAt == nil || $0.deleteAt == 0)
            })
        }
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func cachedChannels(
        teamID: String? = nil,
        includeDeleted: Bool = false
    ) throws -> [MattermostCachedChannel] {
        let sort = [SortDescriptor(\MattermostCachedChannel.displayName)]
        if let teamID, includeDeleted {
            return try context.fetch(
                FetchDescriptor(
                    predicate: #Predicate { $0.teamId == teamID },
                    sortBy: sort
                )
            )
        }
        if let teamID {
            return try context.fetch(FetchDescriptor(
                predicate: #Predicate {
                    $0.teamId == teamID && ($0.deleteAt == nil || $0.deleteAt == 0)
                },
                sortBy: sort
            ))
        }
        if includeDeleted {
            return try context.fetch(FetchDescriptor(sortBy: sort))
        }
        return try context.fetch(FetchDescriptor(
            predicate: #Predicate { $0.deleteAt == nil || $0.deleteAt == 0 },
            sortBy: sort
        ))
    }

    /// Returns immutable channel values that can safely be retained or sent to another actor.
    public func cachedChannelSnapshots(
        teamID: String? = nil,
        includeDeleted: Bool = false
    ) throws -> [MattermostCachedChannelSnapshot] {
        try cachedChannels(teamID: teamID, includeDeleted: includeDeleted).map(MattermostCachedChannelSnapshot.init)
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
        includeDeleted: Bool = false
    ) throws -> [MattermostCachedPost] {
        var descriptor: FetchDescriptor<MattermostCachedPost>
        if includeDeleted {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.channelId == channelID },
                sortBy: [SortDescriptor(\MattermostCachedPost.createAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.channelId == channelID && $0.deleteAt == 0 },
                sortBy: [SortDescriptor(\MattermostCachedPost.createAt, order: .reverse)]
            )
        }
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try context.fetch(descriptor)
    }

    /// Returns immutable post values that can safely be retained or sent to another actor.
    public func cachedPostSnapshots(
        channelID: String,
        limit: Int? = nil,
        includeDeleted: Bool = false
    ) throws -> [MattermostCachedPostSnapshot] {
        try cachedPosts(channelID: channelID, limit: limit, includeDeleted: includeDeleted)
            .map(MattermostCachedPostSnapshot.init)
    }

    public func cachedThread(rootID: String, includeDeleted: Bool = false) throws -> [MattermostCachedPost] {
        let descriptor: FetchDescriptor<MattermostCachedPost>
        if includeDeleted {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.id == rootID || $0.rootId == rootID },
                sortBy: [SortDescriptor(\MattermostCachedPost.createAt)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate {
                    ($0.id == rootID || $0.rootId == rootID) && $0.deleteAt == 0
                },
                sortBy: [SortDescriptor(\MattermostCachedPost.createAt)]
            )
        }
        return try context.fetch(descriptor)
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
        includeDeleted: Bool = false
    ) throws -> [MattermostCachedPost] {
        switch target {
        case .channel(let channelID):
            return try cachedPosts(channelID: channelID, limit: limit, includeDeleted: includeDeleted)
        case .thread(let rootPostID):
            var descriptor: FetchDescriptor<MattermostCachedPost>
            if includeDeleted {
                descriptor = FetchDescriptor(
                    predicate: #Predicate { $0.id == rootPostID || $0.rootId == rootPostID },
                    sortBy: [SortDescriptor(\MattermostCachedPost.createAt)]
                )
            } else {
                descriptor = FetchDescriptor(
                    predicate: #Predicate {
                        ($0.id == rootPostID || $0.rootId == rootPostID) && $0.deleteAt == 0
                    },
                    sortBy: [SortDescriptor(\MattermostCachedPost.createAt)]
                )
            }
            if let limit {
                descriptor.fetchLimit = limit
            }
            return try context.fetch(descriptor)
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
        let posts = try cachedPosts(channelID: channelID, includeDeleted: true)
        let prunedPosts = Array(posts.dropFirst(keepCount))
        try deleteCachedPostContent(postIDs: prunedPosts.map(\.id))
        for post in prunedPosts {
            context.delete(post)
        }
    }

    public func deleteChannelContent(channelID: String) throws {
        let posts = try cachedPosts(channelID: channelID, includeDeleted: true)

        for post in posts {
            context.delete(post)
        }
        for unread in try context.fetch(FetchDescriptor<MattermostCachedChannelUnread>(
            predicate: #Predicate { $0.channelId == channelID }
        )) {
            context.delete(unread)
        }
        try deleteCachedPostContent(postIDs: posts.map(\.id))
    }

    private func deleteCachedPostContent(postIDs: [String]) throws {
        guard !postIDs.isEmpty else {
            return
        }
        for reaction in try fetchInBatches(ids: postIDs, descriptor: { chunkIDs in
            FetchDescriptor<MattermostCachedReaction>(predicate: #Predicate { chunkIDs.contains($0.postId) })
        }) {
            context.delete(reaction)
        }
        for file in try fetchInBatches(ids: postIDs, descriptor: { chunkIDs in
            FetchDescriptor<MattermostCachedFile>(predicate: #Predicate { file in
                if let pid = file.postId { return chunkIDs.contains(pid) } else { return false }
            })
        }) {
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
             .multipleChannelsViewed,
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
