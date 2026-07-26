import Foundation

/// Options for SDK-level cache hydration and incremental sync.
public struct MattermostSyncOptions: Equatable, Sendable {
    /// Number of posts requested per channel-post page.
    public var postPageSize: Int

    /// Maximum number of channel-post pages to fetch in one sync pass.
    public var maxPostPages: Int

    /// Whether to cache all channel user profiles for the selected post channel.
    public var includeChannelUsers: Bool

    /// Whether to cache sidebar categories for the resolved team.
    public var includeSidebarCategories: Bool

    /// Whether to refresh unread counts for every joined channel in the resolved team.
    public var refreshUnreadForAllJoinedChannels: Bool

    public init(
        postPageSize: Int = 60,
        maxPostPages: Int = 3,
        includeChannelUsers: Bool = true,
        includeSidebarCategories: Bool = true,
        refreshUnreadForAllJoinedChannels: Bool = true
    ) {
        self.postPageSize = max(1, postPageSize)
        self.maxPostPages = max(1, maxPostPages)
        self.includeChannelUsers = includeChannelUsers
        self.includeSidebarCategories = includeSidebarCategories
        self.refreshUnreadForAllJoinedChannels = refreshUnreadForAllJoinedChannels
    }
}

/// Summary of posts fetched for a channel during a sync pass.
public struct MattermostChannelPostSyncResult: Equatable, Sendable {
    public let channelID: String
    public let posts: [MattermostPost]
    public let pageCount: Int
    public let cursorLastSyncAt: Int64
    public let cursorLastItemID: String?

    public init(
        channelID: String,
        posts: [MattermostPost],
        pageCount: Int,
        cursorLastSyncAt: Int64,
        cursorLastItemID: String?
    ) {
        self.channelID = channelID
        self.posts = posts
        self.pageCount = pageCount
        self.cursorLastSyncAt = cursorLastSyncAt
        self.cursorLastItemID = cursorLastItemID
    }
}

/// Summary of a workspace sync pass.
public struct MattermostSyncResult: Equatable, Sendable {
    public let user: MattermostUser
    public let teams: [MattermostTeam]
    public let teamID: String?
    public let channels: [MattermostChannel]
    public let postSync: MattermostChannelPostSyncResult?
    public let syncedTeamsCount: Int
    public let syncedUsersCount: Int
    public let syncedMembersCount: Int
    public let syncedUnreadsCount: Int
    public let syncedCategoriesCount: Int
    public let cachedTeamsCount: Int
    public let cachedUsersCount: Int
    public let cachedChannelsCount: Int
    public let cachedMembersCount: Int
    public let cachedUnreadsCount: Int
    public let teamCursorLastSyncAt: Int64?

    public init(
        user: MattermostUser,
        teams: [MattermostTeam],
        teamID: String?,
        channels: [MattermostChannel],
        postSync: MattermostChannelPostSyncResult?,
        syncedTeamsCount: Int,
        syncedUsersCount: Int,
        syncedMembersCount: Int,
        syncedUnreadsCount: Int,
        syncedCategoriesCount: Int,
        cachedTeamsCount: Int,
        cachedUsersCount: Int,
        cachedChannelsCount: Int,
        cachedMembersCount: Int,
        cachedUnreadsCount: Int,
        teamCursorLastSyncAt: Int64?
    ) {
        self.user = user
        self.teams = teams
        self.teamID = teamID
        self.channels = channels
        self.postSync = postSync
        self.syncedTeamsCount = syncedTeamsCount
        self.syncedUsersCount = syncedUsersCount
        self.syncedMembersCount = syncedMembersCount
        self.syncedUnreadsCount = syncedUnreadsCount
        self.syncedCategoriesCount = syncedCategoriesCount
        self.cachedTeamsCount = cachedTeamsCount
        self.cachedUsersCount = cachedUsersCount
        self.cachedChannelsCount = cachedChannelsCount
        self.cachedMembersCount = cachedMembersCount
        self.cachedUnreadsCount = cachedUnreadsCount
        self.teamCursorLastSyncAt = teamCursorLastSyncAt
    }
}

/// High-level sync coordinator for keeping `MattermostStore` coherent with one server/account.
public struct MattermostSyncService: Sendable {
    private let client: MattermostClient

    public init(client: MattermostClient) {
        self.client = client
    }

