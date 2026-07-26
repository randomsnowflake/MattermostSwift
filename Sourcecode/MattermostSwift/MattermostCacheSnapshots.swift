import Foundation

/// Immutable, sendable representation of a cached user.
/// Create snapshots through `MattermostStore`; never retain a managed SwiftData object for
/// background work.
public struct MattermostCachedUserSnapshot: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let nickname: String?
    public let position: String?
    public let locale: String?
    public let lastPictureUpdate: Int64?

    @MainActor init(_ cached: MattermostCachedUser) {
        id = cached.id
        username = cached.username
        email = cached.email
        firstName = cached.firstName
        lastName = cached.lastName
        nickname = cached.nickname
        position = cached.position
        locale = cached.locale
        lastPictureUpdate = cached.lastPictureUpdate
    }
}

/// Immutable, sendable representation of a cached channel.
public struct MattermostCachedChannelSnapshot: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let createAt: Int64?
    public let updateAt: Int64?
    public let teamID: String?
    public let name: String
    public let displayName: String
    public let type: String
    public let header: String?
    public let purpose: String?
    public let deleteAt: Int64?
    public let totalMsgCount: Int64?
    public let totalMsgCountRoot: Int64?
    public let lastPostAt: Int64?
    public let lastRootPostAt: Int64?

    @MainActor init(_ cached: MattermostCachedChannel) {
        id = cached.id
        createAt = cached.createAt
        updateAt = cached.updateAt
        teamID = cached.teamId
        name = cached.name
        displayName = cached.displayName
        type = cached.type
        header = cached.header
        purpose = cached.purpose
        deleteAt = cached.deleteAt
        totalMsgCount = cached.totalMsgCount
        totalMsgCountRoot = cached.totalMsgCountRoot
        lastPostAt = cached.lastPostAt
        lastRootPostAt = cached.lastRootPostAt
    }
}

/// Immutable, sendable representation of a cached post.
public struct MattermostCachedPostSnapshot: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let createAt: Int64
    public let updateAt: Int64
    public let editAt: Int64
    public let deleteAt: Int64
    public let userID: String
    public let channelID: String
    public let rootID: String
    public let originalID: String?
    public let message: String
    public let type: String
    public let hashtags: String?
    public let pendingPostID: String?
    public let fileIDs: [String]
    public let hasReactions: Bool?
    /// The cached post props exactly as stored JSON.
    ///
    /// Call ``decodedProps()`` only when the typed values are needed.
    public let propsJSON: String?
    /// The cached post metadata exactly as stored JSON.
    ///
    /// Call ``decodedMetadata()`` only when typed file or reaction metadata is needed.
    public let metadataJSON: String?

    @MainActor init(_ cached: MattermostCachedPost) {
        id = cached.id
        createAt = cached.createAt
        updateAt = cached.updateAt
        editAt = cached.editAt
        deleteAt = cached.deleteAt
        userID = cached.userId
        channelID = cached.channelId
        rootID = cached.rootId
        originalID = cached.originalId
        message = cached.message
        type = cached.type
        hashtags = cached.hashtags
        pendingPostID = cached.pendingPostId
        fileIDs = cached.fileIds
        hasReactions = cached.hasReactions
        propsJSON = cached.propsJSON
        metadataJSON = cached.metadataJSON
    }

    /// Decodes the raw props JSON on demand, preserving arbitrary Mattermost keys.
    ///
    /// - Returns: The post's property bag, or `nil` when no props were cached.
    /// - Throws: A decoding error when ``propsJSON`` is not a JSON object whose values
    ///   can be represented by ``MattermostJSONValue``.
    public func decodedProps() throws -> [String: MattermostJSONValue]? {
        guard let propsJSON else {
            return nil
        }

        return try JSONDecoder().decode(
            [String: MattermostJSONValue].self,
            from: Data(propsJSON.utf8)
        )
    }

    /// Decodes typed file and reaction metadata from the raw metadata JSON on demand.
    ///
    /// - Returns: Typed metadata, or `nil` when no metadata was cached.
    /// - Throws: A decoding error when ``metadataJSON`` does not match
    ///   ``MattermostPostMetadata``.
    public func decodedMetadata() throws -> MattermostPostMetadata? {
        guard let metadataJSON else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(
            MattermostPostMetadata.self,
            from: Data(metadataJSON.utf8)
        )
    }
}
