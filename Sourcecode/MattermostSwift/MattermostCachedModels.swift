import Foundation
import SwiftData

/// Plain JSON coders reused for cached post props/metadata round-trips (no key strategy:
/// keys are arbitrary server JSON and must survive verbatim). Shared to avoid per-call allocation.
private let mattermostCachedPostEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()
private let mattermostCachedPostDecoder = JSONDecoder()

@Model
public final class MattermostCachedUser {
    @Attribute(.unique) public var id: String = ""
    public var username: String = ""
    public var email: String?
    public var firstName: String?
    public var lastName: String?
    public var nickname: String?
    public var position: String?
    public var locale: String?
    public var lastPictureUpdate: Int64?

    init(_ user: MattermostUser) {
        self.id = user.id
        self.username = user.username
        email = user.email
        firstName = user.firstName
        lastName = user.lastName
        nickname = user.nickname
        position = user.position
        locale = user.locale
        lastPictureUpdate = user.lastPictureUpdate
    }

    func apply(_ user: MattermostUser) {
        username = user.username
        email = user.email
        firstName = user.firstName
        lastName = user.lastName
        nickname = user.nickname
        position = user.position
        locale = user.locale
        lastPictureUpdate = user.lastPictureUpdate
    }
}

@Model
public final class MattermostCachedUserStatus {
    @Attribute(.unique) public var userId: String = ""
    public var status: String = ""
    public var manual: Bool?
    public var lastActivityAt: Int64?
    public var activeChannel: String?
    public var dndEndTime: Int64?

    public init(
        userId: String,
        status: String,
        manual: Bool? = nil,
        lastActivityAt: Int64? = nil,
        activeChannel: String? = nil,
        dndEndTime: Int64? = nil
    ) {
        self.userId = userId
        self.status = status
        self.manual = manual
        self.lastActivityAt = lastActivityAt
        self.activeChannel = activeChannel
        self.dndEndTime = dndEndTime
    }

    init(_ status: MattermostUserStatus) {
        userId = status.userId
        self.status = status.status
        manual = status.manual
        lastActivityAt = status.lastActivityAt
        activeChannel = status.activeChannel
        dndEndTime = status.dndEndTime
    }

    func apply(_ status: MattermostUserStatus) {
        self.status = status.status
        manual = status.manual
        lastActivityAt = status.lastActivityAt
        activeChannel = status.activeChannel
        dndEndTime = status.dndEndTime
    }
}

@Model
public final class MattermostCachedTeam {
    @Attribute(.unique) public var id: String = ""
    public var name: String = ""
    public var displayName: String = ""
    public var descriptionText: String?
    public var type: String?

    init(_ team: MattermostTeam) {
        id = team.id
        name = team.name
        displayName = team.displayName
        descriptionText = team.description
        type = team.type
    }

    func apply(_ team: MattermostTeam) {
        name = team.name
        displayName = team.displayName
        descriptionText = team.description
        type = team.type
    }
}

@Model
public final class MattermostCachedChannel {
    #Index<MattermostCachedChannel>([\.teamId])
    @Attribute(.unique) public var id: String = ""
    public var createAt: Int64?
    public var updateAt: Int64?
    public var teamId: String?
    public var name: String = ""
    public var displayName: String = ""
    public var type: String = ""
    public var header: String?
    public var purpose: String?
    public var deleteAt: Int64?

    init(_ channel: MattermostChannel) {
        id = channel.id
        createAt = channel.createAt
        updateAt = channel.updateAt
        teamId = channel.teamId
        name = channel.name
        displayName = channel.displayName
        type = channel.type
        header = channel.header
        purpose = channel.purpose
        deleteAt = channel.deleteAt
    }

    func apply(_ channel: MattermostChannel) {
        guard shouldApply(channel) else {
            return
        }

        createAt = channel.createAt
        updateAt = channel.updateAt
        teamId = channel.teamId
        name = channel.name
        displayName = channel.displayName
        type = channel.type
        header = channel.header
        purpose = channel.purpose
        deleteAt = channel.deleteAt
    }

    func markDeleted(at deletedAt: Int64) {
        deleteAt = max(deleteAt ?? 0, deletedAt)
    }

