import Foundation

/// Immutable, sendable representation of a cached user.
/// Create snapshots through `MattermostStore`; never retain a managed SwiftData object for
/// background work.
public struct MattermostCachedUserSnapshot: Equatable, Sendable, Identifiable {
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
public struct MattermostCachedChannelSnapshot: Equatable, Sendable, Identifiable {
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
    }
}

/// Immutable, sendable representation of a cached post.
public struct MattermostCachedPostSnapshot: Equatable, Sendable, Identifiable {
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
    public let props: [String: MattermostJSONValue]?
    public let metadata: [String: MattermostJSONValue]?

    @MainActor init(_ cached: MattermostCachedPost) throws {
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
        props = try cached.decodedProps()
        metadata = try cached.decodedMetadata()
    }
}
