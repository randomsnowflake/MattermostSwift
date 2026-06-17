import Foundation

// MARK: - Sidebar

extension MattermostClient {
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

    private func resolvedUserIDForRequestBody(_ userID: String) async throws -> String {
        if userID == "me" {
            return try await currentUser().id
        }
        return userID
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
