import Foundation

// MARK: - Files

extension MattermostClient {
    /// Uploads a file for later attachment to a post.
    public func uploadFile(
        channelID: String,
        filename: String,
        data: Data,
        contentType: String = "application/octet-stream",
        clientID: String? = nil
    ) async throws -> MattermostFileUploadResponse {
        var parts = [
            MattermostMultipartPart(
                name: "channel_id",
                filename: nil,
                contentType: nil,
                data: Data(channelID.utf8)
            ),
            MattermostMultipartPart(
                name: "files",
                filename: filename,
                contentType: contentType,
                data: data
            ),
        ]

        if let clientID, !clientID.isEmpty {
            parts.append(
                MattermostMultipartPart(
                    name: "client_ids",
                    filename: nil,
                    contentType: nil,
                    data: Data(clientID.utf8)
                )
            )
        }

        return try await httpClient.multipart("/files", parts: parts)
    }

    /// Uploads a staged local file without loading its contents into memory.
    /// The caller owns the file and may remove it after this method returns.
    public func uploadFile(
        channelID: String,
        filename: String,
        fileURL: URL,
        contentType: String = "application/octet-stream",
        clientID: String? = nil
    ) async throws -> MattermostFileUploadResponse {
        var parts = [
            MattermostMultipartPart(
                name: "channel_id",
                filename: nil,
                contentType: nil,
                data: Data(channelID.utf8)
            ),
        ]
        if let clientID, !clientID.isEmpty {
            parts.append(
                MattermostMultipartPart(
                    name: "client_ids",
                    filename: nil,
                    contentType: nil,
                    data: Data(clientID.utf8)
                )
            )
        }
        return try await httpClient.multipart(
            "/files",
            parts: parts,
            filePart: MattermostMultipartFilePart(
                name: "files",
                filename: filename,
                contentType: contentType,
                fileURL: fileURL
            )
        )
    }

    /// Loads metadata for a file by id.
    public func fileInfo(id: String) async throws -> MattermostFileInfo {
        try await httpClient.get("/files/\(id)/info")
    }

    /// Loads metadata for files attached to a post.
    public func fileInfos(postID: String) async throws -> [MattermostFileInfo] {
        try await httpClient.get("/posts/\(postID)/files/info")
    }

    /// Downloads raw bytes for a file by id.
    public func downloadFile(id: String) async throws -> Data {
        try await httpClient.data("/files/\(id)")
    }

    /// Downloads a file directly to disk without allocating its contents as `Data`.
    /// `maximumSize` rejects responses larger than the supplied byte limit.
    /// `progress` receives `(bytesReceived, bytesExpected)` from the URLSession
    /// delegate queue; `bytesExpected` is `-1` when the server sends no length.
    @discardableResult
    public func downloadFile(
        id: String,
        to destinationURL: URL,
        maximumSize: Int64? = nil,
        progress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> URL {
        try await httpClient.download(
            "/files/\(id)",
            to: destinationURL,
            maximumSize: maximumSize,
            progress: progress
        )
    }

    /// Searches files in a team. `terms` uses the server's search syntax; the
    /// official web app lists one channel's files with `"channel:<channelID>"`.
    public func searchFiles(
        teamID: String,
        terms: String,
        isOrSearch: Bool = false,
        includeDeletedChannels: Bool = true,
        page: Int = 0,
        perPage: Int = 60
    ) async throws -> MattermostFileSearchResults {
        try await httpClient.post(
            "/teams/\(teamID)/files/search",
            body: MattermostPostSearchRequest(
                terms: terms,
                isOrSearch: isOrSearch,
                timeZoneOffset: 0,
                includeDeletedChannels: includeDeletedChannels,
                page: page,
                perPage: perPage
            )
        )
    }

    /// Downloads the server-generated preview JPEG (about 1920 px wide) for an
    /// image file whose ``MattermostFileInfo/hasPreviewImage`` is true.
    public func filePreview(id: String) async throws -> Data {
        try await httpClient.data("/files/\(id)/preview")
    }

    /// Downloads the server-generated thumbnail JPEG (about 120x100 px) for an
    /// image file whose ``MattermostFileInfo/hasPreviewImage`` is true.
    public func fileThumbnail(id: String) async throws -> Data {
        try await httpClient.data("/files/\(id)/thumbnail")
    }
}
