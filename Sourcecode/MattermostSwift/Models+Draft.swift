import Foundation

// MARK: - Synced drafts

/// A server-backed Mattermost composer draft.
///
/// Draft identity is the authenticated user plus `channelID` and optional
/// `rootID`. An empty `rootID` represents the channel composer; a non-empty
/// value represents that thread's reply composer.
public struct MattermostDraft: Codable, Equatable, Sendable {
    public let createAt: Int64
    public let updateAt: Int64
    public let deleteAt: Int64
    public let userID: String
    public let channelID: String
    public let rootID: String
    public let message: String
    public let type: String
    public let props: [String: MattermostJSONValue]?
    public let fileIDs: [String]?
    public let metadata: MattermostPostMetadata?
    public let priority: [String: MattermostJSONValue]?

    public var createdAt: Date { Date(mattermostMilliseconds: createAt) }
    public var updatedAt: Date { Date(mattermostMilliseconds: updateAt) }

    enum CodingKeys: String, CodingKey {
        case createAt
        case updateAt
        case deleteAt
        case userID = "userId"
        case channelID = "channelId"
        case rootID = "rootId"
        case message
        case type
        case props
        case fileIDs = "fileIds"
        case metadata
        case priority
    }
}

/// The editable fields accepted by Mattermost's synced-draft upsert endpoint.
public struct MattermostDraftUpsertRequest: Codable, Equatable, Sendable {
    public let channelID: String
    public let rootID: String
    public let message: String
    public let type: String
    public let props: [String: MattermostJSONValue]?
    public let fileIDs: [String]?
    public let priority: [String: MattermostJSONValue]?

    public init(
        channelID: String,
        rootID: String = "",
        message: String,
        type: String = "",
        props: [String: MattermostJSONValue]? = nil,
        fileIDs: [String]? = nil,
        priority: [String: MattermostJSONValue]? = nil
    ) {
        self.channelID = channelID
        self.rootID = rootID
        self.message = message
        self.type = type
        self.props = props
        self.fileIDs = fileIDs
        self.priority = priority
    }

    enum CodingKeys: String, CodingKey {
        case channelID = "channelId"
        case rootID = "rootId"
        case message
        case type
        case props
        case fileIDs = "fileIds"
        case priority
    }
}
