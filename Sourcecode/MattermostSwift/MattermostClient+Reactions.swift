import Foundation

// MARK: - Reactions

extension MattermostClient {
    /// Adds an emoji reaction to a post.
    public func addReaction(
        postID: String,
        userID: String,
        emojiName: String
    ) async throws -> MattermostReaction {
        try await httpClient.post(
            "/reactions",
            body: MattermostReactionRequest(
                userId: userID,
                postId: postID,
                emojiName: emojiName
            )
        )
    }

    /// Lists reactions on a post.
    public func reactions(postID: String) async throws -> [MattermostReaction] {
        try await httpClient.get("/posts/\(postID)/reactions")
    }

    /// Removes an emoji reaction from a post.
    @discardableResult
    public func removeReaction(
        postID: String,
        userID: String,
        emojiName: String
    ) async throws -> MattermostStatusOK {
        try await httpClient.delete("/users/\(userID)/posts/\(postID)/reactions/\(emojiName)")
    }

    /// Searches posts in a team.
    public func searchPosts(
        teamID: String,
        terms: String,
        isOrSearch: Bool = false,
        page: Int = 0,
        perPage: Int = 60
    ) async throws -> MattermostPostSearchResults {
        try await httpClient.post(
            "/teams/\(teamID)/posts/search",
            body: MattermostPostSearchRequest(
                terms: terms,
                isOrSearch: isOrSearch,
                timeZoneOffset: 0,
                includeDeletedChannels: false,
                page: page,
                perPage: perPage
            )
        )
    }
}