    /// Hydrates the local store with joined teams, current user, status, joined channels, memberships,
    /// unread state, sidebar categories, all pages of channel users, and optionally a channel timeline.
    @MainActor
    public func sync(
        to store: MattermostStore,
        teamID requestedTeamID: String? = nil,
        teamName: String? = nil,
        channelID postChannelID: String? = nil,
        options: MattermostSyncOptions = MattermostSyncOptions()
    ) async throws -> MattermostSyncResult {
        let user = try await client.currentUser()
        let status = try await client.status(userID: user.id)
        let joinedTeamsResult = try await joinedTeams(userID: user.id, store: store)
        let joinedTeams = joinedTeamsResult.values

        try store.upsert(user: user)
        try store.upsert(status: status)
        if joinedTeamsResult.wasModified {
            try store.upsert(teams: joinedTeams)
        }

        let resolvedTeam = try await resolveTeamAndChannels(
            teamID: requestedTeamID,
            teamName: teamName,
            joinedTeams: joinedTeams,
            store: store
        )

        if let team = resolvedTeam.team {
            try store.upsert(team: team)
        }
        if resolvedTeam.channelsWereModified {
            if let teamID = resolvedTeam.teamID {
                try store.replaceJoinedChannels(resolvedTeam.channels, teamID: teamID)
            } else {
                // Across-team responses do not establish a deletion scope for direct/group channels.
                try store.upsert(channels: resolvedTeam.channels)
            }
        }

        let syncedTeamsCount = joinedTeams.count
        var syncedUsersCount = 1
        var syncedMembersCount = 0
        var syncedUnreadsCount = 0
        var syncedCategoriesCount = 0
        var postSync: MattermostChannelPostSyncResult?

        if let postChannelID {
            let member = try await client.channelMember(channelID: postChannelID)
            try store.upsert(member: member)
            syncedMembersCount += 1

            if options.includeChannelUsers {
                let users = try await allChannelUsers(channelID: postChannelID)
                try store.upsert(users: users)
                syncedUsersCount = users.count
            }

            postSync = try await client.syncChannelPosts(
                channelID: postChannelID,
                to: store,
                perPage: options.postPageSize,
                maxPages: options.maxPostPages
            )
        }

        if let teamID = resolvedTeam.teamID {
            let members = try await client.channelMembers(userID: user.id, teamID: teamID)
            try store.replaceChannelMembers(members, userID: user.id, teamID: teamID)
            syncedMembersCount = max(syncedMembersCount, members.count)

            if options.includeSidebarCategories {
                let categoriesResult = try await sidebarCategories(
                    userID: user.id,
                    teamID: teamID,
                    store: store
                )
                let categories = categoriesResult.values
                if categoriesResult.wasModified {
                    try store.replaceSidebarCategories(categories, userID: user.id, teamID: teamID)
                }
                syncedCategoriesCount = categories.count
            }
        }

        if options.refreshUnreadForAllJoinedChannels {
            syncedUnreadsCount = try await refreshJoinedChannelUnreads(
                channels: resolvedTeam.channels,
                userID: user.id,
                store: store
            )
            if let teamID = resolvedTeam.teamID {
                try store.reconcileChannelUnreads(
                    userID: user.id,
                    teamID: teamID,
                    channelIDs: resolvedTeam.channels.map(\.id)
                )
            }
        } else if let postChannelID {
            let unread = try await client.channelUnread(channelID: postChannelID, userID: user.id)
            try store.upsert(unread: unread, userID: user.id)
            syncedUnreadsCount = 1
        }

        let teamCursorLastSyncAt: Int64?
        if let teamID = resolvedTeam.teamID {
            let now = Int64(Date.now.timeIntervalSince1970 * 1000)
            try store.setSyncCursor(scope: "team:\(teamID)", lastSyncAt: now)
            teamCursorLastSyncAt = now
        } else {
            teamCursorLastSyncAt = nil
        }

        try store.save()

        return MattermostSyncResult(
            user: user,
            teams: joinedTeams,
            teamID: resolvedTeam.teamID,
            channels: resolvedTeam.channels,
            postSync: postSync,
            syncedTeamsCount: syncedTeamsCount,
            syncedUsersCount: syncedUsersCount,
            syncedMembersCount: syncedMembersCount,
            syncedUnreadsCount: syncedUnreadsCount,
            syncedCategoriesCount: syncedCategoriesCount,
            cachedTeamsCount: try store.cachedTeamsCount(),
            cachedUsersCount: try store.cachedUsersCount(),
            cachedChannelsCount: try store.cachedChannelsCount(),
            cachedMembersCount: try store.cachedChannelMembersCount(),
            cachedUnreadsCount: try store.cachedChannelUnreadsCount(),
            teamCursorLastSyncAt: teamCursorLastSyncAt
        )
    }