    var cacheTimestamp: Int64 {
        max(createAt ?? 0, updateAt ?? 0, deleteAt ?? 0)
    }

    private func shouldApply(_ channel: MattermostChannel) -> Bool {
        let incomingTimestamp = channel.cacheTimestamp
        guard incomingTimestamp > 0, cacheTimestamp > 0 else {
            return true
        }
        return incomingTimestamp >= cacheTimestamp
    }
}

@Model
public final class MattermostCachedChannelMember {
    #Index<MattermostCachedChannelMember>([\.userId])
    @Attribute(.unique) public var id: String = ""
    public var channelId: String = ""
    public var userId: String = ""
    public var roles: String?
    public var lastViewedAt: Int64?
    public var msgCount: Int?
    public var mentionCount: Int?
    public var notifyProps: [String: String] = [:]
    public var lastUpdateAt: Int64?

    public var channelNotifyProps: MattermostChannelNotifyProps {
        MattermostChannelNotifyProps(notifyProps)
    }

    init(_ member: MattermostChannelMember) {
        id = Self.cacheID(channelID: member.channelId, userID: member.userId)
        channelId = member.channelId
        userId = member.userId
        roles = member.roles
        lastViewedAt = member.lastViewedAt
        msgCount = member.msgCount
        mentionCount = member.mentionCount
        notifyProps = member.notifyProps ?? [:]
        lastUpdateAt = member.lastUpdateAt
    }

    public static func cacheID(channelID: String, userID: String) -> String {
        "\(channelID):\(userID)"
    }

    func apply(_ member: MattermostChannelMember) {
        channelId = member.channelId
        userId = member.userId
        roles = member.roles
        lastViewedAt = member.lastViewedAt
        msgCount = member.msgCount
        mentionCount = member.mentionCount
        notifyProps = member.notifyProps ?? [:]
        lastUpdateAt = member.lastUpdateAt
    }
}

@Model
public final class MattermostCachedChannelUnread {
    #Index<MattermostCachedChannelUnread>([\.userId])
    @Attribute(.unique) public var id: String = ""
    public var teamId: String?
    public var channelId: String = ""
    public var userId: String = ""
    public var msgCount: Int = 0
    public var mentionCount: Int = 0

    init(_ unread: MattermostChannelUnread, userID: String) {
        id = Self.cacheID(channelID: unread.channelId, userID: userID)
        teamId = unread.teamId
        channelId = unread.channelId
        self.userId = userID
        msgCount = unread.msgCount
        mentionCount = unread.mentionCount
    }

    public static func cacheID(channelID: String, userID: String) -> String {
        "\(channelID):\(userID)"
    }

    func apply(_ unread: MattermostChannelUnread, userID: String) {
        teamId = unread.teamId
        channelId = unread.channelId
        self.userId = userID
        msgCount = unread.msgCount
        mentionCount = unread.mentionCount
    }
}

@Model
public final class MattermostCachedThread {
    #Index<MattermostCachedThread>([\.userId, \.teamId])
    @Attribute(.unique) public var id: String = ""
    public var rootId: String = ""
    public var userId: String = ""
    public var teamId: String = ""
    public var replyCount: Int64 = 0
    public var lastReplyAt: Int64 = 0
    public var lastViewedAt: Int64 = 0
    public var unreadReplies: Int64 = 0
    public var unreadMentions: Int64 = 0
    public var isUrgent: Bool = false
    public var deleteAt: Int64 = 0
    public var participantIds: [String] = []

    public var isUnread: Bool {
        unreadReplies > 0 || unreadMentions > 0
    }

    init(_ thread: MattermostThreadResponse, userID: String, teamID: String) {
        id = Self.cacheID(rootID: thread.id, userID: userID, teamID: teamID)
        rootId = thread.id
        userId = userID
        self.teamId = teamID
        replyCount = thread.replyCount
        lastReplyAt = thread.lastReplyAt
        lastViewedAt = thread.lastViewedAt
        unreadReplies = thread.unreadReplies
        unreadMentions = thread.unreadMentions
        isUrgent = thread.isUrgent
        deleteAt = thread.deleteAt
        participantIds = thread.participants.map(\.id)
    }

