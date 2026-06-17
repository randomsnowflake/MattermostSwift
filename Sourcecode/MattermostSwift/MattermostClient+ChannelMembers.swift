import Foundation

// MARK: - Channel Members

extension MattermostClient {
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
}
