import Foundation
import Testing
@testable import MattermostSwift

@MainActor
@Test
func storeUpsertsUsersAndStatuses() throws {
    let store = try MattermostStore(inMemory: true)
    let user = MattermostUser(
        id: "user-1",
        username: "alice",
        email: "old@example.com",
        firstName: "Johannes",
        lastName: nil,
        nickname: nil,
        position: nil,
        locale: "en",
        timezone: nil
    )
    let updatedUser = MattermostUser(
        id: "user-1",
        username: "alice",
        email: "new@example.com",
        firstName: "Johannes",
        lastName: "Leimbach",
        nickname: nil,
        position: nil,
        locale: "de",
        timezone: nil
    )
    let status = MattermostUserStatus(
        userId: "user-1",
        status: "online",
        manual: false,
        lastActivityAt: 123,
        activeChannel: "channel-1",
        dndEndTime: nil
    )
    let team = MattermostTeam(
        id: "team-1",
        name: "engineering",
        displayName: "Engineering",
        description: "Old description",
        type: "O"
    )
    let updatedTeam = MattermostTeam(
        id: "team-1",
        name: "engineering",
        displayName: "Engineering Team",
        description: "New description",
        type: "O"
    )

    try store.upsert(user: user)
    try store.upsert(user: updatedUser)
    try store.upsert(status: status)
    try store.upsert(team: team)
    try store.upsert(team: updatedTeam)
    try store.save()

    let users = try store.cachedUsers()
    let teams = try store.cachedTeams()
    let cachedUser = try #require(try store.cachedUser(id: "user-1"))
    let cachedStatus = try #require(try store.cachedUserStatus(userID: "user-1"))
    let cachedTeam = try #require(try store.cachedTeam(id: "team-1"))

    #expect(users.count == 1)
    #expect(teams.count == 1)
    #expect(cachedUser.email == "new@example.com")
    #expect(cachedUser.lastName == "Leimbach")
    #expect(cachedStatus.status == "online")
    #expect(cachedStatus.activeChannel == "channel-1")
    #expect(cachedTeam.displayName == "Engineering Team")
    #expect(cachedTeam.descriptionText == "New description")
}

@MainActor
@Test
func storeCachesChannelsPostsAndThreads() throws {
    let store = try MattermostStore(inMemory: true)
    let channel = MattermostChannel(
        id: "channel-1",
        createAt: 1,
        updateAt: 1,
        teamId: "team-1",
        name: "town-square",
        displayName: "Town Square",
        type: "O",
        header: nil,
        purpose: nil,
        deleteAt: nil
    )
    let root = MattermostPost(
        id: "post-root",
        createAt: 1,
        updateAt: 1,
        editAt: 0,
        deleteAt: 0,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "root",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil
    )
    let reply = MattermostPost(
        id: "post-reply",
        createAt: 2,
        updateAt: 2,
        editAt: 0,
        deleteAt: 0,
        userId: "user-2",
        channelId: "channel-1",
        rootId: "post-root",
        originalId: nil,
        message: "reply",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: ["file-1"],
        hasReactions: true,
        props: [
            "mmswift": .object([
                "source": .string("store-test"),
                "ok": .bool(true),
            ]),
        ],
        metadata: [
            "priority": .object([
                "requested_ack": .bool(false),
            ]),
        ]
    )
    let list = MattermostPostList(
        order: ["post-reply", "post-root"],
        posts: [
            root.id: root,
            reply.id: reply,
        ],
        nextPostId: nil,
        prevPostId: nil,
        hasNext: nil
    )

    try store.upsert(channel: channel)
    try store.upsert(postList: list)
    try store.save()

    let cachedChannels = try store.cachedChannels(teamID: "team-1")
    let cachedPosts = try store.cachedPosts(channelID: "channel-1")
    let thread = try store.cachedThread(rootID: "post-root")

    #expect(cachedChannels.map(\.id) == ["channel-1"])
    #expect(cachedPosts.map(\.id) == ["post-reply", "post-root"])
    #expect(thread.map(\.id) == ["post-root", "post-reply"])
    #expect(try store.cachedTimeline(.channel(id: "channel-1")).map(\.id) == ["post-reply", "post-root"])
    #expect(try store.cachedTimeline(.thread(rootPostID: "post-root")).map(\.id) == ["post-root", "post-reply"])
    let cachedReply = try #require(try store.cachedPost(id: "post-reply"))
    #expect(cachedReply.fileIds == ["file-1"])
    #expect(try cachedReply.decodedProps()?["mmswift"] == .object([
        "source": .string("store-test"),
        "ok": .bool(true),
    ]))
    #expect(try cachedReply.decodedMetadata()?["priority"] == .object([
        "requested_ack": .bool(false),
    ]))
}

