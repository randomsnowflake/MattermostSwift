import Foundation

// MARK: - Threads

extension MattermostClient {
    /// Loads a post and the rest of the posts in the same thread.
    public func thread(
        postID: String,
        options: MattermostThreadOptions
    ) async throws -> MattermostPostList {
        // The thread endpoint intentionally uses camelCase query parameters
        // (`perPage`, `fromPost`, `fromCreateAt`, `skipFetchThreads`, ...), unlike the
        // snake_case parameters used elsewhere. This matches Mattermost's
        // `GET /posts/{post_id}/thread` contract — do not "normalize" these to snake_case.
        var queryItems = [
            URLQueryItem(name: "perPage", value: String(options.perPage)),
        ]

        if let fromPost = options.fromPost, !fromPost.isEmpty {
            queryItems.append(URLQueryItem(name: "fromPost", value: fromPost))
        }

        if let fromCreateAt = options.fromCreateAt {
            queryItems.append(URLQueryItem(name: "fromCreateAt", value: String(fromCreateAt)))
        }

        if let direction = options.direction {
            queryItems.append(URLQueryItem(name: "direction", value: direction.rawValue))
        }

        if let skipFetchThreads = options.skipFetchThreads {
            queryItems.append(URLQueryItem(name: "skipFetchThreads", value: skipFetchThreads ? "true" : "false"))
        }

        if let collapsedThreads = options.collapsedThreads {
            queryItems.append(URLQueryItem(name: "collapsedThreads", value: collapsedThreads ? "true" : "false"))
        }

        if let collapsedThreadsExtended = options.collapsedThreadsExtended {
            queryItems.append(URLQueryItem(name: "collapsedThreadsExtended", value: collapsedThreadsExtended ? "true" : "false"))
        }

        return try await httpClient.get("/posts/\(postID)/thread", queryItems: queryItems)
    }

    /// Compatibility overload for the pre-options parameter list.
    @available(*, deprecated, message: "Use thread(postID:options:)")
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
        try await thread(
            postID: postID,
            options: MattermostThreadOptions(
                perPage: perPage,
                fromPost: fromPost,
                fromCreateAt: fromCreateAt,
                direction: direction,
                skipFetchThreads: skipFetchThreads,
                collapsedThreads: collapsedThreads,
                collapsedThreadsExtended: collapsedThreadsExtended
            )
        )
    }

    /// Loads posts around the oldest unread post for a user in a channel.
    public func postsAroundLastUnread(
        channelID: String,
        userID: String = "me",
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

    @available(*, deprecated, renamed: "postsAroundLastUnread(channelID:userID:limitBefore:limitAfter:skipFetchThreads:collapsedThreads:collapsedThreadsExtended:)")
    public func postsAroundLastUnread(
        userID: String,
        channelID: String,
        limitBefore: Int = 30,
        limitAfter: Int = 30,
        skipFetchThreads: Bool = false,
        collapsedThreads: Bool = false,
        collapsedThreadsExtended: Bool = false
    ) async throws -> MattermostPostList {
        try await postsAroundLastUnread(
            channelID: channelID,
            userID: userID,
            limitBefore: limitBefore,
            limitAfter: limitAfter,
            skipFetchThreads: skipFetchThreads,
            collapsedThreads: collapsedThreads,
            collapsedThreadsExtended: collapsedThreadsExtended
        )
    }

    /// Lists per-user thread inbox state for a team.
    public func userThreads(
        teamID: String,
        userID: String = "me",
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

    @available(*, deprecated, renamed: "userThreads(teamID:userID:request:)")
    public func userThreads(
        userID: String,
        teamID: String,
        request: MattermostThreadListRequest = MattermostThreadListRequest()
    ) async throws -> MattermostThreadList {
        try await userThreads(teamID: teamID, userID: userID, request: request)
    }

    /// Loads one per-user thread inbox state record for a team.
    public func userThread(
        teamID: String,
        threadID: String,
        userID: String = "me",
        extended: Bool = false
    ) async throws -> MattermostThreadResponse {
        let queryItems = extended ? [URLQueryItem(name: "extended", value: "true")] : []
        return try await httpClient.get(
            "/users/\(userID)/teams/\(teamID)/threads/\(threadID)",
            queryItems: queryItems
        )
    }

    @available(*, deprecated, renamed: "userThread(teamID:threadID:userID:extended:)")
    public func userThread(
        userID: String,
        teamID: String,
        threadID: String,
        extended: Bool = false
    ) async throws -> MattermostThreadResponse {
        try await userThread(
            teamID: teamID,
            threadID: threadID,
            userID: userID,
            extended: extended
        )
    }

    /// Marks a followed thread read up to the supplied server timestamp.
    ///
    /// Mattermost expects milliseconds since epoch here, matching post `create_at`
    /// and thread `last_reply_at` values. Passing seconds leaves the thread unread.
    @discardableResult
    public func markThreadRead(
        teamID: String,
        threadID: String,
        userID: String = "me",
        timestamp: Int64
    ) async throws -> MattermostThreadResponse {
        try await httpClient.put(
            "/users/\(userID)/teams/\(teamID)/threads/\(threadID)/read/\(timestamp)"
        )
    }

    /// Marks a followed thread read up to a `Date`.
    @discardableResult
    public func markThreadRead(
        teamID: String,
        threadID: String,
        userID: String = "me",
        upTo date: Date
    ) async throws -> MattermostThreadResponse {
        try await markThreadRead(
            teamID: teamID,
            threadID: threadID,
            userID: userID,
            timestamp: date.mattermostMilliseconds
        )
    }

    /// Marks every thread in a team's per-user thread inbox as read.
    @discardableResult
    public func markAllThreadsRead(
        teamID: String,
        userID: String = "me"
    ) async throws -> MattermostStatusOK {
        try await httpClient.put(
            "/users/\(userID)/teams/\(teamID)/threads/read"
        )
    }

    @available(*, deprecated, renamed: "markThreadRead(teamID:threadID:userID:timestamp:)")
    @discardableResult
    public func markThreadRead(
        userID: String,
        teamID: String,
        threadID: String,
        timestamp: Int64
    ) async throws -> MattermostThreadResponse {
        try await markThreadRead(
            teamID: teamID,
            threadID: threadID,
            userID: userID,
            timestamp: timestamp
        )
    }

    /// Updates whether a user follows a collapsed reply thread.
    @discardableResult
    public func setThreadFollowing(
        teamID: String,
        threadID: String,
        userID: String = "me",
        following: Bool
    ) async throws -> MattermostStatusOK {
        let endpoint = "/users/\(userID)/teams/\(teamID)/threads/\(threadID)/following"
        if following {
            return try await httpClient.put(endpoint)
        }
        return try await httpClient.delete(endpoint)
    }

    @available(*, deprecated, renamed: "setThreadFollowing(teamID:threadID:userID:following:)")
    @discardableResult
    public func setThreadFollowing(
        userID: String,
        teamID: String,
        threadID: String,
        following: Bool
    ) async throws -> MattermostStatusOK {
        try await setThreadFollowing(
            teamID: teamID,
            threadID: threadID,
            userID: userID,
            following: following
        )
    }
}
