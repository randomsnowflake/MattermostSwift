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

/// SwiftData row containing the cached profile fields for a Mattermost user.
///
/// Instances returned by ``MattermostStore`` belong to its main context and main-actor
/// isolation. Use ``MattermostCachedUserSnapshot`` when the value must cross actors.
// Do not conform to Sendable — see MattermostCacheSnapshots.
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

/// SwiftData row containing the latest cached presence state for one user.
///
/// The unique identity is `userId`. Mutate and retain managed instances only on the
/// ``MattermostStore`` main actor.
// Do not conform to Sendable — see MattermostCacheSnapshots.
@Model
public final class MattermostCachedUserStatus {
    @Attribute(.unique) public var userId: String = ""
    public var status: String = ""
    public var manual: Bool?
    public var lastActivityAt: Int64?
    public var activeChannel: String?
    public var dndEndTime: Int64?

    /// Creates a cache status row, primarily for applying live presence events.
    public init(
        userID: String,
        status: MattermostUserStatusValue,
        manual: Bool? = nil,
        lastActivityAt: Int64? = nil,
        activeChannel: String? = nil,
        dndEndTime: Int64? = nil
    ) {
        self.userId = userID
        self.status = status.rawValue
        self.manual = manual
        self.lastActivityAt = lastActivityAt
        self.activeChannel = activeChannel
        self.dndEndTime = dndEndTime
    }

    @available(*, deprecated, message: "Use init(userID:status:manual:lastActivityAt:activeChannel:dndEndTime:)")
    public convenience init(
        userId: String,
        status: String,
        manual: Bool? = nil,
        lastActivityAt: Int64? = nil,
        activeChannel: String? = nil,
        dndEndTime: Int64? = nil
    ) {
        self.init(
            userID: userId,
            status: MattermostUserStatusValue(rawValue: status),
            manual: manual,
            lastActivityAt: lastActivityAt,
            activeChannel: activeChannel,
            dndEndTime: dndEndTime
        )
    }

    init(_ status: MattermostUserStatus) {
        userId = status.userID
        self.status = status.status.rawValue
        manual = status.manual
        lastActivityAt = status.lastActivityAt
        activeChannel = status.activeChannel
        dndEndTime = status.dndEndTime
    }

    func apply(_ status: MattermostUserStatus) {
        self.status = status.status.rawValue
        manual = status.manual
        lastActivityAt = status.lastActivityAt
        activeChannel = status.activeChannel
        dndEndTime = status.dndEndTime
    }
}

/// SwiftData row containing cached Mattermost team metadata.
///
/// Instances are managed by the ``MattermostStore`` main context.
// Do not conform to Sendable — see MattermostCacheSnapshots.
@Model
public final class MattermostCachedTeam {
    @Attribute(.unique) public var id: String = ""
    public var name: String = ""
    public var displayName: String = ""
    /// The team's server `description` value.
    ///
    /// The property is named `descriptionText` to avoid colliding with Swift description APIs.
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

/// SwiftData row containing cached channel metadata and deletion state.
///
/// Channel updates use server timestamps so an older payload can't overwrite a newer edit or
/// resurrect a deleted channel. A positive `deleteAt` is a tombstone; normal
/// ``MattermostStore`` channel readers hide tombstones unless `includeDeleted` is `true`.
// Do not conform to Sendable — see MattermostCacheSnapshots.
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
    public var totalMsgCount: Int64?
    public var totalMsgCountRoot: Int64?
    public var lastPostAt: Int64?
    public var lastRootPostAt: Int64?

    init(_ channel: MattermostChannel) {
        id = channel.id
        createAt = channel.createAt
        updateAt = channel.updateAt
        teamId = channel.teamID
        name = channel.name
        displayName = channel.displayName
        type = channel.type.rawValue
        header = channel.header
        purpose = channel.purpose
        deleteAt = channel.deleteAt
        totalMsgCount = channel.totalMsgCount
        totalMsgCountRoot = channel.totalMsgCountRoot
        lastPostAt = channel.lastPostAt
        lastRootPostAt = channel.lastRootPostAt
    }

