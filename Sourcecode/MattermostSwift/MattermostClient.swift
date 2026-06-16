import Foundation

/// High-level entry point for a single Mattermost server/account.
public struct MattermostClient: Sendable {
    private let configuration: MattermostConfiguration
    private let httpClient: MattermostHTTPClient
    private let urlSession: URLSession

    /// Creates a client from an explicit configuration.
    public init(configuration: MattermostConfiguration, urlSession: URLSession = .mattermost) {
        self.configuration = configuration
        self.urlSession = urlSession
        httpClient = MattermostHTTPClient(configuration: configuration, urlSession: urlSession)
    }

    /// Creates a bearer-token authenticated client.
    public init(
        serverURL: URL,
        token: String,
        urlSession: URLSession = .mattermost,
        allowInsecureHTTP: Bool = false
    ) throws {
        let configuration = try MattermostConfiguration(
            serverURL: serverURL,
            authentication: .bearerToken(token),
            allowInsecureHTTP: allowInsecureHTTP
        )
        self.init(configuration: configuration, urlSession: urlSession)
    }

    /// Loads the authenticated user.
    public func currentUser() async throws -> MattermostUser {
        try await httpClient.get("/users/me")
    }

    /// Loads a user by id. Pass `"me"` for the authenticated user.
    public func user(id: String) async throws -> MattermostUser {
        try await httpClient.get("/users/\(id)")
    }

    /// Downloads a user's current profile image. Pass `"me"` for the authenticated user.
    public func userProfileImage(userID: String = "me") async throws -> Data {
        try await httpClient.data("/users/\(userID)/image")
    }

    /// Downloads the generated default profile image for a user id.
    public func defaultUserProfileImage(userID: String) async throws -> Data {
        try await httpClient.data("/users/\(userID)/image/default")
    }

    /// Loads users by id in one request.
    public func users(ids: [String]) async throws -> [MattermostUser] {
        try await httpClient.post("/users/ids", body: ids)
    }

    /// Loads users by username in one request.
    public func users(usernames: [String]) async throws -> [MattermostUser] {
        try await httpClient.post("/users/usernames", body: usernames)
    }

    /// Lists users who are members of a channel.
    public func users(channelID: String, page: Int = 0, perPage: Int = 60) async throws -> [MattermostUser] {
        try await httpClient.get(
            "/users",
            queryItems: [
                URLQueryItem(name: "in_channel", value: channelID),
                URLQueryItem(name: "page", value: String(Self.clampedPage(page))),
                URLQueryItem(name: "per_page", value: String(Self.clampedPerPage(perPage))),
            ]
        )
    }

    /// Searches users by username, full name, nickname, or email where the server permits it.
    public func searchUsers(
        term: String,
        teamID: String? = nil,
        notInTeamID: String? = nil,
        inChannelID: String? = nil,
        notInChannelID: String? = nil,
        allowInactive: Bool = false,
        withoutTeam: Bool = false,
        limit: Int = 20
    ) async throws -> [MattermostUser] {
        try await httpClient.post(
            "/users/search",
            body: MattermostUserSearchRequest(
                term: term,
                teamId: teamID,
                notInTeamId: notInTeamID,
                inChannelId: inChannelID,
                notInChannelId: notInChannelID,
                allowInactive: allowInactive,
                withoutTeam: withoutTeam,
                limit: limit
            )
        )
    }