    private func allChannelUsers(channelID: String) async throws -> [MattermostUser] {
        let pageSize = 60
        var page = 0
        var users: [MattermostUser] = []

        while true {
            let pageUsers = try await client.users(
                channelID: channelID,
                page: page,
                perPage: pageSize
            )
            users.append(contentsOf: pageUsers)

            guard pageUsers.count >= pageSize else {
                return users
            }
            page += 1
        }
    }

    @MainActor
    private func resolveTeamAndChannels(
        teamID: String?,
        teamName: String?,
        joinedTeams: [MattermostTeam],
        store: MattermostStore
    ) async throws -> (
        team: MattermostTeam?,
        teamID: String?,
        channels: [MattermostChannel],
        channelsWereModified: Bool
    ) {
        if let teamID, !teamID.isEmpty {
            let team: MattermostTeam
            if let joinedTeam = joinedTeams.first(where: { $0.id == teamID }) {
                team = joinedTeam
            } else {
                team = try await client.team(id: teamID)
            }
            let channels = try await joinedChannels(teamID: teamID, store: store)
            return (team, teamID, channels.values, channels.wasModified)
        }

        if let teamName, !teamName.isEmpty {
            let team: MattermostTeam
            if let joinedTeam = joinedTeams.first(where: { $0.name == teamName }) {
                team = joinedTeam
            } else {
                team = try await client.team(named: teamName)
            }
            let channels = try await joinedChannels(teamID: team.id, store: store)
            return (team, team.id, channels.values, channels.wasModified)
        }

        let channelsResult = try await joinedChannelsAcrossTeams(store: store)
        let inferredTeamID = channelsResult.values.lazy.compactMap(\.teamID).first { !$0.isEmpty }
        let inferredTeam = inferredTeamID.flatMap { teamID in
            joinedTeams.first { $0.id == teamID }
        }
        return (
            inferredTeam,
            inferredTeamID,
            channelsResult.values,
            channelsResult.wasModified
        )
    }

    @MainActor
    private func joinedTeams(
        userID: String,
        store: MattermostStore
    ) async throws -> ConditionalList<MattermostTeam> {
        let endpoint = "/users/\(userID)/teams"
        let scope = Self.etagScope(endpoint: endpoint)
        let cachedETag = try store.cachedETag(scope: scope)
        let response: MattermostConditionalResponse<[MattermostTeam]> = try await client.httpClient
            .conditionalGet(endpoint, etag: cachedETag?.value)

        switch response {
        case .modified(let teams, let etag):
            try updateETag(etag, scope: scope, itemIDs: teams.map(\.id), store: store)
            return ConditionalList(values: teams, wasModified: true)
        case .notModified:
            return ConditionalList(
                values: Self.orderedModels(
                    ids: cachedETag?.itemIDs ?? [],
                    models: try store.cachedTeams().map(\.mattermostModel)
                ),
                wasModified: false
            )
        }
    }

    @MainActor
    private func joinedChannels(
        teamID: String,
        store: MattermostStore
    ) async throws -> ConditionalList<MattermostChannel> {
        let endpoint = "/users/me/teams/\(teamID)/channels"
        return try await joinedChannels(endpoint: endpoint, store: store)
    }

    @MainActor
    private func joinedChannelsAcrossTeams(
        store: MattermostStore
    ) async throws -> ConditionalList<MattermostChannel> {
        try await joinedChannels(endpoint: "/users/me/channels", store: store)
    }

    @MainActor
    private func joinedChannels(
        endpoint: String,
        store: MattermostStore
    ) async throws -> ConditionalList<MattermostChannel> {
        let scope = Self.etagScope(endpoint: endpoint)
        let cachedETag = try store.cachedETag(scope: scope)
        let response: MattermostConditionalResponse<[MattermostChannel]> = try await client.httpClient
            .conditionalGet(endpoint, etag: cachedETag?.value)

        switch response {
        case .modified(let channels, let etag):
            try updateETag(etag, scope: scope, itemIDs: channels.map(\.id), store: store)
            return ConditionalList(values: channels, wasModified: true)
        case .notModified:
            return ConditionalList(
                values: Self.orderedModels(
                    ids: cachedETag?.itemIDs ?? [],
                    models: try store.cachedChannels(includeDeleted: true).map(\.mattermostModel)
                ),
                wasModified: false
            )
        }
    }

