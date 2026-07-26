import Foundation

// MARK: - File upload response, file info, and custom emoji models

/// Response returned after uploading one or more files.
public struct MattermostFileUploadResponse: Decodable, Equatable, Sendable {
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
public struct MattermostFileInfo: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let userID: String?
    public let postID: String?
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
        hasPreviewImage: Bool?
    ) {
        self.id = id
        self.userID = userID
        self.postID = postID
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

/// Metadata for a Mattermost custom emoji.
public struct MattermostCustomEmoji: Decodable, Equatable, Hashable, Sendable, Identifiable {
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
