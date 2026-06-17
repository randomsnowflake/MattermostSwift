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
}