    /// Autocompletes users for composer/member pickers.
    public func autocompleteUsers(
        name: String,
        teamID: String? = nil,
        channelID: String? = nil,
        limit: Int = 20
    ) async throws -> MattermostUserAutocomplete {
        var queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "limit", value: String(Self.clampedPerPage(limit))),
        ]
        if let teamID, !teamID.isEmpty {
            queryItems.append(URLQueryItem(name: "team_id", value: teamID))
        }
        if let channelID, !channelID.isEmpty {
            queryItems.append(URLQueryItem(name: "channel_id", value: channelID))
        }

        return try await httpClient.get("/users/autocomplete", queryItems: queryItems)
    }

    /// Loads IDs of users with any known relationship to the authenticated user.
    public func knownUserIDs() async throws -> [String] {
        try await httpClient.get("/users/known")
    }

    /// Loads a single user's presence status.
    public func status(userID: String) async throws -> MattermostUserStatus {
        try await httpClient.get("/users/\(userID)/status")
    }

    /// Loads presence statuses for multiple users.
    public func statuses(userIDs: [String]) async throws -> [MattermostUserStatus] {
        try await httpClient.post("/users/status/ids", body: userIDs)
    }

    /// Loads basic server health and capability metadata.
    public func serverInfo() async throws -> MattermostServerInfo {
        async let ping = serverPing()
        async let clientConfig = clientConfig()

        return try await MattermostServerInfo(
            ping: ping,
            clientConfig: clientConfig
        )
    }

    /// Checks Mattermost server health.
    public func serverPing() async throws -> MattermostServerPing {
        try await httpClient.get(
            "/system/ping",
            queryItems: [
                URLQueryItem(name: "get_server_status", value: "true"),
                URLQueryItem(name: "use_rest_semantics", value: "true"),
            ]
        )
    }

    /// Loads the subset of server configuration exposed to clients.
    public func clientConfig() async throws -> MattermostClientConfig {
        try await httpClient.get("/config/client")
    }

    /// Resolves a team by its URL-safe name.
    public func team(named name: String) async throws -> MattermostTeam {
        try await httpClient.get("/teams/name/\(name)")
    }

    /// Loads team metadata by id.
    public func team(id: String) async throws -> MattermostTeam {
        try await httpClient.get("/teams/\(id)")
    }

    /// Lists teams joined by a user. Pass `"me"` for the authenticated user.
    public func teams(userID: String = "me") async throws -> [MattermostTeam] {
        try await httpClient.get("/users/\(userID)/teams")
    }

    /// Lists team membership records for users on a team.
    public func teamMembers(
        teamID: String,
        page: Int = 0,
        perPage: Int = 60,
        sort: String? = nil,
        excludeDeletedUsers: Bool = false
    ) async throws -> [MattermostTeamMember] {
        var queryItems = [
            URLQueryItem(name: "page", value: String(Self.clampedPage(page))),
            URLQueryItem(name: "per_page", value: String(Self.clampedPerPage(perPage))),
        ]
        if let sort, !sort.isEmpty {
            queryItems.append(URLQueryItem(name: "sort", value: sort))
        }
        if excludeDeletedUsers {
            queryItems.append(URLQueryItem(name: "exclude_deleted_users", value: "true"))
        }

        return try await httpClient.get("/teams/\(teamID)/members", queryItems: queryItems)
    }

    /// Lists channels on a team for the authenticated user.
    public func joinedChannels(teamID: String) async throws -> [MattermostChannel] {
        try await httpClient.get("/users/me/teams/\(teamID)/channels")
    }

    /// Lists public channels on a team that the authenticated user may discover.
    public func publicChannels(teamID: String, page: Int = 0, perPage: Int = 60) async throws -> [MattermostChannel] {
        try await httpClient.get(
            "/teams/\(teamID)/channels",
            queryItems: [
                URLQueryItem(name: "page", value: String(Self.clampedPage(page))),
                URLQueryItem(name: "per_page", value: String(Self.clampedPerPage(perPage))),
            ]
        )
    }

    /// Loads channel metadata by id.
    public func channel(id: String) async throws -> MattermostChannel {
        try await httpClient.get("/channels/\(id)")
    }

    /// Resolves channel metadata by team id and URL-safe channel name.
    public func channel(teamID: String, name: String, includeDeleted: Bool = false) async throws -> MattermostChannel {
        try await httpClient.get(
            "/teams/\(teamID)/channels/name/\(name)",
            queryItems: [
                URLQueryItem(name: "include_deleted", value: String(includeDeleted)),
            ]
        )
    }

    /// Resolves channel metadata by team name and URL-safe channel name.
    public func channel(teamName: String, channelName: String, includeDeleted: Bool = false) async throws -> MattermostChannel {
        try await httpClient.get(
            "/teams/name/\(teamName)/channels/name/\(channelName)",
            queryItems: [
                URLQueryItem(name: "include_deleted", value: String(includeDeleted)),
            ]
        )
    }

    /// Loads aggregate statistics for one channel.
    public func channelStats(channelID: String) async throws -> MattermostChannelStats {
        try await httpClient.get("/channels/\(channelID)/stats")
    }

    /// Lists timezones represented by channel members.
    public func channelTimezones(channelID: String) async throws -> [String] {
        try await httpClient.get("/channels/\(channelID)/timezones")
    }

    /// Loads member counts for multiple channels keyed by channel id.
    public func channelMemberCounts(channelIDs: [String]) async throws -> [String: Int64] {
        try await httpClient.post("/channels/stats/member_count", body: channelIDs)
    }

    /// Searches channels by name, display name, or purpose.
    public func searchChannels(
        term: String,
        teamIDs: [String] = [],
        excludeDefaultChannels: Bool = false,
        includeDeleted: Bool = false,
        page: Int = 0,
        perPage: Int = 60,
        includeSearchByID: Bool = false
    ) async throws -> MattermostChannelSearchResults {
        try await httpClient.post(
            "/channels/search",
            body: MattermostChannelSearchRequest(
                term: term,
                teamIds: teamIDs,
                excludeDefaultChannels: excludeDefaultChannels,
                deleted: includeDeleted,
                page: page,
                perPage: perPage,
                includeSearchById: includeSearchByID
            )
        )
    }

    /// Searches public channels on a team. Servers may limit results to joined channels based on permissions.
    public func searchTeamChannels(teamID: String, term: String) async throws -> [MattermostChannel] {
        try await httpClient.post(
            "/teams/\(teamID)/channels/search",
            body: MattermostTeamChannelSearchRequest(term: term)
        )
    }

    /// Opens or creates a direct message channel between two users.
    public func createDirectChannel(userID: String, otherUserID: String) async throws -> MattermostChannel {
        try await httpClient.post("/channels/direct", body: [userID, otherUserID])
    }

    /// Opens or creates a group message channel. Mattermost may append the current user if omitted.
    public func createGroupChannel(userIDs: [String]) async throws -> MattermostChannel {
        try await httpClient.post("/channels/group", body: userIDs)
    }

    /// Searches group message channels by member username.
    public func searchGroupChannels(term: String) async throws -> [MattermostChannel] {
        try await httpClient.post("/channels/group/search", body: MattermostTeamChannelSearchRequest(term: term))
    }

    /// Creates a public or private channel on a team.
    public func createChannel(
        teamID: String,
        name: String,
        displayName: String,
        purpose: String? = nil,
        header: String? = nil,
        type: String = "O"
    ) async throws -> MattermostChannel {
        try await httpClient.post(
            "/channels",
            body: MattermostCreateChannelRequest(
                teamId: teamID,
                name: name,
                displayName: displayName,
                purpose: purpose,
                header: header,
                type: type
            )
        )
    }

    /// Partially updates mutable channel metadata.
    public func patchChannel(
        id: String,
        name: String? = nil,
        displayName: String? = nil,
        purpose: String? = nil,
        header: String? = nil
    ) async throws -> MattermostChannel {
        try await httpClient.put(
            "/channels/\(id)/patch",
            body: MattermostPatchChannelRequest(
                name: name,
                displayName: displayName,
                purpose: purpose,
                header: header
            )
        )
    }

    /// Archives a channel where the server and permissions allow it.
    @discardableResult
    public func deleteChannel(id: String) async throws -> MattermostStatusOK {
        try await httpClient.delete("/channels/\(id)")
    }

    /// Lists joined channels across all teams for the authenticated user.
    public func joinedChannelsAcrossTeams() async throws -> [MattermostChannel] {
        try await httpClient.get("/users/me/channels")
    }

    /// Loads the authenticated user's membership state for a channel.
    public func channelMember(channelID: String, userID: String = "me") async throws -> MattermostChannelMember {
        try await httpClient.get("/channels/\(channelID)/members/\(userID)")
    }

    /// Lists memberships for users in a channel.
    public func channelMembers(channelID: String, page: Int = 0, perPage: Int = 60) async throws -> [MattermostChannelMember] {
        try await httpClient.get(
            "/channels/\(channelID)/members",
            queryItems: [
                URLQueryItem(name: "page", value: String(Self.clampedPage(page))),
                URLQueryItem(name: "per_page", value: String(Self.clampedPerPage(perPage))),
            ]
        )
    }

    /// Loads specific channel memberships by user id.
    public func channelMembers(channelID: String, userIDs: [String]) async throws -> [MattermostChannelMember] {
        try await httpClient.post("/channels/\(channelID)/members/ids", body: userIDs)
    }

    /// Lists channel memberships for a user on a team.
    public func channelMembersForUser(userID: String = "me", teamID: String) async throws -> [MattermostChannelMember] {
        try await httpClient.get("/users/\(userID)/teams/\(teamID)/channels/members")
    }

    /// Adds one or more users to a public or private channel where permissions allow it.
    public func addChannelMembers(
        channelID: String,
        userIDs: [String],
        postRootID: String? = nil
    ) async throws -> MattermostChannelMember {
        try await httpClient.post(
            "/channels/\(channelID)/members",
            body: MattermostAddChannelMembersRequest(
                userIds: userIDs,
                postRootId: postRootID
            )
        )
    }

    /// Adds one user to a public or private channel where permissions allow it.
    public func addChannelMember(
        channelID: String,
        userID: String,
        postRootID: String? = nil
    ) async throws -> MattermostChannelMember {
        try await httpClient.post(
            "/channels/\(channelID)/members",
            body: MattermostAddChannelMembersRequest(
                userId: userID,
                postRootId: postRootID
            )
        )
    }

    /// Removes a user from a public or private channel where permissions allow it.
    @discardableResult
    public func removeChannelMember(
        channelID: String,
        userID: String
    ) async throws -> MattermostStatusOK {
        try await httpClient.delete("/channels/\(channelID)/members/\(userID)")
    }

    /// Loads unread message and mention counts for a user in a channel.
    public func channelUnread(userID: String = "me", channelID: String) async throws -> MattermostChannelUnread {
        try await httpClient.get("/users/\(userID)/channels/\(channelID)/unread")
    }

    /// Updates a user's channel notification properties.
    @discardableResult
    public func updateChannelNotifyProps(
        channelID: String,
        userID: String = "me",
        notifyProps: [String: String]
    ) async throws -> MattermostStatusOK {
        try await httpClient.put(
            "/channels/\(channelID)/members/\(userID)/notify_props",
            body: notifyProps
        )
    }

    /// Updates a user's channel notification properties with typed accessors.
    @discardableResult
    public func updateChannelNotifyProps(
        channelID: String,
        userID: String = "me",
        notifyProps: MattermostChannelNotifyProps
    ) async throws -> MattermostStatusOK {
        try await updateChannelNotifyProps(
            channelID: channelID,
            userID: userID,
            notifyProps: notifyProps.rawValues
        )
    }

    /// Marks a channel as viewed and clears related notification state.
    @discardableResult
    public func viewChannel(
        channelID: String,
        userID: String = "me",
        previousChannelID: String? = nil
    ) async throws -> MattermostChannelViewResponse {
        try await httpClient.post(
            "/channels/members/\(userID)/view",
            body: MattermostViewChannelRequest(
                channelId: channelID,
                prevChannelId: previousChannelID
            )
        )
    }

    /// Lists stored preferences for a user. Pass `"me"` for the authenticated user.
    public func preferences(userID: String = "me") async throws -> [MattermostPreference] {
        try await httpClient.get("/users/\(userID)/preferences")
    }

    /// Lists stored preferences in one category for a user.
    public func preferences(userID: String = "me", category: String) async throws -> [MattermostPreference] {
        try await httpClient.get("/users/\(userID)/preferences/\(category)")
    }

    /// Loads one stored preference by category and name for a user.
    public func preference(userID: String = "me", category: String, name: String) async throws -> MattermostPreference {
        try await httpClient.get("/users/\(userID)/preferences/\(category)/name/\(name)")
    }

    /// Saves one or more stored preferences for a user.
    @discardableResult
    public func savePreferences(
        _ preferences: [MattermostPreference],
        userID: String = "me"
    ) async throws -> MattermostStatusOK {
        try await httpClient.put("/users/\(userID)/preferences", body: preferences)
    }

    /// Deletes one or more stored preferences for a user.
    @discardableResult
    public func deletePreferences(
        _ preferences: [MattermostPreference],
        userID: String = "me"
    ) async throws -> MattermostStatusOK {
        try await httpClient.post("/users/\(userID)/preferences/delete", body: preferences)
    }

    /// Publishes a typing event to a channel or thread.
    @discardableResult
    public func sendTyping(
        channelID: String,
        parentID: String? = nil,
        userID: String = "me"
    ) async throws -> MattermostStatusOK {
        try await httpClient.post(
            "/users/\(userID)/typing",
            body: MattermostTypingRequest(
                channelId: channelID,
                parentId: parentID
            )
        )
    }

    /// Lists sidebar categories for the authenticated user on a team.
    public func sidebarCategoryList(teamID: String) async throws -> MattermostSidebarCategoryList {
        try await httpClient.get("/users/me/teams/\(teamID)/channels/categories")
    }

    /// Lists sidebar categories for the authenticated user on a team.
    public func sidebarCategories(teamID: String) async throws -> [MattermostSidebarCategory] {
        try await sidebarCategoryList(teamID: teamID).orderedCategories
    }

    /// Loads a single sidebar category for the authenticated user on a team.
    public func sidebarCategory(
        teamID: String,
        categoryID: String,
        userID: String = "me"
    ) async throws -> MattermostSidebarCategory {
        try await httpClient.get("/users/\(userID)/teams/\(teamID)/channels/categories/\(categoryID)")
    }

    /// Creates a custom sidebar category for the authenticated user on a team.
    public func createSidebarCategory(
        teamID: String,
        displayName: String,
        channelIDs: [String] = [],
        userID: String = "me"
    ) async throws -> MattermostSidebarCategory {
        let resolvedUserID = try await resolvedUserIDForRequestBody(userID)
        let category: MattermostSidebarCategory = try await httpClient.post(
            "/users/\(userID)/teams/\(teamID)/channels/categories",
            body: MattermostSidebarCategoryRequest(
                id: nil,
                userId: resolvedUserID,
                teamId: teamID,
                displayName: displayName,
                type: "custom",
                channelIds: channelIDs,
                sorting: "manual"
            )
        )
        return category
    }

    /// Updates a sidebar category's name and channel order.
    public func updateSidebarCategory(
        teamID: String,
        categoryID: String,
        displayName: String,
        channelIDs: [String],
        type: String = "custom",
        userID: String = "me"
    ) async throws -> MattermostSidebarCategory {
        let resolvedUserID = try await resolvedUserIDForRequestBody(userID)
        let category: MattermostSidebarCategory = try await httpClient.put(
            "/users/\(userID)/teams/\(teamID)/channels/categories/\(categoryID)",
            body: MattermostSidebarCategoryRequest(
                id: categoryID,
                userId: resolvedUserID,
                teamId: teamID,
                displayName: displayName,
                type: type,
                channelIds: channelIDs,
                sorting: "manual"
            )
        )
        return category
    }

    /// Moves a channel into a sidebar category and returns the reloaded category list.
    public func moveChannelToSidebarCategory(
        teamID: String,
        channelID: String,
        categoryID: String,
        position: Int? = nil,
        userID: String = "me"
    ) async throws -> MattermostSidebarCategoryMoveResult {
        let categories = try await sidebarCategories(teamID: teamID)
        guard let destination = categories.first(where: { $0.id == categoryID }) else {
            throw MattermostError.sidebarCategoryNotFound(categoryID)
        }

        let destinationChannelIDs = Self.sidebarChannelIDs(
            destination.channelIds,
            moving: channelID,
            to: position
        )
        var updatedCategories: [MattermostSidebarCategory] = []

        if destinationChannelIDs != destination.channelIds {
            let updatedDestination = try await updateSidebarCategory(
                teamID: teamID,
                categoryID: destination.id,
                displayName: destination.displayName,
                channelIDs: destinationChannelIDs,
                type: destination.type,
                userID: userID
            )
            updatedCategories.append(updatedDestination)
        }

        for category in categories where category.id != destination.id && category.isCustom && category.channelIds.contains(channelID) {
            let channelIDs = category.channelIds.filter { $0 != channelID }
            let updatedSource = try await updateSidebarCategory(
                teamID: teamID,
                categoryID: category.id,
                displayName: category.displayName,
                channelIDs: channelIDs,
                type: category.type,
                userID: userID
            )
            updatedCategories.append(updatedSource)
        }

        return MattermostSidebarCategoryMoveResult(
            updatedCategories: updatedCategories,
            categories: try await sidebarCategories(teamID: teamID)
        )
    }

    /// Reorders a channel within a sidebar category and returns the updated category.
    public func reorderChannelInSidebarCategory(
        teamID: String,
        categoryID: String,
        channelID: String,
        position: Int,
        userID: String = "me"
    ) async throws -> MattermostSidebarCategory {
        let category = try await sidebarCategory(teamID: teamID, categoryID: categoryID, userID: userID)
        let channelIDs = Self.sidebarChannelIDs(
            category.channelIds,
            moving: channelID,
            to: position
        )
        return try await updateSidebarCategory(
            teamID: teamID,
            categoryID: categoryID,
            displayName: category.displayName,
            channelIDs: channelIDs,
            type: category.type,
            userID: userID
        )
    }

    /// Deletes a custom sidebar category for the authenticated user on a team.
    @discardableResult
    public func deleteSidebarCategory(
        teamID: String,
        categoryID: String,
        userID: String = "me"
    ) async throws -> MattermostStatusOK {
        try await httpClient.delete("/users/\(userID)/teams/\(teamID)/channels/categories/\(categoryID)")
    }

    /// Loads sidebar category ordering for the authenticated user on a team.
    public func sidebarCategoryOrder(teamID: String, userID: String = "me") async throws -> [String] {
        try await httpClient.get("/users/\(userID)/teams/\(teamID)/channels/categories/order")
    }

    /// Updates sidebar category ordering for the authenticated user on a team.
    @discardableResult
    public func updateSidebarCategoryOrder(
        teamID: String,
        order: [String],
        userID: String = "me"
    ) async throws -> [String] {
        try await httpClient.put(
            "/users/\(userID)/teams/\(teamID)/channels/categories/order",
            body: order
        )
    }

    /// Loads a page of posts for a channel.
    public func posts(
        channelID: String,
        page: Int = 0,
        perPage: Int = 60,
        since: Int64? = nil,
        before: String? = nil,
        after: String? = nil
    ) async throws -> MattermostPostList {
        if let since {
            return try await postsSince(channelID: channelID, since: since)
        }

        var queryItems = [
            URLQueryItem(name: "page", value: String(Self.clampedPage(page))),
            URLQueryItem(name: "per_page", value: String(Self.clampedPerPage(perPage))),
        ]

        if let before, !before.isEmpty {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }

        if let after, !after.isEmpty {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }

        return try await httpClient.get("/channels/\(channelID)/posts", queryItems: queryItems)
    }

    /// Loads posts pinned in a channel.
    public func pinnedPosts(channelID: String) async throws -> MattermostPostList {
        try await httpClient.get("/channels/\(channelID)/pinned")
    }

    /// Loads posts created or modified after a Unix timestamp in milliseconds.
    public func postsSince(channelID: String, since: Int64) async throws -> MattermostPostList {
        try await httpClient.get(
            "/channels/\(channelID)/posts",
            queryItems: [
                URLQueryItem(name: "since", value: String(since)),
            ]
        )
    }

    /// Loads a single post by id.
    public func post(id: String) async throws -> MattermostPost {
        try await httpClient.get("/posts/\(id)")
    }

    /// Loads a post and the rest of the posts in the same thread.
    public func thread(
        postID: String,
        perPage: Int = 0,
        fromPost: String? = nil,
        fromCreateAt: Int64? = nil,
        direction: MattermostThreadDirection? = nil,
        skipFetchThreads: Bool? = nil,
        collapsedThreads: Bool? = nil,
        collapsedThreadsExtended: Bool? = nil
    ) async throws -> MattermostPostList {
        var queryItems = [
            URLQueryItem(name: "perPage", value: String(perPage)),
        ]

        if let fromPost, !fromPost.isEmpty {
            queryItems.append(URLQueryItem(name: "fromPost", value: fromPost))
        }

        if let fromCreateAt {
            queryItems.append(URLQueryItem(name: "fromCreateAt", value: String(fromCreateAt)))
        }

        if let direction {
            queryItems.append(URLQueryItem(name: "direction", value: direction.rawValue))
        }

        if let skipFetchThreads {
            queryItems.append(URLQueryItem(name: "skipFetchThreads", value: skipFetchThreads ? "true" : "false"))
        }

        if let collapsedThreads {
            queryItems.append(URLQueryItem(name: "collapsedThreads", value: collapsedThreads ? "true" : "false"))
        }

        if let collapsedThreadsExtended {
            queryItems.append(URLQueryItem(name: "collapsedThreadsExtended", value: collapsedThreadsExtended ? "true" : "false"))
        }

        return try await httpClient.get("/posts/\(postID)/thread", queryItems: queryItems)
    }

    /// Loads posts around the oldest unread post for a user in a channel.
    public func postsAroundLastUnread(
        userID: String = "me",
        channelID: String,
        limitBefore: Int = 30,
        limitAfter: Int = 30,
        skipFetchThreads: Bool = false,
        collapsedThreads: Bool = false,
        collapsedThreadsExtended: Bool = false
    ) async throws -> MattermostPostList {
        try await httpClient.get(
            "/users/\(userID)/channels/\(channelID)/posts/unread",
            queryItems: [
                URLQueryItem(name: "limit_before", value: String(max(0, limitBefore))),
                URLQueryItem(name: "limit_after", value: String(max(0, limitAfter))),
                URLQueryItem(name: "skipFetchThreads", value: skipFetchThreads ? "true" : "false"),
                URLQueryItem(name: "collapsedThreads", value: collapsedThreads ? "true" : "false"),
                URLQueryItem(name: "collapsedThreadsExtended", value: collapsedThreadsExtended ? "true" : "false"),
            ]
        )
    }

    /// Lists per-user thread inbox state for a team.
    public func userThreads(
        userID: String = "me",
        teamID: String,
        request: MattermostThreadListRequest = MattermostThreadListRequest()
    ) async throws -> MattermostThreadList {
        var queryItems: [URLQueryItem] = []

        if let since = request.since {
            queryItems.append(URLQueryItem(name: "since", value: String(since)))
        }

        if let before = request.before, !before.isEmpty {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }

        if let after = request.after, !after.isEmpty {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }

        if request.perPage > 0 {
            queryItems.append(URLQueryItem(name: "per_page", value: String(request.perPage)))
        }

        if request.extended {
            queryItems.append(URLQueryItem(name: "extended", value: "true"))
        }

        if request.deleted {
            queryItems.append(URLQueryItem(name: "deleted", value: "true"))
        }

        if request.unread {
            queryItems.append(URLQueryItem(name: "unread", value: "true"))
        }

        if request.threadsOnly {
            queryItems.append(URLQueryItem(name: "threadsOnly", value: "true"))
        }

        if request.totalsOnly {
            queryItems.append(URLQueryItem(name: "totalsOnly", value: "true"))
        }

        if request.excludeDirect {
            queryItems.append(URLQueryItem(name: "excludeDirect", value: "true"))
        }

        return try await httpClient.get(
            "/users/\(userID)/teams/\(teamID)/threads",
            queryItems: queryItems
        )
    }

    /// Loads one per-user thread inbox state record for a team.
    public func userThread(
        userID: String = "me",
        teamID: String,
        threadID: String,
        extended: Bool = false
    ) async throws -> MattermostThreadResponse {
        let queryItems = extended ? [URLQueryItem(name: "extended", value: "true")] : []
        return try await httpClient.get(
            "/users/\(userID)/teams/\(teamID)/threads/\(threadID)",
            queryItems: queryItems
        )
    }

    /// Loads a unified channel or thread timeline page.
    public func timeline(
        _ target: MattermostTimelineTarget,
        request: MattermostTimelineRequest = MattermostTimelineRequest()
    ) async throws -> MattermostTimelinePage {
        let postList: MattermostPostList
        switch target {
        case .channel(let channelID):
            postList = try await posts(
                channelID: channelID,
                page: request.page,
                perPage: request.perPage,
                since: request.since,
                before: request.before,
                after: request.after
            )
        case .thread(let rootPostID):
            postList = try await thread(
                postID: rootPostID,
                perPage: request.perPage,
                fromPost: request.fromPost,
                fromCreateAt: request.fromCreateAt,
                direction: request.direction,
                skipFetchThreads: request.skipFetchThreads,
                collapsedThreads: request.collapsedThreads,
                collapsedThreadsExtended: request.collapsedThreadsExtended
            )
        }

        return MattermostTimelinePage(target: target, postList: postList)
    }

    /// Sends a post to a channel. Set `rootID` to create a reply.
    public func sendPost(
        channelID: String,
        message: String,
        rootID: String? = nil,
        fileIDs: [String] = [],
        props: [String: MattermostJSONValue] = [:]
    ) async throws -> MattermostPost {
        try await httpClient.post(
            "/posts",
            body: MattermostCreatePostRequest(
                channelId: channelID,
                message: message,
                rootId: rootID,
                fileIds: fileIDs,
                props: props
            )
        )
    }

    /// Updates the message body for a post.
    public func editPost(
        id: String,
        message: String,
        props: [String: MattermostJSONValue]? = nil
    ) async throws -> MattermostPost {
        try await httpClient.put(
            "/posts/\(id)/patch",
            body: MattermostPatchPostRequest(message: message, props: props)
        )
    }

    /// Soft-deletes a post.
    @discardableResult
    public func deletePost(id: String) async throws -> MattermostStatusOK {
        try await httpClient.delete("/posts/\(id)")
    }

    /// Adds an emoji reaction to a post.
    public func addReaction(
        postID: String,
        userID: String,
        emojiName: String
    ) async throws -> MattermostReaction {
        try await httpClient.post(
            "/reactions",
            body: MattermostReactionRequest(
                userId: userID,
                postId: postID,
                emojiName: emojiName
            )
        )
    }

    /// Lists reactions on a post.
    public func reactions(postID: String) async throws -> [MattermostReaction] {
        try await httpClient.get("/posts/\(postID)/reactions")
    }

    /// Removes an emoji reaction from a post.
    @discardableResult
    public func removeReaction(
        postID: String,
        userID: String,
        emojiName: String
    ) async throws -> MattermostStatusOK {
        try await httpClient.delete("/users/\(userID)/posts/\(postID)/reactions/\(emojiName)")
    }

    /// Searches posts in a team.
    public func searchPosts(
        teamID: String,
        terms: String,
        isOrSearch: Bool = false,
        page: Int = 0,
        perPage: Int = 60
    ) async throws -> MattermostPostSearchResults {
        try await httpClient.post(
            "/teams/\(teamID)/posts/search",
            body: MattermostPostSearchRequest(
                terms: terms,
                isOrSearch: isOrSearch,
                timeZoneOffset: 0,
                includeDeletedChannels: false,
                page: page,
                perPage: perPage
            )
        )
    }

    /// Uploads a file for later attachment to a post.
    public func uploadFile(
        channelID: String,
        filename: String,
        data: Data,
        contentType: String = "application/octet-stream",
        clientID: String? = nil
    ) async throws -> MattermostFileUploadResponse {
        var parts = [
            MattermostMultipartPart(
                name: "channel_id",
                filename: nil,
                contentType: nil,
                data: Data(channelID.utf8)
            ),
            MattermostMultipartPart(
                name: "files",
                filename: filename,
                contentType: contentType,
                data: data
            ),
        ]

        if let clientID, !clientID.isEmpty {
            parts.append(
                MattermostMultipartPart(
                    name: "client_ids",
                    filename: nil,
                    contentType: nil,
                    data: Data(clientID.utf8)
                )
            )
        }

        return try await httpClient.multipart("/files", parts: parts)
    }

    /// Loads metadata for a file by id.
    public func fileInfo(id: String) async throws -> MattermostFileInfo {
        try await httpClient.get("/files/\(id)/info")
    }

    /// Loads metadata for files attached to a post.
    public func fileInfos(postID: String) async throws -> [MattermostFileInfo] {
        try await httpClient.get("/posts/\(postID)/files/info")
    }

    /// Downloads raw bytes for a file by id.
    public func downloadFile(id: String) async throws -> Data {
        try await httpClient.data("/files/\(id)")
    }

    /// Lists custom emoji metadata.
    public func customEmoji(page: Int = 0, perPage: Int = 60, sort: String = "name") async throws -> [MattermostCustomEmoji] {
        try await httpClient.get(
            "/emoji",
            queryItems: [
                URLQueryItem(name: "page", value: String(Self.clampedPage(page))),
                URLQueryItem(name: "per_page", value: String(Self.clampedPerPage(perPage))),
                URLQueryItem(name: "sort", value: sort),
            ]
        )
    }

    /// Loads custom emoji metadata by id.
    public func customEmoji(id: String) async throws -> MattermostCustomEmoji {
        try await httpClient.get("/emoji/\(id)")
    }

    /// Loads custom emoji metadata by name.
    public func customEmoji(named name: String) async throws -> MattermostCustomEmoji {
        try await httpClient.get("/emoji/name/\(name)")
    }

    /// Searches custom emoji by name.
    public func searchCustomEmoji(term: String, prefixOnly: Bool = false) async throws -> [MattermostCustomEmoji] {
        try await httpClient.post(
            "/emoji/search",
            body: MattermostEmojiSearchRequest(term: term, prefixOnly: prefixOnly)
        )
    }

    /// Autocompletes custom emoji names.
    public func autocompleteCustomEmoji(name: String) async throws -> [MattermostCustomEmoji] {
        try await httpClient.get(
            "/emoji/autocomplete",
            queryItems: [
                URLQueryItem(name: "name", value: name),
            ]
        )
    }

    /// Downloads a custom emoji image.
    public func customEmojiImage(id: String) async throws -> Data {
        try await httpClient.data("/emoji/\(id)/image")
    }

    /// Creates a WebSocket live-event stream for this client.
    public func liveEventStream() -> MattermostLiveEventStream {
        MattermostLiveEventStream(configuration: configuration, urlSession: urlSession)
    }

    private func resolvedUserIDForRequestBody(_ userID: String) async throws -> String {
        if userID == "me" {
            return try await currentUser().id
        }
        return userID
    }

    private static func clampedPage(_ page: Int) -> Int {
        max(0, page)
    }

    private static func clampedPerPage(_ perPage: Int) -> Int {
        max(1, perPage)
    }

    static func sidebarChannelIDs(
        _ channelIDs: [String],
        moving channelID: String,
        to position: Int?
    ) -> [String] {
        var result = channelIDs.filter { $0 != channelID }
        let insertionIndex = max(0, min(position ?? result.count, result.count))
        result.insert(channelID, at: insertionIndex)
        return result
    }
}