@MainActor
@Test
func storeCachesThreadState() throws {
    let store = try MattermostStore(inMemory: true)
    let user = MattermostUser(
        id: "user-1",
        username: "alice",
        email: nil,
        firstName: nil,
        lastName: nil,
        nickname: nil,
        position: nil,
        locale: nil,
        timezone: nil
    )
    let post = MattermostPost(
        id: "root-1",
        createAt: 10,
        updateAt: 20,
        editAt: 0,
        deleteAt: 0,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "root",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: false
    )
    let thread = MattermostThreadResponse(
        id: "root-1",
        replyCount: 4,
        lastReplyAt: 50,
        lastViewedAt: 30,
        participants: [user],
        post: post,
        unreadReplies: 2,
        unreadMentions: 1,
        isUrgent: true,
        deleteAt: 0
    )
    let list = MattermostThreadList(
        total: 1,
        totalUnreadThreads: 1,
        totalUnreadMentions: 1,
        totalUnreadUrgentMentions: 1,
        threads: [thread]
    )

    try store.upsert(threads: list, userID: "user-1", teamID: "team-1")
    try store.save()

    let cachedThread = try #require(try store.cachedThreadState(rootID: "root-1", userID: "user-1", teamID: "team-1"))
    let cachedUnreadThreads = try store.cachedThreadStates(userID: "user-1", teamID: "team-1", unreadOnly: true)
    let cachedPost = try #require(try store.cachedPost(id: "root-1"))
    let cachedUser = try #require(try store.cachedUser(id: "user-1"))

    #expect(cachedThread.replyCount == 4)
    #expect(cachedThread.unreadReplies == 2)
    #expect(cachedThread.unreadMentions == 1)
    #expect(cachedThread.isUnread)
    #expect(cachedThread.isUrgent)
    #expect(cachedThread.participantIds == ["user-1"])
    #expect(cachedUnreadThreads.map(\.rootId) == ["root-1"])
    #expect(cachedPost.message == "root")
    #expect(cachedUser.username == "alice")
}

@MainActor
@Test
func storePreservesEditedAndDeletedPostState() throws {
    let store = try MattermostStore(inMemory: true)
    let original = MattermostPost(
        id: "post-1",
        createAt: 10,
        updateAt: 10,
        editAt: 0,
        deleteAt: 0,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "original",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil
    )
    let deleted = MattermostPost(
        id: "post-1",
        createAt: 10,
        updateAt: 30,
        editAt: 20,
        deleteAt: 30,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "edited",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil
    )

    try store.upsert(post: original)
    try store.upsert(post: deleted)
    try store.save()

    let cached = try #require(try store.cachedPost(id: "post-1"))

    #expect(cached.message == "edited")
    #expect(cached.editAt == 20)
    #expect(cached.deleteAt == 30)
}

@MainActor
@Test
func storeMarksPostDeletedFromLiveEventWithoutEmbeddedPost() throws {
    let store = try MattermostStore(inMemory: true)
    let original = MattermostPost(
        id: "post-1",
        createAt: 10,
        updateAt: 10,
        editAt: 0,
        deleteAt: 0,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "original",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil
    )
    let olderActivePayload = MattermostPost(
        id: "post-1",
        createAt: 10,
        updateAt: 20,
        editAt: 0,
        deleteAt: 0,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "older active",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil
    )
    let deletion = MattermostLiveEvent(
        event: "post_deleted",
        data: [
            "post_id": .string("post-1"),
            "delete_at": .number(30),
        ],
        broadcast: nil,
        seq: 1
    )

    try store.upsert(post: original)
    let typedEvent = try store.apply(liveEvent: deletion)
    try store.upsert(post: olderActivePayload)
    try store.save()

    let cached = try #require(try store.cachedPost(id: "post-1"))

    #expect(typedEvent == .postDeleted(nil))
    #expect(cached.isDeleted)
    #expect(cached.deleteAt == 30)
    #expect(cached.message == "original")
}

