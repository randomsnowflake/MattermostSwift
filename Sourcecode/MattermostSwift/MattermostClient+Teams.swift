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
}
