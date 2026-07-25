import Foundation
import SwiftData

/// SwiftData-backed cache for Mattermost objects used by app targets and the CLI.
///
/// Every member is main-actor isolated. Keep managed cache models on that actor; use the
/// immutable snapshot readers when values need to cross an actor boundary.
///
/// Mutation methods stage changes in ``context`` but don't persist them automatically. Call
/// ``save()`` after a group of direct mutations. Higher-level sync APIs that document a save
/// boundary, such as ``MattermostSyncService/sync(to:teamID:teamName:channelID:options:)``,
/// save before returning.
///
/// `upsert` methods are additive and never infer that an omitted object was deleted.
/// `replace` and `reconcile` methods remove rows only inside the complete, authoritative scope
/// named by their parameters. Readers with `includeDeleted: false` hide channel and post
/// tombstones; passing `true` exposes them for reconciliation and diagnostics.
///
/// Host apps own retention policy. Use pruning helpers such as
/// `prunePosts(channelID:keepCount:)` and `deleteChannelContent(channelID:)` during
/// background maintenance or channel lifecycle events to keep long-lived stores bounded.
@MainActor
public final class MattermostStore {
    private static let batchedFetchIDLimit = 500

    /// The versioned SwiftData schema used by MattermostSwift cache containers.
    public static var schema: Schema {
        Schema(versionedSchema: MattermostCacheSchemaV1.self)
    }

    /// The model container that owns this store's cache.
    public let container: ModelContainer
    /// The container's main context, used for all reads and mutations.
    public let context: ModelContext

    /// Creates a store around an existing container and its main context.
    /// - Parameter container: A container compatible with ``schema``.
    public init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    /// Creates a versioned Mattermost cache container.
    /// - Parameters:
    ///   - inMemory: When `true` and `url` is `nil`, keeps the store only in memory.
    ///   - url: An explicit persistent-store URL. When supplied, this takes precedence over
    ///     `inMemory`.
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

    /// Persists all staged inserts, updates, and deletions in ``context``.
    ///
    /// Direct mutation methods don't call this method. Group related mutations and call `save()`
    /// once at the desired transaction boundary.
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

    /// Inserts a user or updates the cached row with the same Mattermost user ID.
    ///
    /// The change remains staged until ``save()``.
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

    /// Inserts or updates users by Mattermost user ID without removing omitted users.
    ///
    /// The changes remain staged until ``save()``.
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

    /// Inserts or updates one user's presence status.
    ///
    /// The change remains staged until ``save()``.
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

    /// Inserts or updates presence statuses by user ID without removing omitted statuses.
    ///
    /// The changes remain staged until ``save()``.
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

    /// Inserts a team or updates the cached row with the same team ID.
    ///
    /// The change remains staged until ``save()``.
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

    /// Inserts or updates teams by ID without removing omitted teams.
    ///
    /// The changes remain staged until ``save()``.
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

    /// Inserts or timestamp-merges a channel by ID, including an existing tombstone.
    ///
    /// Older server payloads don't overwrite newer channel state. The change remains staged
    /// until ``save()``.
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

    /// Inserts or timestamp-merges channels by ID without removing omitted channels.
    ///
    /// Use ``replaceJoinedChannels(_:teamID:)`` only when the input is a complete,
    /// server-authoritative joined-channel response for one team. Changes remain staged until
    /// ``save()``.
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
    ///
    /// Rows absent from this proven team scope are permanently removed together with their
    /// cached posts, reactions, files, unreads, and memberships. An empty array therefore clears
    /// every cached channel in `teamID`. Don't pass a partial or paginated response.
    /// The changes remain staged until ``save()``.
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

    /// Marks an existing cached channel as a deletion tombstone.
    ///
    /// The method doesn't create a row when `id` is unknown and doesn't delete related content.
    /// The greatest observed deletion timestamp wins. Call ``deleteChannelContent(channelID:)``
    /// separately when related cached content should be removed, then call ``save()``.
    public func markChannelDeleted(id: String, at deletedAt: Int64 = Int64(Date.now.timeIntervalSince1970 * 1000)) throws {
        if let cached = try cachedChannel(id: id, includeDeleted: true) {
            cached.markDeleted(at: deletedAt)
        }
    }

    /// Marks an existing cached post as a deletion tombstone.
    ///
    /// The method doesn't create a row when `id` is unknown. The greatest observed deletion
    /// timestamp wins, and the change remains staged until ``save()``.
    public func markPostDeleted(id: String, at deletedAt: Int64 = Int64(Date.now.timeIntervalSince1970 * 1000)) throws {
        if let cached = try cachedPost(id: id) {
            cached.markDeleted(at: deletedAt)
        }
    }

