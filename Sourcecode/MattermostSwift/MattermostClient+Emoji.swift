import Foundation

// MARK: - Emoji

extension MattermostClient {
    /// Lists custom emoji metadata.
    public func customEmoji(page: Int = 0, perPage: Int = 60, sort: String = "name") async throws -> [MattermostCustomEmoji] {
        try await httpClient.get(
            "/emoji",
            queryItems: Self.pageQueryItems(page: page, perPage: perPage) + [
                URLQueryItem(name: "sort", value: sort),
            ]
        )
    }

    /// Loads custom emoji metadata by id.
    public func customEmoji(id: String) async throws -> MattermostCustomEmoji {
        try await httpClient.get("/emoji/\(id)")
    }

    /// Loads custom emoji metadata by name.
    public func customEmoji(named name: String) async throws -> MattermostCustomEmoji {
        try await httpClient.get("/emoji/name/\(name)")
    }

    /// Searches custom emoji by name.
    public func searchCustomEmoji(term: String, prefixOnly: Bool = false) async throws -> [MattermostCustomEmoji] {
        try await httpClient.post(
            "/emoji/search",
            body: MattermostEmojiSearchRequest(term: term, prefixOnly: prefixOnly)
        )
    }

    /// Autocompletes custom emoji names.
    public func autocompleteCustomEmoji(name: String) async throws -> [MattermostCustomEmoji] {
        try await httpClient.get(
            "/emoji/autocomplete",
            queryItems: [
                URLQueryItem(name: "name", value: name),
            ]
        )
    }

    /// Downloads a custom emoji image.
    public func customEmojiImage(id: String) async throws -> Data {
        try await httpClient.data("/emoji/\(id)/image")
    }
}
