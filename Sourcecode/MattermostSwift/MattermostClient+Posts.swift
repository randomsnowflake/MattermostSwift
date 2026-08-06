import Foundation

// MARK: - Posts

extension MattermostClient {
    /// Loads a page of posts for a channel.
    ///
    /// If `options.since` is set, the server's update-fetch mode is used and
    /// `page`, `perPage`, `before`, and `after` are ignored.
    public func posts(
        channelID: String,
        options: MattermostPostsOptions
    ) async throws -> MattermostPostList {
        if let since = options.since {
            return try await postsSince(
                channelID: channelID,
                since: since,
                skipFetchThreads: options.skipFetchThreads,
                collapsedThreads: options.collapsedThreads,
                collapsedThreadsExtended: options.collapsedThreadsExtended
            )
        }

        var queryItems = Self.pageQueryItems(page: options.page, perPage: options.perPage)

        if let before = options.before, !before.isEmpty {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }

        if let after = options.after, !after.isEmpty {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }

        if let skipFetchThreads = options.skipFetchThreads {
            queryItems.append(URLQueryItem(name: "skipFetchThreads", value: String(skipFetchThreads)))
        }

        if let collapsedThreads = options.collapsedThreads {
            queryItems.append(URLQueryItem(name: "collapsedThreads", value: String(collapsedThreads)))
        }

        if let collapsedThreadsExtended = options.collapsedThreadsExtended {
            queryItems.append(URLQueryItem(name: "collapsedThreadsExtended", value: String(collapsedThreadsExtended)))
        }

        return try await httpClient.get("/channels/\(channelID)/posts", queryItems: queryItems)
    }

    /// Compatibility overload for the pre-options parameter list.
    @available(*, deprecated, message: "Use posts(channelID:options:)")
    public func posts(
        channelID: String,
        page: Int = 0,
        perPage: Int = 60,
        since: Int64? = nil,
        before: String? = nil,
        after: String? = nil,
        skipFetchThreads: Bool? = nil,
        collapsedThreads: Bool? = nil,
        collapsedThreadsExtended: Bool? = nil
    ) async throws -> MattermostPostList {
        try await posts(
            channelID: channelID,
            options: MattermostPostsOptions(
                page: page,
                perPage: perPage,
                since: since,
                before: before,
                after: after,
                skipFetchThreads: skipFetchThreads,
                collapsedThreads: collapsedThreads,
                collapsedThreadsExtended: collapsedThreadsExtended
            )
        )
    }

    /// Loads posts pinned in a channel.
    public func pinnedPosts(channelID: String) async throws -> MattermostPostList {
        try await httpClient.get("/channels/\(channelID)/pinned")
    }

    /// Loads posts created or modified after a Unix timestamp in milliseconds.
    public func postsSince(
        channelID: String,
        since: Int64,
        skipFetchThreads: Bool? = nil,
        collapsedThreads: Bool? = nil,
        collapsedThreadsExtended: Bool? = nil
    ) async throws -> MattermostPostList {
        var queryItems = [URLQueryItem(name: "since", value: String(since))]
        if let skipFetchThreads {
            queryItems.append(URLQueryItem(name: "skipFetchThreads", value: String(skipFetchThreads)))
        }
        if let collapsedThreads {
            queryItems.append(URLQueryItem(name: "collapsedThreads", value: String(collapsedThreads)))
        }
        if let collapsedThreadsExtended {
            queryItems.append(URLQueryItem(name: "collapsedThreadsExtended", value: String(collapsedThreadsExtended)))
        }
        return try await httpClient.get(
            "/channels/\(channelID)/posts",
            queryItems: queryItems
        )
    }

    /// Loads a single post by id.
    public func post(id: String) async throws -> MattermostPost {
        try await httpClient.get("/posts/\(id)")
    }

    /// Marks the post's channel unread starting at the supplied post.
    ///
    /// Mattermost stores one chronological channel read frontier. Passing
    /// `collapsedThreadsSupported: true` keeps root-post and followed-thread
    /// unread state consistent with clients that support collapsed threads.
    @discardableResult
    public func setPostUnread(
        postID: String,
        userID: String = "me",
        collapsedThreadsSupported: Bool = false
    ) async throws -> MattermostChannelUnreadAt {
        try await httpClient.post(
            "/users/\(userID)/posts/\(postID)/set_unread",
            body: MattermostSetPostUnreadRequest(
                collapsedThreadsSupported: collapsedThreadsSupported
            )
        )
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