    public static func cacheID(rootID: String, userID: String, teamID: String) -> String {
        "\(teamID):\(userID):\(rootID)"
    }

    func apply(_ thread: MattermostThreadResponse, userID: String, teamID: String) {
        guard shouldApply(thread) else {
            return
        }

        rootId = thread.id
        self.userId = userID
        self.teamId = teamID
        replyCount = thread.replyCount
        lastReplyAt = thread.lastReplyAt
        lastViewedAt = thread.lastViewedAt
        unreadReplies = thread.unreadReplies
        unreadMentions = thread.unreadMentions
        isUrgent = thread.isUrgent
        deleteAt = thread.deleteAt
        participantIds = thread.participants.map(\.id)
    }

    var cacheTimestamp: Int64 {
        max(lastReplyAt, lastViewedAt, deleteAt)
    }

    private func shouldApply(_ thread: MattermostThreadResponse) -> Bool {
        let incomingTimestamp = max(thread.lastReplyAt, thread.lastViewedAt, thread.deleteAt)
        guard incomingTimestamp > 0, cacheTimestamp > 0 else {
            return true
        }
        return incomingTimestamp >= cacheTimestamp
    }
}

@Model
public final class MattermostCachedPost {
    #Index<MattermostCachedPost>([\.channelId], [\.channelId, \.createAt], [\.rootId])
    @Attribute(.unique) public var id: String = ""
    public var createAt: Int64 = 0
    public var updateAt: Int64 = 0
    public var editAt: Int64 = 0
    public var deleteAt: Int64 = 0
    public var userId: String = ""
    public var channelId: String = ""
    public var rootId: String = ""
    public var originalId: String?
    public var message: String = ""
    public var type: String = ""
    public var hashtags: String?
    public var pendingPostId: String?
    public var fileIds: [String] = []
    public var hasReactions: Bool?
    public var propsJSON: String?
    public var metadataJSON: String?

    init(_ post: MattermostPost, propsJSON: String?, metadataJSON: String?) {
        id = post.id
        createAt = post.createAt
        updateAt = post.updateAt
        editAt = post.editAt
        deleteAt = post.deleteAt
        userId = post.userId
        channelId = post.channelId
        rootId = post.rootId
        originalId = post.originalId
        message = post.message
        type = post.type
        hashtags = post.hashtags
        pendingPostId = post.pendingPostId
        fileIds = post.fileIds ?? []
        hasReactions = post.hasReactions
        self.propsJSON = propsJSON
        self.metadataJSON = metadataJSON
    }

    public static func encodedJSON(_ value: [String: MattermostJSONValue]?) throws -> String? {
        guard let value else {
            return nil
        }

        let data = try mattermostCachedPostEncoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    public func decodedProps() throws -> [String: MattermostJSONValue]? {
        try Self.decodedJSON(propsJSON)
    }

    public func decodedMetadata() throws -> [String: MattermostJSONValue]? {
        try Self.decodedJSON(metadataJSON)
    }

    public var isDeleted: Bool {
        deleteAt > 0
    }

    func apply(_ post: MattermostPost) throws {
        guard shouldApply(post) else {
            return
        }

        let propsJSON = try Self.encodedJSON(post.props)
        let metadataJSON = try Self.encodedJSON(post.metadata)
        createAt = post.createAt
        updateAt = post.updateAt
        editAt = post.editAt
        deleteAt = post.deleteAt
        userId = post.userId
        channelId = post.channelId
        rootId = post.rootId
        originalId = post.originalId
        message = post.message
        type = post.type
        hashtags = post.hashtags
        pendingPostId = post.pendingPostId
        fileIds = post.fileIds ?? []
        hasReactions = post.hasReactions
        self.propsJSON = propsJSON
        self.metadataJSON = metadataJSON
    }

    var cacheTimestamp: Int64 {
        max(createAt, updateAt, editAt, deleteAt)
    }

    private static func decodedJSON(_ string: String?) throws -> [String: MattermostJSONValue]? {
        guard let string else {
            return nil
        }

        return try mattermostCachedPostDecoder.decode([String: MattermostJSONValue].self, from: Data(string.utf8))
    }

    func markDeleted(at deletedAt: Int64) {
        deleteAt = max(deleteAt, deletedAt)
    }

    private func shouldApply(_ post: MattermostPost) -> Bool {
        let incomingTimestamp = post.cacheTimestamp
        guard incomingTimestamp > 0, cacheTimestamp > 0 else {
            return true
        }
        return incomingTimestamp >= cacheTimestamp
    }
}

@Model
public final class MattermostCachedReaction {
    #Index<MattermostCachedReaction>([\.postId])
    @Attribute(.unique) public var id: String = ""
    public var userId: String = ""
    public var postId: String = ""
    public var emojiName: String = ""
    public var createAt: Int64?

