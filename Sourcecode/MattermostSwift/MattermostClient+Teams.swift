import Foundation

// MARK: - Teams

extension MattermostClient {
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

    /// Unread and mention counts for the user's teams.
    ///
    /// The server aggregates these rows and returns them unordered. With an
    /// `excludeTeamID`, it can also return a row with an empty `teamID` that
    /// aggregates direct and group messages. The SDK returns the raw rows;
    /// callers decide which rows count toward their own badges.
    public func teamsUnread(
        userID: String = "me",
        excludeTeamID: String? = nil,
        includeCollapsedThreads: Bool = true
    ) async throws -> [MattermostTeamUnread] {
        var queryItems: [URLQueryItem] = []
        if let excludeTeamID, !excludeTeamID.isEmpty {
            queryItems.append(URLQueryItem(name: "exclude_team", value: excludeTeamID))
        }
        queryItems.append(
            URLQueryItem(name: "include_collapsed_threads", value: includeCollapsedThreads ? "true" : "false")
        )
        return try await httpClient.get("/users/\(userID)/teams/unread", queryItems: queryItems)
    }

    /// Lists team membership records for users on a team.
    public func teamMembers(
        teamID: String,
        page: Int = 0,
        perPage: Int = 60,
        sort: String? = nil,
        excludeDeletedUsers: Bool = false
    ) async throws -> [MattermostTeamMember] {
        var queryItems = Self.pageQueryItems(page: page, perPage: perPage)
        if let sort, !sort.isEmpty {
            queryItems.append(URLQueryItem(name: "sort", value: sort))
        }
        if excludeDeletedUsers {
            queryItems.append(URLQueryItem(name: "exclude_deleted_users", value: "true"))
        }

        return try await httpClient.get("/teams/\(teamID)/members", queryItems: queryItems)
    }
}