    /// Inserts or updates a channel membership using its channel/user composite identity.
    ///
    /// The change remains staged until ``save()``.
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

    /// Inserts or updates channel memberships without removing omitted memberships.
    ///
    /// The changes remain staged until ``save()``.
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

    /// Replaces one user's memberships for the cached channels belonging to one team.
    ///
    /// The caller must pass a complete server response for that user/team. Memberships omitted
    /// from that authoritative scope are permanently removed; an empty array removes all of the
    /// user's memberships for cached channels in `teamID`. Other users and teams are unaffected.
    /// The changes remain staged until ``save()``.
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

    /// Inserts or updates unread counts for a channel/user composite identity.
    ///
    /// The change remains staged until ``save()``.
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

    /// Inserts or timestamp-merges one post, preserving tolerant props and metadata JSON.
    ///
    /// Older server payloads don't overwrite newer edits or deletion tombstones. The change
    /// remains staged until ``save()``.
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

    /// Inserts or timestamp-merges every ordered post in a post-list response.
    ///
    /// This method doesn't remove posts omitted from the response. The changes remain staged
    /// until ``save()``.
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

    /// Inserts or timestamp-merges one per-user thread state and its root post and participants.
    ///
    /// The change remains staged until ``save()``.
    @discardableResult
    public func upsert(thread: MattermostThreadResponse, userID: String, teamID: String) throws -> MattermostCachedThread {
        if let post = thread.post {
            try upsert(post: post)
        }
        try upsert(users: thread.participants)

        return try upsertThreadState(thread, userID: userID, teamID: teamID)
    }

    /// Inserts or timestamp-merges a thread inbox page, its root posts, and participants.
    ///
    /// This method doesn't remove thread states omitted from the page. The changes remain staged
    /// until ``save()``.
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

    /// Inserts or updates a reaction using its post/user/emoji composite identity.
    ///
    /// The change remains staged until ``save()``.
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

    /// Inserts or updates reactions without removing omitted reactions.
    ///
    /// The changes remain staged until ``save()``.
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

    /// Inserts a file record or updates the cached row with the same file ID.
    ///
    /// The change remains staged until ``save()``.
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

    /// Inserts or updates file records without removing omitted files.
    ///
    /// The changes remain staged until ``save()``.
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

    /// Inserts a sidebar category or updates the cached row with the same category ID.
    ///
    /// The change remains staged until ``save()``.
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

    /// Inserts or updates sidebar categories without removing omitted categories.
    ///
    /// The changes remain staged until ``save()``.
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
    ///
    /// Categories omitted from the complete response are permanently removed within the
    /// user/team scope. An empty array clears that scope. Other users and teams are unaffected.
    /// The changes remain staged until ``save()``.
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

    /// Reconciles one user's unread rows against an authoritative channel set for a team.
    ///
    /// Rows whose channel IDs aren't present in `channelIDs` are permanently removed within the
    /// user/team scope. An empty `channelIDs` array clears that scope; other users and teams are
    /// unaffected. This method doesn't upsert unread values. The deletions remain staged until
    /// ``save()``.
    public func reconcileChannelUnreads(userID: String, teamID: String, channelIDs: [String]) throws {
        let retained = Set(channelIDs)
        let existing = try context.fetch(FetchDescriptor<MattermostCachedChannelUnread>(
            predicate: #Predicate { $0.userId == userID && $0.teamId == teamID }
        ))
        for unread in existing where !retained.contains(unread.channelId) {
            context.delete(unread)
        }
    }

    /// Returns the cached user with `id`, or `nil` when no row exists.
    public func cachedUser(id: String) throws -> MattermostCachedUser? {
        var descriptor = FetchDescriptor<MattermostCachedUser>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns the cached presence status for a user, or `nil` when no row exists.
    public func cachedUserStatus(userID: String) throws -> MattermostCachedUserStatus? {
        var descriptor = FetchDescriptor<MattermostCachedUserStatus>(
            predicate: #Predicate { $0.userId == userID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns all cached users sorted by username.
    ///
    /// Returned SwiftData models remain bound to ``context`` and the main actor.
    public func cachedUsers() throws -> [MattermostCachedUser] {
        try context.fetch(
            FetchDescriptor(sortBy: [SortDescriptor(\MattermostCachedUser.username)])
        )
    }

    /// Returns immutable user values that can safely be retained or sent to another actor.
    public func cachedUserSnapshots() throws -> [MattermostCachedUserSnapshot] {
        try cachedUsers().map(MattermostCachedUserSnapshot.init)
    }

    /// Returns the number of cached user rows.
    public func cachedUsersCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedUser>())
    }

    /// Returns the cached team with `id`, or `nil` when no row exists.
    public func cachedTeam(id: String) throws -> MattermostCachedTeam? {
        var descriptor = FetchDescriptor<MattermostCachedTeam>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns all cached teams sorted by display name.
    public func cachedTeams() throws -> [MattermostCachedTeam] {
        try context.fetch(
            FetchDescriptor(sortBy: [SortDescriptor(\MattermostCachedTeam.displayName)])
        )
    }

    /// Returns the number of cached team rows.
    public func cachedTeamsCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedTeam>())
    }