    func apply(_ channel: MattermostChannel) {
        guard shouldApply(channel) else {
            return
        }

        createAt = channel.createAt
        updateAt = channel.updateAt
        teamId = channel.teamID
        name = channel.name
        displayName = channel.displayName
        type = channel.type.rawValue
        header = channel.header
        purpose = channel.purpose
        deleteAt = channel.deleteAt
        totalMsgCount = channel.totalMsgCount
        totalMsgCountRoot = channel.totalMsgCountRoot
        lastPostAt = channel.lastPostAt
        lastRootPostAt = channel.lastRootPostAt
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

/// SwiftData row containing one user's membership and read state in one channel.
///
/// `id` is the stable channel/user composite key produced by
/// ``cacheID(channelID:userID:)``. Instances are managed by the ``MattermostStore`` main
/// context.
// Do not conform to Sendable — see MattermostCacheSnapshots.
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
    public var msgCountRoot: Int?
    public var mentionCountRoot: Int?
    public var notifyProps: [String: String] = [:]
    public var lastUpdateAt: Int64?

    /// A typed view of common notification keys that preserves unknown raw server values.
    public var channelNotifyProps: MattermostChannelNotifyProps {
        MattermostChannelNotifyProps(notifyProps)
    }

    init(_ member: MattermostChannelMember) {
        id = Self.cacheID(channelID: member.channelID, userID: member.userID)
        channelId = member.channelID
        userId = member.userID
        roles = member.roles
        lastViewedAt = member.lastViewedAt
        msgCount = member.msgCount
        mentionCount = member.mentionCount
        msgCountRoot = member.msgCountRoot
        mentionCountRoot = member.mentionCountRoot
        notifyProps = member.notifyProps ?? [:]
        lastUpdateAt = member.lastUpdateAt
    }

    /// Returns the stable composite identity for a channel membership.
    public static func cacheID(channelID: String, userID: String) -> String {
        "\(channelID):\(userID)"
    }

    func apply(_ member: MattermostChannelMember) {
        channelId = member.channelID
        userId = member.userID
        roles = member.roles
        lastViewedAt = member.lastViewedAt
        msgCount = member.msgCount
        mentionCount = member.mentionCount
        msgCountRoot = member.msgCountRoot
        mentionCountRoot = member.mentionCountRoot
        notifyProps = member.notifyProps ?? [:]
        lastUpdateAt = member.lastUpdateAt
    }
}

/// SwiftData row containing server-computed unread counts for one user and channel.
///
/// `id` is the stable channel/user composite key produced by
/// ``cacheID(channelID:userID:)``. Root counters support collapsed reply threads.
// Do not conform to Sendable — see MattermostCacheSnapshots.
@Model
public final class MattermostCachedChannelUnread {
    #Index<MattermostCachedChannelUnread>([\.userId])
    @Attribute(.unique) public var id: String = ""
    public var teamId: String?
    public var channelId: String = ""
    public var userId: String = ""
    public var msgCount: Int = 0
    public var mentionCount: Int = 0
    public var msgCountRoot: Int?
    public var mentionCountRoot: Int?

    init(_ unread: MattermostChannelUnread, userID: String) {
        id = Self.cacheID(channelID: unread.channelID, userID: userID)
        teamId = unread.teamID
        channelId = unread.channelID
        self.userId = userID
        msgCount = unread.msgCount
        mentionCount = unread.mentionCount
        msgCountRoot = unread.msgCountRoot
        mentionCountRoot = unread.mentionCountRoot
    }

    /// Returns the stable composite identity for one user's channel unread state.
    public static func cacheID(channelID: String, userID: String) -> String {
        "\(channelID):\(userID)"
    }

    func apply(_ unread: MattermostChannelUnread, userID: String) {
        teamId = unread.teamID
        channelId = unread.channelID
        self.userId = userID
        msgCount = unread.msgCount
        mentionCount = unread.mentionCount
        msgCountRoot = unread.msgCountRoot
        mentionCountRoot = unread.mentionCountRoot
    }
}

/// SwiftData row containing one user's thread-inbox state for a root post and team.
///
/// This is per-user state, not the cached root/reply post collection. Use
/// ``MattermostStore/cachedThread(rootID:includeDeleted:)`` to read the posts themselves.
// Do not conform to Sendable — see MattermostCacheSnapshots.
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
    /// User IDs for the participant profiles delivered with the thread response.
    public var participantIds: [String] = []

    /// Whether the cached state has unread replies or mentions.
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