@MainActor
@Test
func cachedTimelineCanFilterDeletedPosts() throws {
    let store = try MattermostStore(inMemory: true)
    let visible = MattermostPost(
        id: "post-visible",
        createAt: 20,
        updateAt: 20,
        editAt: 0,
        deleteAt: 0,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "visible",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil
    )
    let deleted = MattermostPost(
        id: "post-deleted",
        createAt: 10,
        updateAt: 30,
        editAt: 0,
        deleteAt: 30,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "deleted",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil
    )

    try store.upsert(post: visible)
    try store.upsert(post: deleted)
    try store.save()

    let allPosts = try store.cachedTimeline(.channel(id: "channel-1"))
    let visiblePosts = try store.cachedTimeline(.channel(id: "channel-1"), includeDeleted: false)

    #expect(allPosts.map(\.id) == ["post-visible", "post-deleted"])
    #expect(visiblePosts.map(\.id) == ["post-visible"])
}

@MainActor
@Test
func storeDoesNotApplyOlderPostPayloadOverNewerState() throws {
    let store = try MattermostStore(inMemory: true)
    let newer = MattermostPost(
        id: "post-1",
        createAt: 10,
        updateAt: 30,
        editAt: 30,
        deleteAt: 0,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "newer",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil
    )
    let older = MattermostPost(
        id: "post-1",
        createAt: 10,
        updateAt: 20,
        editAt: 20,
        deleteAt: 0,
        userId: "user-1",
        channelId: "channel-1",
        rootId: "",
        originalId: nil,
        message: "older",
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil
    )

    try store.upsert(post: newer)
    try store.upsert(post: older)
    try store.save()

    let cached = try #require(try store.cachedPost(id: "post-1"))

    #expect(cached.message == "newer")
    #expect(cached.editAt == 30)
}

@MainActor
@Test
func storeDoesNotResurrectDeletedChannelFromOlderPayload() throws {
    let store = try MattermostStore(inMemory: true)
    let deleted = MattermostChannel(
        id: "channel-1",
        createAt: 10,
        updateAt: 20,
        teamId: "team-1",
        name: "town-square",
        displayName: "Deleted Channel",
        type: "O",
        header: nil,
        purpose: nil,
        deleteAt: 40
    )
    let olderActive = MattermostChannel(
        id: "channel-1",
        createAt: 10,
        updateAt: 30,
        teamId: "team-1",
        name: "town-square",
        displayName: "Older Active Channel",
        type: "O",
        header: nil,
        purpose: nil,
        deleteAt: 0
    )

    try store.upsert(channel: deleted)
    try store.upsert(channel: olderActive)
    try store.save()

    let cached = try #require(try store.cachedChannel(id: "channel-1"))

    #expect(cached.displayName == "Deleted Channel")
    #expect(cached.deleteAt == 40)
}

@MainActor
@Test
func storeCachesChannelMembersAndUnreadState() throws {
    let store = try MattermostStore(inMemory: true)
    let member = MattermostChannelMember(
        channelId: "channel-1",
        userId: "user-1",
        roles: "channel_user",
        lastViewedAt: 10,
        msgCount: 20,
        mentionCount: 1,
        notifyProps: ["desktop": "mention"],
        lastUpdateAt: 30
    )
    let updatedMember = MattermostChannelMember(
        channelId: "channel-1",
        userId: "user-1",
        roles: "channel_user channel_admin",
        lastViewedAt: 40,
        msgCount: 22,
        mentionCount: 0,
        notifyProps: ["desktop": "all"],
        lastUpdateAt: 50
    )
    let unread = MattermostChannelUnread(
        teamId: "team-1",
        channelId: "channel-1",
        msgCount: 3,
        mentionCount: 2
    )

    try store.upsert(member: member)
    try store.upsert(member: updatedMember)
    try store.upsert(unread: unread, userID: "user-1")
    try store.save()

    let memberID = MattermostCachedChannelMember.cacheID(channelID: "channel-1", userID: "user-1")
    let unreadID = MattermostCachedChannelUnread.cacheID(channelID: "channel-1", userID: "user-1")
    let cachedMember = try #require(try store.cachedChannelMember(id: memberID))
    let cachedUnread = try #require(try store.cachedChannelUnread(id: unreadID))

    #expect(try store.cachedChannelMembers(userID: "user-1").count == 1)
    #expect(cachedMember.roles == "channel_user channel_admin")
    #expect(cachedMember.lastViewedAt == 40)
    #expect(cachedMember.notifyProps["desktop"] == "all")
    #expect(cachedMember.channelNotifyProps.desktop == "all")
    #expect(cachedUnread.teamId == "team-1")
    #expect(cachedUnread.msgCount == 3)
    #expect(cachedUnread.mentionCount == 2)
}