    init(_ reaction: MattermostReaction) {
        id = Self.cacheID(
            userID: reaction.userId,
            postID: reaction.postId,
            emojiName: reaction.emojiName
        )
        userId = reaction.userId
        postId = reaction.postId
        emojiName = reaction.emojiName
        createAt = reaction.createAt
    }

    public static func cacheID(userID: String, postID: String, emojiName: String) -> String {
        "\(postID):\(userID):\(emojiName)"
    }

    func apply(_ reaction: MattermostReaction) {
        userId = reaction.userId
        postId = reaction.postId
        emojiName = reaction.emojiName
        createAt = reaction.createAt
    }
}

@Model
public final class MattermostCachedFile {
    #Index<MattermostCachedFile>([\.postId])
    @Attribute(.unique) public var id: String = ""
    public var userId: String?
    public var postId: String?
    public var createAt: Int64?
    public var updateAt: Int64?
    public var deleteAt: Int64?
    public var name: String = ""
    public var extensionName: String?
    public var size: Int64?
    public var mimeType: String?
    public var width: Int?
    public var height: Int?
    public var hasPreviewImage: Bool?

    init(_ file: MattermostFileInfo) {
        id = file.id
        userId = file.userId
        postId = file.postId
        createAt = file.createAt
        updateAt = file.updateAt
        deleteAt = file.deleteAt
        name = file.name
        extensionName = file.extensionName
        size = file.size
        mimeType = file.mimeType
        width = file.width
        height = file.height
        hasPreviewImage = file.hasPreviewImage
    }

    func apply(_ file: MattermostFileInfo) {
        userId = file.userId
        postId = file.postId
        createAt = file.createAt
        updateAt = file.updateAt
        deleteAt = file.deleteAt
        name = file.name
        extensionName = file.extensionName
        size = file.size
        mimeType = file.mimeType
        width = file.width
        height = file.height
        hasPreviewImage = file.hasPreviewImage
    }
}

@Model
public final class MattermostCachedSidebarCategory {
    #Index<MattermostCachedSidebarCategory>([\.teamId])
    @Attribute(.unique) public var id: String = ""
    public var userId: String?
    public var teamId: String?
    public var displayName: String = ""
    public var type: String = ""
    public var sortOrder: Int?
    public var channelIds: [String] = []
    public var sorting: String?
    public var muted: Bool?
    public var collapsed: Bool?

    init(_ category: MattermostSidebarCategory) {
        id = category.id
        userId = category.userId
        teamId = category.teamId
        displayName = category.displayName
        type = category.type
        sortOrder = category.sortOrder
        channelIds = category.channelIds
        sorting = category.sorting
        muted = category.muted
        collapsed = category.collapsed
    }

    func apply(_ category: MattermostSidebarCategory) {
        userId = category.userId
        teamId = category.teamId
        displayName = category.displayName
        type = category.type
        sortOrder = category.sortOrder
        channelIds = category.channelIds
        sorting = category.sorting
        muted = category.muted
        collapsed = category.collapsed
    }
}

@Model
public final class MattermostSyncCursor {
    @Attribute(.unique) public var scope: String = ""
    public var lastSyncAt: Int64 = 0
    public var lastItemID: String?

    public init(scope: String, lastSyncAt: Int64, lastItemID: String? = nil) {
        self.scope = scope
        self.lastSyncAt = lastSyncAt
        self.lastItemID = lastItemID
    }
}