    /// Returns the stable team/user/root-post composite identity for thread state.
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

/// SwiftData row containing a cached Mattermost post and its deletion tombstone.
///
/// Updates are server-timestamp last-write-wins. `propsJSON` and `metadataJSON` preserve
/// arbitrary server JSON; prefer ``decodedProps()`` and ``decodedMetadata()`` over parsing those
/// storage strings directly. Instances belong to the ``MattermostStore`` main context; use
/// ``MattermostCachedPostSnapshot`` when values must cross actors.
// Do not conform to Sendable — see MattermostCacheSnapshots.
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
    /// Lossless JSON storage for arbitrary post props.
    ///
    /// Use ``decodedProps()`` for typed access.
    public var propsJSON: String?
    /// Lossless JSON storage for arbitrary post metadata.
    ///
    /// Use ``decodedMetadata()`` for typed access.
    public var metadataJSON: String?

    init(_ post: MattermostPost, propsJSON: String?, metadataJSON: String?) {
        id = post.id
        createAt = post.createAt
        updateAt = post.updateAt
        editAt = post.editAt
        deleteAt = post.deleteAt
        userId = post.userID
        channelId = post.channelID
        rootId = post.rootID
        originalId = post.originalID
        message = post.message
        type = post.type.rawValue
        hashtags = post.hashtags
        pendingPostId = post.pendingPostID
        fileIds = post.fileIDs ?? []
        hasReactions = post.hasReactions
        self.propsJSON = propsJSON
        self.metadataJSON = metadataJSON
    }

    /// Encodes a tolerant Mattermost JSON dictionary for persistent string storage.
    public static func encodedJSON(_ value: [String: MattermostJSONValue]?) throws -> String? {
        guard let value else {
            return nil
        }

        let data = try mattermostCachedPostEncoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    /// Decodes ``propsJSON`` into tolerant Mattermost JSON values.
    public func decodedProps() throws -> [String: MattermostJSONValue]? {
        try Self.decodedJSON(propsJSON)
    }

    /// Decodes ``metadataJSON`` into tolerant Mattermost JSON values.
    public func decodedMetadata() throws -> [String: MattermostJSONValue]? {
        try Self.decodedJSON(metadataJSON)
    }

    /// Whether this row is a deletion tombstone.
    public var isDeleted: Bool {
        deleteAt > 0
    }

    func apply(_ post: MattermostPost) throws {
        guard shouldApply(post) else {
            return
        }

        let propsJSON = try Self.encodedJSON(post.props)
        let metadataJSON = try Self.encodedJSON(post.rawMetadata)
        createAt = post.createAt
        updateAt = post.updateAt
        editAt = post.editAt
        deleteAt = post.deleteAt
        userId = post.userID
        channelId = post.channelID
        rootId = post.rootID
        originalId = post.originalID
        message = post.message
        type = post.type.rawValue
        hashtags = post.hashtags
        pendingPostId = post.pendingPostID
        fileIds = post.fileIDs ?? []
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

/// SwiftData row containing one user's emoji reaction to one post.
///
/// `id` is the stable post/user/emoji composite key produced by
/// ``cacheID(userID:postID:emojiName:)``.
// Do not conform to Sendable — see MattermostCacheSnapshots.
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
            userID: reaction.userID,
            postID: reaction.postID,
            emojiName: reaction.emojiName
        )
        userId = reaction.userID
        postId = reaction.postID
        emojiName = reaction.emojiName
        createAt = reaction.createAt
    }

    /// Returns the stable composite identity for a reaction.
    public static func cacheID(userID: String, postID: String, emojiName: String) -> String {
        "\(postID):\(userID):\(emojiName)"
    }

    func apply(_ reaction: MattermostReaction) {
        userId = reaction.userID
        postId = reaction.postID
        emojiName = reaction.emojiName
        createAt = reaction.createAt
    }
}

