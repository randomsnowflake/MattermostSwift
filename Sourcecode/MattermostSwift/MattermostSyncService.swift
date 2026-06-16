import Foundation

/// Options for SDK-level cache hydration and incremental sync.
public struct MattermostSyncOptions: Equatable, Sendable {
    /// Number of posts requested per channel-post page.
    public var postPageSize: Int

    /// Maximum number of channel-post pages to fetch in one sync pass.
    public var maxPostPages: Int

    /// Whether to cache channel user profiles for the selected post channel.
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
    /// unread state, sidebar categories, and optionally a channel timeline.
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
        let joinedTeams = try await client.teams(userID: user.id)
        let resolvedTeam = try await resolveTeamAndChannels(
            teamID: requestedTeamID,
            teamName: teamName,
            joinedTeams: joinedTeams
        )

        try store.upsert(user: user)
        try store.upsert(status: status)
        try store.upsert(teams: joinedTeams)
        if let team = resolvedTeam.team {
            try store.upsert(team: team)
        }
        try store.upsert(channels: resolvedTeam.channels)

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
                let users = try await client.users(channelID: postChannelID, perPage: 60)
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
            let members = try await client.channelMembersForUser(userID: user.id, teamID: teamID)
            try store.upsert(members: members)
            syncedMembersCount = max(syncedMembersCount, members.count)

            if options.includeSidebarCategories {
                let categories = try await client.sidebarCategories(teamID: teamID)
                try store.upsert(sidebarCategories: categories)
                syncedCategoriesCount = categories.count
            }
        }

        if options.refreshUnreadForAllJoinedChannels {
            for channel in resolvedTeam.channels {
                let unread = try await client.channelUnread(userID: user.id, channelID: channel.id)
                try store.upsert(unread: unread, userID: user.id)
                syncedUnreadsCount += 1
            }
        } else if let postChannelID {
            let unread = try await client.channelUnread(userID: user.id, channelID: postChannelID)
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
            cachedTeamsCount: try store.cachedTeams().count,
            cachedUsersCount: try store.cachedUsers().count,
            cachedChannelsCount: try store.cachedChannels().count,
            cachedMembersCount: try store.cachedChannelMembers().count,
            cachedUnreadsCount: try store.cachedChannelUnreads().count,
            teamCursorLastSyncAt: teamCursorLastSyncAt
        )
    }

    private func resolveTeamAndChannels(
        teamID: String?,
        teamName: String?,
        joinedTeams: [MattermostTeam]
    ) async throws -> (team: MattermostTeam?, teamID: String?, channels: [MattermostChannel]) {
        if let teamID, !teamID.isEmpty {
            let team: MattermostTeam
            if let joinedTeam = joinedTeams.first(where: { $0.id == teamID }) {
                team = joinedTeam
            } else {
                team = try await client.team(id: teamID)
            }
            return (team, teamID, try await client.joinedChannels(teamID: teamID))
        }

        if let teamName, !teamName.isEmpty {
            let team: MattermostTeam
            if let joinedTeam = joinedTeams.first(where: { $0.name == teamName }) {
                team = joinedTeam
            } else {
                team = try await client.team(named: teamName)
            }
            return (team, team.id, try await client.joinedChannels(teamID: team.id))
        }

        let channels = try await client.joinedChannelsAcrossTeams()
        let inferredTeamID = channels.compactMap(\.teamId).first { !$0.isEmpty }
        let inferredTeam = inferredTeamID.flatMap { teamID in
            joinedTeams.first { $0.id == teamID }
        }
        return (inferredTeam, inferredTeamID, channels)
    }
}

public extension MattermostClient {
    /// Creates a high-level sync coordinator for this client.
    func syncService() -> MattermostSyncService {
        MattermostSyncService(client: self)
    }
}
