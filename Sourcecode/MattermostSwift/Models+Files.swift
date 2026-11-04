import Foundation

// MARK: - File upload response, file info, and custom emoji models

/// Response returned after uploading one or more files.
public struct MattermostFileUploadResponse: Codable, Equatable, Sendable {
    public let fileInfos: [MattermostFileInfo]
    public let clientIDs: [String]?

    @available(*, deprecated, renamed: "clientIDs")
    public var clientIds: [String]? { clientIDs }

    enum CodingKeys: String, CodingKey {
        case fileInfos
        case clientIDs = "clientIds"
    }
}

/// Metadata for an uploaded Mattermost file.
public struct MattermostFileInfo: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let userID: String?
    public let postID: String?
    /// Present in file search results; post metadata omits it.
    public let channelID: String?
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
    /// Tiny JPEG (about 16x16) the server embeds in post metadata for images
    /// with a preview, meant as an instant blurred placeholder.
    public let miniPreview: Data?

    public init(
        id: String,
        userID: String?,
        postID: String?,
        createAt: Int64?,
        updateAt: Int64?,
        deleteAt: Int64?,
        name: String,
        extensionName: String?,
        size: Int64?,
        mimeType: String?,
        width: Int?,
        height: Int?,
        hasPreviewImage: Bool?,
        miniPreview: Data? = nil,
        channelID: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.postID = postID
        self.channelID = channelID
        self.createAt = createAt
        self.updateAt = updateAt
        self.deleteAt = deleteAt
        self.name = name
        self.extensionName = extensionName
        self.size = size
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.hasPreviewImage = hasPreviewImage
        self.miniPreview = miniPreview
    }

    @available(*, deprecated, message: "Use the ID-spelled initializer")
    public init(
        id: String,
        userId: String?,
        postId: String?,
        createAt: Int64?,
        updateAt: Int64?,
        deleteAt: Int64?,
        name: String,
        extensionName: String?,
        size: Int64?,
        mimeType: String?,
        width: Int?,
        height: Int?,
        hasPreviewImage: Bool?
    ) {
        self.init(
            id: id,
            userID: userId,
            postID: postId,
            createAt: createAt,
            updateAt: updateAt,
            deleteAt: deleteAt,
            name: name,
            extensionName: extensionName,
            size: size,
            mimeType: mimeType,
            width: width,
            height: height,
            hasPreviewImage: hasPreviewImage
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "userId"
        case postID = "postId"
        case channelID = "channelId"
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
        case miniPreview
    }

    @available(*, deprecated, renamed: "userID")
    public var userId: String? { userID }
    @available(*, deprecated, renamed: "postID")
    public var postId: String? { postID }

    public var createdAt: Date? { createAt.map(Date.init(mattermostMilliseconds:)) }
    public var updatedAt: Date? { updateAt.map(Date.init(mattermostMilliseconds:)) }
    public var deletedAt: Date? {
        guard let deleteAt, deleteAt > 0 else { return nil }
        return Date(mattermostMilliseconds: deleteAt)
    }
}

/// One page of `POST /teams/{team_id}/files/search`, newest first.
public struct MattermostFileSearchResults: Codable, Equatable, Sendable {
    public let order: [String]
    public let fileInfos: [String: MattermostFileInfo]
    public let nextFileInfoID: String?
    public let prevFileInfoID: String?

    public init(
        order: [String],
        fileInfos: [String: MattermostFileInfo],
        nextFileInfoID: String? = nil,
        prevFileInfoID: String? = nil
    ) {
        self.order = order
        self.fileInfos = fileInfos
        self.nextFileInfoID = nextFileInfoID
        self.prevFileInfoID = prevFileInfoID
    }

    public var orderedFiles: [MattermostFileInfo] {
        order.compactMap { fileInfos[$0] }
    }

    enum CodingKeys: String, CodingKey {
        case order
        case fileInfos
        case nextFileInfoID = "nextFileInfoId"
        case prevFileInfoID = "prevFileInfoId"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The server sends `null` rather than empty collections when nothing matches.
        order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        fileInfos = try container.decodeIfPresent([String: MattermostFileInfo].self, forKey: .fileInfos) ?? [:]
        nextFileInfoID = try container.decodeIfPresent(String.self, forKey: .nextFileInfoID)
        prevFileInfoID = try container.decodeIfPresent(String.self, forKey: .prevFileInfoID)
    }
}

/// Metadata for a Mattermost custom emoji.
public struct MattermostCustomEmoji: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let creatorID: String?
    public let name: String
    public let createAt: Int64?
    public let updateAt: Int64?
    public let deleteAt: Int64?

    @available(*, deprecated, renamed: "creatorID")
    public var creatorId: String? { creatorID }

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creatorId"
        case name
        case createAt
        case updateAt
        case deleteAt
    }

    public var createdAt: Date? { createAt.map(Date.init(mattermostMilliseconds:)) }
    public var updatedAt: Date? { updateAt.map(Date.init(mattermostMilliseconds:)) }
    public var deletedAt: Date? {
        guard let deleteAt, deleteAt > 0 else { return nil }
        return Date(mattermostMilliseconds: deleteAt)
    }
}