public extension MattermostClient {
    /// Logs in with a username/email and password, returning the user plus session token.
    ///
    /// Mattermost browser clients can authenticate from the `MMAUTHTOKEN` cookie that is set
    /// by a successful login. API clients can authenticate with the same session token as a
    /// bearer token, so the SDK accepts either the documented `Token` response header or the
    /// official `MMAUTHTOKEN` cookie. The SDK does not store the returned token. Host apps are
    /// responsible for secure storage.
    static func login(
        serverURL: URL,
        loginID: String,
        password: String,
        mfaToken: String? = nil,
        deviceID: String? = nil,
        ldapOnly: Bool? = nil,
        urlSession: URLSession = .mattermost
    ) async throws -> MattermostSession {
        let configuration = try MattermostConfiguration(
            serverURL: serverURL,
            authentication: .none
        )
        let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: urlSession)
        var request = try httpClient.makeJSONRequest(
            endpoint: "/users/login",
            method: "POST",
            body: MattermostLoginRequest(
                loginId: loginID,
                password: password,
                token: mfaToken,
                deviceId: deviceID,
                ldapOnly: ldapOnly
            )
        )
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let response: MattermostHTTPResponse<MattermostUser> = try await httpClient.performWithResponse(request: request)
        if let sessionToken = response.httpResponse.mattermostSessionToken(
            cookieStorage: urlSession.configuration.httpCookieStorage
        ) {
            return MattermostSession(
                user: response.value,
                token: sessionToken.token,
                tokenSource: sessionToken.source
            )
        }

#if os(macOS)
        // Some deployments reset URLSession's TLS connection (-1005); retry login via curl.
        let curlResponse: MattermostHTTPResponse<MattermostUser> = try await httpClient.performLoginWithCurlResponse(request: request)
        if let sessionToken = curlResponse.httpResponse.mattermostSessionToken(cookieStorage: nil) {
            return MattermostSession(
                user: curlResponse.value,
                token: sessionToken.token,
                tokenSource: sessionToken.source
            )
        }
#endif