@MainActor
@Test
func storeCachesReactionsFilesAndCursors() throws {
    let store = try MattermostStore(inMemory: true)
    let reaction = MattermostReaction(
        userId: "user-1",
        postId: "post-1",
        emojiName: "smile",
        createAt: 123
    )
    let file = MattermostFileInfo(
        id: "file-1",
        userId: "user-1",
        postId: "post-1",
        createAt: 100,
        updateAt: 101,
        deleteAt: 0,
        name: "hello.txt",
        extensionName: "txt",
        size: 12,
        mimeType: "text/plain",
        width: nil,
        height: nil,
        hasPreviewImage: false
    )

    try store.upsert(reaction: reaction)
    try store.upsert(file: file)
    try store.setSyncCursor(scope: "channel:post-1", lastSyncAt: 100, lastItemID: "post-1")
    try store.setSyncCursor(scope: "channel:post-1", lastSyncAt: 200, lastItemID: "post-2")
    try store.save()

    let reactionID = MattermostCachedReaction.cacheID(
        userID: "user-1",
        postID: "post-1",
        emojiName: "smile"
    )
    let cursor = try #require(try store.cachedSyncCursor(scope: "channel:post-1"))

    #expect(try store.cachedReaction(id: reactionID)?.createAt == 123)
    #expect(try store.cachedFiles(postID: "post-1").map(\.id) == ["file-1"])
    #expect(cursor.lastSyncAt == 200)
    #expect(cursor.lastItemID == "post-2")
}

@MainActor
@Test
func storeAppliesLivePostAndReactionEvents() throws {
    let store = try MattermostStore(inMemory: true)
    let postJSON = """
    {
      "id": "post-1",
      "create_at": 1,
      "update_at": 2,
      "edit_at": 0,
      "delete_at": 0,
      "user_id": "user-1",
      "channel_id": "channel-1",
      "root_id": "",
      "message": "hello",
      "type": ""
    }
    """
    let reactionJSON = """
    {
      "user_id": "user-1",
      "post_id": "post-1",
      "emoji_name": "smile",
      "create_at": 3
    }
    """
    let posted = MattermostLiveEvent(
        event: "posted",
        data: ["post": .string(postJSON)],
        broadcast: nil,
        seq: 1
    )
    let reactionAdded = MattermostLiveEvent(
        event: "reaction_added",
        data: ["reaction": .string(reactionJSON)],
        broadcast: nil,
        seq: 2
    )
    let reactionRemoved = MattermostLiveEvent(
        event: "reaction_removed",
        data: ["reaction": .string(reactionJSON)],
        broadcast: nil,
        seq: 3
    )

    let postedEvent = try store.apply(liveEvent: posted)
    try store.apply(liveEvent: reactionAdded)
    try store.apply(liveEvent: reactionRemoved)
    try store.save()

    let reactionID = MattermostCachedReaction.cacheID(
        userID: "user-1",
        postID: "post-1",
        emojiName: "smile"
    )
    let cachedPost = try #require(try store.cachedPost(id: "post-1"))

    if case .posted(let post) = postedEvent {
        #expect(post.id == "post-1")
        #expect(post.message == "hello")
    } else {
        Issue.record("Expected a typed posted event.")
    }
    #expect(cachedPost.message == "hello")
    #expect(cachedPost.fileIds == [])
    #expect(try store.cachedReaction(id: reactionID) == nil)
}

