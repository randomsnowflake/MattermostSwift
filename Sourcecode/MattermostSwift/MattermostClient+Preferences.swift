import Foundation

// MARK: - Preferences

extension MattermostClient {
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
}
