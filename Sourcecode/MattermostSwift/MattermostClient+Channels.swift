import Foundation

// MARK: - Channels

extension MattermostClient {
    /// Lists channels on a team for the authenticated user.
    public func joinedChannels(teamID: String) async throws -> [MattermostChannel] {
        try await httpClient.get("/users/me/teams/\(teamID)/channels")
    }

    /// Lists public channels on a team that the authenticated user may discover.
    public func publicChannels(
        teamID: String,
        page: Int = 0,
        perPage: Int = 60,
        includeDeleted: Bool = false
    ) async throws -> [MattermostChannel] {
        try await httpClient.get(
            "/teams/\(teamID)/channels",
            queryItems: Self.pageQueryItems(page: page, perPage: perPage) + [
                URLQueryItem(name: "include_deleted", value: String(includeDeleted)),
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

    /// Lists archived channels on a team.
    public func deletedChannels(teamID: String, page: Int = 0, perPage: Int = 60) async throws -> [MattermostChannel] {
        try await httpClient.get(
            "/teams/\(teamID)/channels/deleted",
            queryItems: Self.pageQueryItems(page: page, perPage: perPage)
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

    /// Restores an archived channel.
    public func restoreChannel(id: String) async throws -> MattermostChannel {
        try await httpClient.post("/channels/\(id)/restore")
    }

    /// Updates a channel privacy type (`"O"` public, `"P"` private).
    public func setChannelPrivacy(id: String, type: String) async throws -> MattermostChannel {
        try await httpClient.put(
            "/channels/\(id)/privacy",
            body: MattermostChannelPrivacyRequest(privacy: type)
        )
    }

    /// Converts a group message into a private channel in a team.
    public func convertGroupToChannel(
        id: String,
        teamID: String,
        name: String? = nil,
        displayName: String? = nil
    ) async throws -> MattermostChannel {
        try await httpClient.post(
            "/channels/\(id)/convert_to_channel",
            body: MattermostGroupMessageConversionRequest(
                channelId: id,
                teamId: teamID,
                name: name,
                displayName: displayName
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
}