        throw MattermostError.missingAuthenticationToken
    }

    /// Logs in from Mattermost development environment variables.
    ///
    /// Required:
    /// - `MATTERMOST_URL`
    /// - `MATTERMOST_USERNAME`
    /// - `MATTERMOST_PASSWORD`
    static func loginFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        urlSession: URLSession = .mattermost
    ) async throws -> MattermostSession {
        guard let rawURL = environment["MATTERMOST_URL"], !rawURL.isEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_URL")
        }
        guard let serverURL = URL(string: rawURL) else {
            throw MattermostError.invalidServerURL(rawURL)
        }
        guard let username = environment["MATTERMOST_USERNAME"].nonEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_USERNAME")
        }
        guard let password = environment["MATTERMOST_PASSWORD"].nonEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_PASSWORD")
        }

        return try await login(
            serverURL: serverURL,
            loginID: username,
            password: password,
            urlSession: urlSession
        )
    }

    /// Backfills posts for a channel using the store cursor and updates that cursor.
    @MainActor
    func syncChannelPosts(
        channelID: String,
        to store: MattermostStore,
        perPage: Int = 60,
        maxPages: Int = 1
    ) async throws -> MattermostChannelPostSyncResult {
        let cursorScope = "channel-posts:\(channelID)"
        let cursor = try store.cachedSyncCursor(scope: cursorScope)
        var orderedIDs: [String] = []
        var postsByID: [String: MattermostPost] = [:]
        var pageCount = 0

        let postLists: [MattermostPostList]
        if let since = cursor?.lastSyncAt, since > 0 {
            postLists = [try await postsSince(channelID: channelID, since: since)]
        } else {
            var pages: [MattermostPostList] = []
            for page in 0..<max(1, maxPages) {
                let postList = try await posts(
                    channelID: channelID,
                    page: page,
                    perPage: max(1, perPage)
                )
                pages.append(postList)
                if postList.orderedPosts.count < max(1, perPage) {
                    break
                }
            }
            postLists = pages
        }

        for postList in postLists {
            try store.upsert(postList: postList)
            pageCount += 1

            for postID in postList.order where postsByID[postID] == nil {
                orderedIDs.append(postID)
            }
            postsByID.merge(postList.posts) { _, new in new }
        }

        let orderedPosts = orderedIDs.compactMap { postsByID[$0] }
        let lastPost = orderedPosts.max { lhs, rhs in
            lhs.cacheTimestamp < rhs.cacheTimestamp
        }
        let cursorLastSyncAt = lastPost?.cacheTimestamp ?? cursor?.lastSyncAt ?? 0
        let cursorLastItemID = lastPost?.id ?? cursor?.lastItemID
        try store.setSyncCursor(
            scope: cursorScope,
            lastSyncAt: cursorLastSyncAt,
            lastItemID: cursorLastItemID
        )

        return MattermostChannelPostSyncResult(
            channelID: channelID,
            posts: orderedPosts,
            pageCount: pageCount,
            cursorLastSyncAt: cursorLastSyncAt,
            cursorLastItemID: cursorLastItemID
        )
    }

    /// Syncs a channel or thread timeline into the store and updates its cursor.
    @MainActor
    func syncTimeline(
        _ target: MattermostTimelineTarget,
        to store: MattermostStore,
        request: MattermostTimelineRequest = MattermostTimelineRequest(),
        maxPages: Int = 1
    ) async throws -> MattermostTimelineSyncResult {
        switch target {
        case .channel(let channelID):
            let result = try await syncChannelPosts(
                channelID: channelID,
                to: store,
                perPage: request.perPage,
                maxPages: maxPages
            )
            return MattermostTimelineSyncResult(
                target: target,
                posts: result.posts,
                pageCount: result.pageCount,
                cursorLastSyncAt: result.cursorLastSyncAt,
                cursorLastItemID: result.cursorLastItemID
            )

        case .thread:
            let page = try await timeline(target, request: request)
            try store.upsert(postList: page.postList)
            let lastPost = page.posts.max { lhs, rhs in
                lhs.cacheTimestamp < rhs.cacheTimestamp
            }
            let cursorLastSyncAt = lastPost?.cacheTimestamp ?? 0
            let cursorLastItemID = lastPost?.id
            try store.setSyncCursor(
                scope: target.cacheScope,
                lastSyncAt: cursorLastSyncAt,
                lastItemID: cursorLastItemID
            )
            try store.save()
            return MattermostTimelineSyncResult(
                target: target,
                posts: page.posts,
                pageCount: 1,
                cursorLastSyncAt: cursorLastSyncAt,
                cursorLastItemID: cursorLastItemID
            )
        }
    }

    /// Builds a client from Mattermost development environment variables.
    ///
    /// Required:
    /// - `MATTERMOST_URL`
    /// - `MATTERMOST_TOKEN`, or `MATTERMOST_AUTH_TOKEN` as a local compatibility alias
    static func liveFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> MattermostClient {
        guard let rawURL = environment["MATTERMOST_URL"], !rawURL.isEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_URL")
        }
        guard let serverURL = URL(string: rawURL) else {
            throw MattermostError.invalidServerURL(rawURL)
        }
        guard let token = environment["MATTERMOST_TOKEN"].nonEmpty ?? environment["MATTERMOST_AUTH_TOKEN"].nonEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_TOKEN")
        }
        return try MattermostClient(serverURL: serverURL, token: token)
    }
}