    /// Returns a cached channel by ID.
    /// - Parameter includeDeleted: When `true`, also returns a channel whose `deleteAt` marks it
    ///   as deleted or archived. The default hides such tombstones.
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

    /// Returns cached channels sorted by display name.
    /// - Parameters:
    ///   - teamID: When supplied, limits results to one team.
    ///   - includeDeleted: When `true`, includes channels whose `deleteAt` marks them deleted or
    ///     archived. The default hides those tombstones.
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
    ///
    /// `includeDeleted` has the same tombstone behavior as
    /// ``cachedChannels(teamID:includeDeleted:)``.
    public func cachedChannelSnapshots(
        teamID: String? = nil,
        includeDeleted: Bool = false
    ) throws -> [MattermostCachedChannelSnapshot] {
        try cachedChannels(teamID: teamID, includeDeleted: includeDeleted).map(MattermostCachedChannelSnapshot.init)
    }

    /// Returns the number of cached channel rows, including deletion tombstones.
    public func cachedChannelsCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedChannel>())
    }

    /// Returns the cached membership for a channel/user pair, or `nil` when absent.
    public func cachedChannelMember(channelID: String, userID: String) throws -> MattermostCachedChannelMember? {
        try cachedChannelMember(id: MattermostCachedChannelMember.cacheID(channelID: channelID, userID: userID))
    }

    /// Returns a cached membership by its composite cache ID.
    ///
    /// Build the ID with ``MattermostCachedChannelMember/cacheID(channelID:userID:)``.
    public func cachedChannelMember(id: String) throws -> MattermostCachedChannelMember? {
        var descriptor = FetchDescriptor<MattermostCachedChannelMember>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns cached memberships sorted by channel ID, optionally filtered to one user.
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

    /// Returns the number of cached membership rows.
    public func cachedChannelMembersCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedChannelMember>())
    }

    /// Returns cached unread counts for a channel/user pair, or `nil` when absent.
    public func cachedChannelUnread(channelID: String, userID: String) throws -> MattermostCachedChannelUnread? {
        try cachedChannelUnread(id: MattermostCachedChannelUnread.cacheID(channelID: channelID, userID: userID))
    }

    /// Returns cached unread counts by their composite cache ID.
    ///
    /// Build the ID with ``MattermostCachedChannelUnread/cacheID(channelID:userID:)``.
    public func cachedChannelUnread(id: String) throws -> MattermostCachedChannelUnread? {
        var descriptor = FetchDescriptor<MattermostCachedChannelUnread>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns cached unread rows sorted by channel ID, optionally filtered to one user.
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

    /// Returns the number of cached unread rows.
    public func cachedChannelUnreadsCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<MattermostCachedChannelUnread>())
    }

    /// Returns a cached post by ID, including a deletion tombstone.
    ///
    /// Inspect ``MattermostCachedPost/isDeleted`` or use a scoped reader with
    /// `includeDeleted: false` when tombstones should be hidden.
    public func cachedPost(id: String) throws -> MattermostCachedPost? {
        var descriptor = FetchDescriptor<MattermostCachedPost>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns cached channel posts in reverse creation order.
    /// - Parameters:
    ///   - channelID: The channel whose posts to return.
    ///   - limit: An optional maximum number of rows.
    ///   - includeDeleted: When `true`, includes post tombstones (`deleteAt > 0`). The default
    ///     returns only visible posts.
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
    ///
    /// `includeDeleted` has the same tombstone behavior as
    /// ``cachedPosts(channelID:limit:includeDeleted:)``.
    public func cachedPostSnapshots(
        channelID: String,
        limit: Int? = nil,
        includeDeleted: Bool = false
    ) throws -> [MattermostCachedPostSnapshot] {
        try cachedPosts(channelID: channelID, limit: limit, includeDeleted: includeDeleted)
            .map(MattermostCachedPostSnapshot.init)
    }

    /// Returns a root post and its replies in ascending creation order.
    /// - Parameter includeDeleted: When `true`, includes deleted root/reply tombstones. The
    ///   default returns only visible posts.
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

    /// Returns per-user thread inbox state for a root/user/team identity.
    public func cachedThreadState(rootID: String, userID: String, teamID: String) throws -> MattermostCachedThread? {
        try cachedThreadState(id: MattermostCachedThread.cacheID(rootID: rootID, userID: userID, teamID: teamID))
    }

    /// Returns per-user thread inbox state by its composite cache ID.
    ///
    /// Build the ID with ``MattermostCachedThread/cacheID(rootID:userID:teamID:)``.
    public func cachedThreadState(id: String) throws -> MattermostCachedThread? {
        var descriptor = FetchDescriptor<MattermostCachedThread>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns thread inbox states in reverse last-reply order.
    /// - Parameters:
    ///   - userID: An optional user filter.
    ///   - teamID: An optional team filter.
    ///   - unreadOnly: When `true`, returns only rows with unread replies or mentions.
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

    /// Returns cached posts for a unified channel or thread timeline.
    /// - Parameters:
    ///   - target: The channel or root-post cache scope.
    ///   - limit: An optional maximum number of rows.
    ///   - includeDeleted: When `true`, includes deletion tombstones. The default returns visible
    ///     posts only.
    ///
    /// Channel results use reverse creation order; thread results use ascending creation order.
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

    /// Returns a cached reaction by its composite cache ID.
    public func cachedReaction(id: String) throws -> MattermostCachedReaction? {
        var descriptor = FetchDescriptor<MattermostCachedReaction>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns reactions for a post sorted by emoji name.
    public func cachedReactions(postID: String) throws -> [MattermostCachedReaction] {
        try context.fetch(
            FetchDescriptor(
                predicate: #Predicate { $0.postId == postID },
                sortBy: [SortDescriptor(\MattermostCachedReaction.emojiName)]
            )
        )
    }

    /// Permanently deletes a cached reaction by composite cache ID.
    ///
    /// Unknown IDs are ignored. The deletion remains staged until ``save()``.
    public func deleteCachedReaction(id: String) throws {
        if let reaction = try cachedReaction(id: id) {
            context.delete(reaction)
        }
    }

    /// Permanently removes older cached posts and their cached reactions and files.
    /// - Parameters:
    ///   - channelID: The channel whose cache to bound.
    ///   - keepCount: The number of newest rows to retain. Negative values are treated as zero.
    ///
    /// Tombstones count toward `keepCount`. The deletions remain staged until ``save()``.
    public func prunePosts(channelID: String, keepCount: Int = 200) throws {
        let keepCount = max(0, keepCount)
        let posts = try cachedPosts(channelID: channelID, includeDeleted: true)
        let prunedPosts = Array(posts.dropFirst(keepCount))
        try deleteCachedPostContent(postIDs: prunedPosts.map(\.id))
        for post in prunedPosts {
            context.delete(post)
        }
    }

    /// Permanently deletes a channel's cached posts, unreads, reactions, and files.
    ///
    /// This method preserves the channel row and channel memberships. It is not a tombstone
    /// operation. The deletions remain staged until ``save()``.
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

    /// Returns a cached file by Mattermost file ID, or `nil` when absent.
    public func cachedFile(id: String) throws -> MattermostCachedFile? {
        var descriptor = FetchDescriptor<MattermostCachedFile>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns cached files attached to a post, sorted by filename.
    public func cachedFiles(postID: String) throws -> [MattermostCachedFile] {
        try context.fetch(
            FetchDescriptor(
                predicate: #Predicate { $0.postId == postID },
                sortBy: [SortDescriptor(\MattermostCachedFile.name)]
            )
        )
    }

    /// Returns a cached sidebar category by ID, or `nil` when absent.
    public func cachedSidebarCategory(id: String) throws -> MattermostCachedSidebarCategory? {
        var descriptor = FetchDescriptor<MattermostCachedSidebarCategory>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns sidebar categories sorted by server sort order, optionally filtered to one team.
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

    /// Returns the incremental-sync cursor for an exact scope string, or `nil` when absent.
    public func cachedSyncCursor(scope: String) throws -> MattermostSyncCursor? {
        var descriptor = FetchDescriptor<MattermostSyncCursor>(
            predicate: #Predicate { $0.scope == scope }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Inserts or updates an incremental-sync cursor.
    ///
    /// Cursor timestamps use Mattermost server milliseconds. The change remains staged until
    /// ``save()``; don't advance a cursor until all associated payloads have been staged
    /// successfully.
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

    /// Decodes and stages cache changes for a supported WebSocket event.
    ///
    /// The returned typed event lets callers handle UI-specific behavior. Unsupported or
    /// invalidation-only events produce no direct cache mutation. Channel deletion removes
    /// related cached content while retaining a channel tombstone; post deletion retains a post
    /// tombstone when the post is known. All changes remain staged until ``save()``.
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
