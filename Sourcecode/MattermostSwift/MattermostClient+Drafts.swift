import Foundation

// MARK: - Synced drafts

extension MattermostClient {
    /// Loads every synced draft belonging to a user in one team.
    ///
    /// Servers expose this endpoint only when `AllowSyncedDrafts` is enabled in
    /// ``MattermostClientConfig``. A user without drafts gets JSON `null` rather
    /// than an empty array; that is returned as an empty list.
    public func drafts(teamID: String, userID: String = "me") async throws -> [MattermostDraft] {
        let drafts: [MattermostDraft]? = try await httpClient.get("/users/\(userID)/teams/\(teamID)/drafts")
        return drafts ?? []
    }

    /// Creates or replaces the channel/thread draft identified by the request.
    ///
    /// Mattermost treats an empty message as a deletion and returns JSON `null`,
    /// represented here as `nil`.
    @discardableResult
    public func upsertDraft(_ request: MattermostDraftUpsertRequest) async throws -> MattermostDraft? {
        try await httpClient.post("/drafts", body: request)
    }

    /// Deletes a channel or thread draft for a user.
    @discardableResult
    public func deleteDraft(
        channelID: String,
        rootID: String? = nil,
        userID: String = "me"
    ) async throws -> MattermostStatusOK {
        let suffix = rootID.flatMap { $0.nonEmpty }.map { "/\($0)" } ?? ""
        return try await httpClient.delete(
            "/users/\(userID)/channels/\(channelID)/drafts\(suffix)"
        )
    }
}