private extension HTTPURLResponse {
    func mattermostSessionToken(
        cookieStorage: HTTPCookieStorage?
    ) -> (token: String, source: MattermostSessionTokenSource)? {
        if let token = authenticationToken.nonEmpty {
            return (token, .responseHeader)
        }

        if let token = mattermostAuthCookieToken.nonEmpty {
            return (token, .authCookie)
        }

        if let url,
           let token = cookieStorage?
               .cookies(for: url)?
               .first(where: { $0.name == "MMAUTHTOKEN" })?
               .value
               .nonEmpty {
            return (token, .authCookie)
        }

        return nil
    }

    var authenticationToken: String? {
        for (key, value) in allHeaderFields {
            guard String(describing: key).lowercased() == "token" else {
                continue
            }
            return String(describing: value)
        }
        return nil
    }

    var mattermostAuthCookieToken: String? {
        guard let url else {
            return nil
        }

        var headerFields: [String: String] = [:]
        for (key, value) in allHeaderFields {
            headerFields[String(describing: key)] = String(describing: value)
        }

        return HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            .first(where: { $0.name == "MMAUTHTOKEN" })?
            .value
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self, !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

public extension URLSession {
    /// URLSession preconfigured with finite request/resource timeouts for Mattermost.
    ///
    /// `URLSession.shared` uses a 7-day resource timeout, which lets a stalled server hang a
    /// request indefinitely. This session caps a single request at 30s and a full transfer
    /// (e.g. a file download) at 5 minutes.
    static let mattermost: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()
}