/// SwiftData row containing cached metadata for an uploaded Mattermost file.
///
/// This model stores metadata only; file bytes remain outside the SwiftData cache.
// Do not conform to Sendable — see MattermostCacheSnapshots.
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
    /// The filename extension reported by Mattermost.
    ///
    /// The property is named `extensionName` because `extension` is a Swift keyword.
    public var extensionName: String?
    public var size: Int64?
    public var mimeType: String?
    public var width: Int?
    public var height: Int?
    public var hasPreviewImage: Bool?

    init(_ file: MattermostFileInfo) {
        id = file.id
        userId = file.userID
        postId = file.postID
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
        userId = file.userID
        postId = file.postID
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

/// SwiftData row containing a user/team sidebar category and its ordered channel IDs.
///
/// Instances are managed by the ``MattermostStore`` main context.
// Do not conform to Sendable — see MattermostCacheSnapshots.
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
        userId = category.userID
        teamId = category.teamID
        displayName = category.displayName
        type = category.type.rawValue
        sortOrder = category.sortOrder
        channelIds = category.channelIDs
        sorting = category.sorting?.rawValue
        muted = category.muted
        collapsed = category.collapsed
    }

    func apply(_ category: MattermostSidebarCategory) {
        userId = category.userID
        teamId = category.teamID
        displayName = category.displayName
        type = category.type.rawValue
        sortOrder = category.sortOrder
        channelIds = category.channelIDs
        sorting = category.sorting?.rawValue
        muted = category.muted
        collapsed = category.collapsed
    }
}

// Canonical public identifier spelling is bridged to the original persisted
// SwiftData fields so issue #75 does not rename columns or invalidate stores.
public extension MattermostCachedUserStatus {
    var userID: String {
        get { userId }
        set { userId = newValue }
    }
}

public extension MattermostCachedChannel {
    var teamID: String? {
        get { teamId }
        set { teamId = newValue }
    }
}

public extension MattermostCachedChannelMember {
    var channelID: String {
        get { channelId }
        set { channelId = newValue }
    }
    var userID: String {
        get { userId }
        set { userId = newValue }
    }
}

public extension MattermostCachedChannelUnread {
    var teamID: String? {
        get { teamId }
        set { teamId = newValue }
    }
    var channelID: String {
        get { channelId }
        set { channelId = newValue }
    }
    var userID: String {
        get { userId }
        set { userId = newValue }
    }
}

public extension MattermostCachedThread {
    var rootID: String {
        get { rootId }
        set { rootId = newValue }
    }
    var userID: String {
        get { userId }
        set { userId = newValue }
    }
    var teamID: String {
        get { teamId }
        set { teamId = newValue }
    }
    var participantIDs: [String] {
        get { participantIds }
        set { participantIds = newValue }
    }
}

public extension MattermostCachedPost {
    var userID: String {
        get { userId }
        set { userId = newValue }
    }
    var channelID: String {
        get { channelId }
        set { channelId = newValue }
    }
    var rootID: String {
        get { rootId }
        set { rootId = newValue }
    }
    var originalID: String? {
        get { originalId }
        set { originalId = newValue }
    }
    var pendingPostID: String? {
        get { pendingPostId }
        set { pendingPostId = newValue }
    }
    var fileIDs: [String] {
        get { fileIds }
        set { fileIds = newValue }
    }
}

public extension MattermostCachedReaction {
    var userID: String {
        get { userId }
        set { userId = newValue }
    }
    var postID: String {
        get { postId }
        set { postId = newValue }
    }
}

public extension MattermostCachedFile {
    var userID: String? {
        get { userId }
        set { userId = newValue }
    }
    var postID: String? {
        get { postId }
        set { postId = newValue }
    }
}

public extension MattermostCachedSidebarCategory {
    var userID: String? {
        get { userId }
        set { userId = newValue }
    }
    var teamID: String? {
        get { teamId }
        set { teamId = newValue }
    }
    var channelIDs: [String] {
        get { channelIds }
        set { channelIds = newValue }
    }
}

/// SwiftData row tracking the last successfully staged item for an incremental-sync scope.
///
/// Cursor timestamps are Mattermost server milliseconds. Advance a cursor only after all data
/// through that point has been staged, and save the data and cursor together.
// Do not conform to Sendable — see MattermostCacheSnapshots.
@Model
public final class MattermostSyncCursor {
    @Attribute(.unique) public var scope: String = ""
    public var lastSyncAt: Int64 = 0
    public var lastItemID: String?

    /// Creates a cursor for an exact cache scope.
    public init(scope: String, lastSyncAt: Int64, lastItemID: String? = nil) {
        self.scope = scope
        self.lastSyncAt = lastSyncAt
        self.lastItemID = lastItemID
    }
}

/// A server validator and the ordered cache membership for one conditional list request.
@Model
final class MattermostCacheETag {
    @Attribute(.unique) var scope: String = ""
    var value: String = ""
    var itemIDs: [String] = []

    init(scope: String, value: String, itemIDs: [String]) {
        self.scope = scope
        self.value = value
        self.itemIDs = itemIDs
    }
}
