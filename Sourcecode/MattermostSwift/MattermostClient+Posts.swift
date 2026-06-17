import Foundation

// MARK: - Posts

extension MattermostClient {
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

    /// Pins a post in its channel.
    @discardableResult
    public func pinPost(id: String) async throws -> MattermostStatusOK {
        try await httpClient.post("/posts/\(id)/pin")
    }

    /// Unpins a post in its channel.
    @discardableResult
    public func unpinPost(id: String) async throws -> MattermostStatusOK {
        try await httpClient.post("/posts/\(id)/unpin")
    }
}