@MainActor
@Test
func storeAppliesLiveChannelMemberAndUserEvents() throws {
    let store = try MattermostStore(inMemory: true)
    let channelJSON = """
    {
      "id": "channel-1",
      "team_id": "team-1",
      "name": "town-square",
      "display_name": "Town Square",
      "type": "O",
      "header": "old header",
      "purpose": "old purpose",
      "delete_at": 0
    }
    """
    let updatedChannelJSON = """
    {
      "id": "channel-1",
      "team_id": "team-1",
      "name": "town-square",
      "display_name": "Town Square Updated",
      "type": "O",
      "header": "new header",
      "purpose": "new purpose",
      "delete_at": 0
    }
    """
    let memberJSON = """
    {
      "channel_id": "channel-1",
      "user_id": "user-1",
      "roles": "channel_user",
      "last_viewed_at": 10,
      "msg_count": 20,
      "mention_count": 1,
      "notify_props": {"desktop": "all"},
      "last_update_at": 30
    }
    """
    let userJSON = """
    {
      "id": "user-1",
      "username": "renamed-user",
      "email": "user@example.com"
    }
    """
    let channelCreated = MattermostLiveEvent(
        event: "channel_created",
        data: ["channel": .string(channelJSON)],
        broadcast: nil,
        seq: 1
    )
    let channelUpdated = MattermostLiveEvent(
        event: "channel_updated",
        data: ["channel": .string(updatedChannelJSON)],
        broadcast: nil,
        seq: 2
    )
    let memberUpdated = MattermostLiveEvent(
        event: "channel_member_updated",
        data: ["channel_member": .string(memberJSON)],
        broadcast: nil,
        seq: 3
    )
    let userUpdated = MattermostLiveEvent(
        event: "user_updated",
        data: ["user": .string(userJSON)],
        broadcast: nil,
        seq: 4
    )
    let channelDeleted = MattermostLiveEvent(
        event: "channel_deleted",
        data: ["channel_id": .string("channel-1")],
        broadcast: nil,
        seq: 5
    )

    #expect(try channelCreated.typedEvent() == .channelCreated(try channelCreated.decodedChannel()))
    try store.apply(liveEvent: channelCreated)
    try store.apply(liveEvent: channelUpdated)
    try store.apply(liveEvent: memberUpdated)
    try store.apply(liveEvent: userUpdated)
    try store.apply(liveEvent: channelDeleted)
    try store.save()

    let cachedChannel = try #require(try store.cachedChannel(id: "channel-1"))
    let cachedMember = try #require(try store.cachedChannelMember(channelID: "channel-1", userID: "user-1"))
    let cachedUser = try #require(try store.cachedUser(id: "user-1"))

    #expect(cachedChannel.displayName == "Town Square Updated")
    #expect((cachedChannel.deleteAt ?? 0) > 0)
    #expect(cachedMember.notifyProps["desktop"] == "all")
    #expect(cachedUser.username == "renamed-user")
}

@Test
func reconnectPolicyCalculatesBackoffAndStopsAtLimit() {
    let policy = MattermostLiveEventReconnectPolicy(
        initialDelaySeconds: 0.5,
        maxDelaySeconds: 2,
        multiplier: 2,
        maxRetries: 2
    )

    #expect(policy.canRetry(attempt: 0))
    #expect(policy.canRetry(attempt: 1))
    #expect(!policy.canRetry(attempt: 2))
    #expect(policy.delay(for: 0) == .milliseconds(500))
    #expect(policy.delay(for: 1) == .seconds(1))
    #expect(policy.delay(for: 4) == .seconds(2))
}

@Test
func syncOptionsClampPageSettings() {
    let options = MattermostSyncOptions(postPageSize: 0, maxPostPages: 0)

    #expect(options.postPageSize == 1)
    #expect(options.maxPostPages == 1)
    #expect(options.includeChannelUsers)
    #expect(options.includeSidebarCategories)
    #expect(options.refreshUnreadForAllJoinedChannels)
}

@Test
func timelineTargetScopesAndRequestClampPageValues() {
    let channelTarget = MattermostTimelineTarget.channel(id: "channel-1")
    let threadTarget = MattermostTimelineTarget.thread(rootPostID: "post-1")
    let request = MattermostTimelineRequest(
        page: -1,
        perPage: -20,
        fromPost: "reply-1",
        fromCreateAt: 1_780_000_000_000,
        direction: .down,
        skipFetchThreads: true,
        collapsedThreads: true,
        collapsedThreadsExtended: true
    )

    #expect(channelTarget.cacheScope == "channel-posts:channel-1")
    #expect(threadTarget.cacheScope == "thread-posts:post-1")
    #expect(request.page == 0)
    #expect(request.perPage == 0)
    #expect(request.fromPost == "reply-1")
    #expect(request.fromCreateAt == 1_780_000_000_000)
    #expect(request.direction == .down)
    #expect(request.skipFetchThreads == true)
    #expect(request.collapsedThreads == true)
    #expect(request.collapsedThreadsExtended == true)
}

@Test
func liveSyncOptionsClampBackfillChannelLimit() {
    let options = MattermostLiveSyncOptions(maxBackfillChannels: -4)

    #expect(options.maxBackfillChannels == 0)
    #expect(options.backfillJoinedChannelPosts)
    #expect(!options.backfillAllJoinedChannelPosts)
    #expect(options.refreshUnreadOnChannelViewed)
    #expect(options.refreshSidebarCategoriesOnPreferenceChange)
    #expect(options.syncOptions.maxPostPages == 1)
}
