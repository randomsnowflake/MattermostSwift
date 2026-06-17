import Foundation

// MARK: - File upload response, file info, and custom emoji models

/// Response returned after uploading one or more files.
public struct MattermostFileUploadResponse: Decodable, Equatable, Sendable {
    public let fileInfos: [MattermostFileInfo]
    public let clientIds: [String]?
}

/// Metadata for an uploaded Mattermost file.
public struct MattermostFileInfo: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let userId: String?
    public let postId: String?
    public let createAt: Int64?
    public let updateAt: Int64?
    public let deleteAt: Int64?
    public let name: String
    public let extensionName: String?
    public let size: Int64?
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let hasPreviewImage: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case postId
        case createAt
        case updateAt
        case deleteAt
        case name
        case extensionName = "extension"
        case size
        case mimeType
        case width
        case height
        case hasPreviewImage
    }
}

/// Metadata for a Mattermost custom emoji.
public struct MattermostCustomEmoji: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let creatorId: String?
    public let name: String
    public let createAt: Int64?
    public let updateAt: Int64?
    public let deleteAt: Int64?
}