    @MainActor
    private func sidebarCategories(
        userID: String,
        teamID: String,
        store: MattermostStore
    ) async throws -> ConditionalList<MattermostSidebarCategory> {
        let endpoint = "/users/me/teams/\(teamID)/channels/categories"
        let scope = Self.etagScope(endpoint: endpoint)
        let cachedETag = try store.cachedETag(scope: scope)
        let response: MattermostConditionalResponse<MattermostSidebarCategoryList> = try await client.httpClient
            .conditionalGet(endpoint, etag: cachedETag?.value)

        switch response {
        case .modified(let list, let etag):
            let categories = list.orderedCategories
            try updateETag(etag, scope: scope, itemIDs: categories.map(\.id), store: store)
            return ConditionalList(values: categories, wasModified: true)
        case .notModified:
            return ConditionalList(
                values: Self.orderedModels(
                    ids: cachedETag?.itemIDs ?? [],
                    models: try store.cachedSidebarCategories(teamID: teamID)
                        .filter { $0.userId == nil || $0.userId == userID }
                        .map(\.mattermostModel)
                ),
                wasModified: false
            )
        }
    }

    @MainActor
    private func updateETag(
        _ etag: String?,
        scope: String,
        itemIDs: [String],
        store: MattermostStore
    ) throws {
        if let etag {
            try store.setETag(scope: scope, value: etag, itemIDs: itemIDs)
        } else {
            try store.removeETag(scope: scope)
        }
    }

    private static func etagScope(
        endpoint: String,
        queryItems: [URLQueryItem] = []
    ) -> String {
        let query = queryItems
            .sorted {
                if $0.name != $1.name {
                    return $0.name < $1.name
                }
                return ($0.value ?? "") < ($1.value ?? "")
            }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        return query.isEmpty ? "GET \(endpoint)" : "GET \(endpoint)?\(query)"
    }

    private static func orderedModels<Model: Identifiable>(
        ids: [String],
        models: [Model]
    ) -> [Model] where Model.ID == String {
        let modelsByID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { modelsByID[$0] }
    }

    // Keep the per-channel HTTP fan-out instead of deriving unread state locally.
    // `MattermostChannelMember.msgCount` is the user's read position, while
    // `MattermostChannelUnread.msgCount` is the server-computed unread count.
    // The channels fetched in this sync pass do not carry total message counts,
    // so computing unread counts locally would produce wrong badges.
    @MainActor
    private func refreshJoinedChannelUnreads(
        channels: [MattermostChannel],
        userID: String,
        store: MattermostStore,
        width: Int = 4
    ) async throws -> Int {
        let unreads = try await mattermostBoundedConcurrentMap(channels, width: width) { channel in
            let unread = try await client.channelUnread(channelID: channel.id, userID: userID)
            try store.upsert(unread: unread, userID: userID)
            return unread
        }
        return unreads.count
    }
}

private struct ConditionalList<Value: Sendable>: Sendable {
    let values: [Value]
    let wasModified: Bool
}

private extension MattermostCachedTeam {
    var mattermostModel: MattermostTeam {
        MattermostTeam(
            id: id,
            name: name,
            displayName: displayName,
            description: descriptionText,
            type: type
        )
    }
}

private extension MattermostCachedChannel {
    var mattermostModel: MattermostChannel {
        MattermostChannel(
            id: id,
            createAt: createAt,
            updateAt: updateAt,
            teamID: teamId,
            name: name,
            displayName: displayName,
            type: MattermostChannelType(rawValue: type),
            header: header,
            purpose: purpose,
            deleteAt: deleteAt,
            totalMsgCount: totalMsgCount,
            totalMsgCountRoot: totalMsgCountRoot,
            lastPostAt: lastPostAt,
            lastRootPostAt: lastRootPostAt
        )
    }
}

private extension MattermostCachedSidebarCategory {
    var mattermostModel: MattermostSidebarCategory {
        MattermostSidebarCategory(
            id: id,
            userID: userId,
            teamID: teamId,
            displayName: displayName,
            type: MattermostSidebarCategoryType(rawValue: type),
            sortOrder: sortOrder,
            channelIDs: channelIds,
            sorting: sorting.map(MattermostSidebarCategorySorting.init(rawValue:)),
            muted: muted,
            collapsed: collapsed
        )
    }
}

public extension MattermostClient {
    /// Creates a high-level sync coordinator for this client.
    func syncService() -> MattermostSyncService {
        MattermostSyncService(client: self)
    }
}
