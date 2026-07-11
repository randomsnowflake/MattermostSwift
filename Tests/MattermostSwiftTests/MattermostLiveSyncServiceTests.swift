import Foundation
import Testing
@testable import MattermostSwift

@Test
func oneShotCallbackIgnoresRepeatedInvocations() {
    let log = MattermostRequestLog()
    let callback = MattermostOneShotCallback<Int> { value in
        log.append("\(value)")
    }

    callback(1)
    callback(2)
    callback(3)

    #expect(log.values == ["1"])
}

@Test
func liveEventStreamFailureCapturesNSErrorAndUnderlyingNSErrorDetails() {
    let underlying = NSError(domain: NSPOSIXErrorDomain, code: 57)
    let error = NSError(
        domain: NSURLErrorDomain,
        code: NSURLErrorNetworkConnectionLost,
        userInfo: [
            NSUnderlyingErrorKey: underlying,
            NSLocalizedDescriptionKey: "The network connection was lost.",
        ]
    )

    let failure = MattermostLiveEventStreamFailure(error: error)

    #expect(failure.domain == NSURLErrorDomain)
    #expect(failure.code == NSURLErrorNetworkConnectionLost)
    #expect(failure.underlyingDomain == NSPOSIXErrorDomain)
    #expect(failure.underlyingCode == 57)
    #expect(failure.message == "The network connection was lost.")
}

@MainActor
@Test
func liveSyncRunsBackfillForEveryConnectingLifecycleEvent() async throws {
    let service = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "test-token"
    ).liveSyncService()
    let store = try MattermostStore(inMemory: true)
    var requestedTeamIDs: [String?] = []

    let stream = service.events(
        to: store,
        options: MattermostLiveSyncOptions(maxBackfillChannels: 1),
        lifecycleEvents: {
            AsyncThrowingStream { continuation in
                continuation.yield(.connecting(attempt: 0))
                continuation.yield(.reconnecting(attempt: 0, delay: .milliseconds(1)))
                continuation.yield(.connecting(attempt: 1))
                continuation.finish()
            }
        },
        backfill: { _, teamID, _, _ in
            requestedTeamIDs.append(teamID)
            return liveSyncBackfillResult(teamID: teamID ?? "team-1")
        }
    )

    var connectingAttempts: [Int] = []
    var backfillCount = 0
    var reconnectingAttempts: [Int] = []

    for try await event in stream {
        switch event {
        case .connecting(let attempt):
            connectingAttempts.append(attempt)
        case .backfilled:
            backfillCount += 1
        case .reconnecting(let attempt, _):
            reconnectingAttempts.append(attempt)
        default:
            break
        }
    }

    #expect(connectingAttempts == [0, 1])
    #expect(backfillCount == 2)
    #expect(reconnectingAttempts == [0])
    #expect(requestedTeamIDs == [nil, "team-1"])
}

@MainActor
@Test
func liveSyncEventsExposeConnectionStateForHostUI() async throws {
    let service = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "test-token"
    ).liveSyncService()
    let store = try MattermostStore(inMemory: true)

    let stream = service.events(
        to: store,
        options: MattermostLiveSyncOptions(maxBackfillChannels: 1),
        lifecycleEvents: {
            AsyncThrowingStream { continuation in
                continuation.yield(.connecting(attempt: 0))
                continuation.yield(.reconnecting(attempt: 0, delay: .milliseconds(250)))
                continuation.yield(.connecting(attempt: 1))
                continuation.finish()
            }
        },
        backfill: { _, teamID, _, _ in
            liveSyncBackfillResult(teamID: teamID ?? "team-1")
        }
    )

    var states: [MattermostLiveSyncConnectionState] = []
    for try await event in stream {
        if let state = event.connectionState {
            states.append(state)
        }
    }

    #expect(states == [
        .connecting(attempt: 0),
        .connected(teamID: "team-1", backfilledChannelCount: 0),
        .reconnecting(attempt: 0, delay: .milliseconds(250)),
        .connecting(attempt: 1),
        .connected(teamID: "team-1", backfilledChannelCount: 0),
    ])
    #expect(states.map(\.isRecovering) == [true, false, true, true, false])
}

@MainActor
@Test
func liveSyncEmitsBackfillFailureWithoutTerminating() async throws {
    struct BackfillFailure: LocalizedError, Equatable {
        let errorDescription: String? = "backfill failed for test"
    }

    let service = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "test-token"
    ).liveSyncService()
    let store = try MattermostStore(inMemory: true)

    let stream = service.events(
        to: store,
        options: MattermostLiveSyncOptions(maxBackfillChannels: 1),
        lifecycleEvents: {
            AsyncThrowingStream { continuation in
                continuation.yield(.connecting(attempt: 2))
                continuation.finish()
            }
        },
        backfill: { _, _, _, _ in
            throw BackfillFailure()
        }
    )

    // A backfill failure surfaces as a `.backfillFailed` event but the stream keeps running so a
    // later reconnect can retry; here the injected lifecycle finishes, so the stream ends cleanly.
    var states: [MattermostLiveSyncConnectionState] = []
    var failure: MattermostLiveSyncFailure?
    for try await event in stream {
        if let state = event.connectionState {
            states.append(state)
        }
        if case .backfillFailed(let emittedFailure) = event {
            failure = emittedFailure
        }
    }

    #expect(failure == MattermostLiveSyncFailure(
        attempt: 2,
        message: "backfill failed for test"
    ))
    #expect(states == [
        .connecting(attempt: 2),
        .failed(attempt: 2, message: "backfill failed for test"),
    ])
    #expect(states.map(\.isRecovering) == [true, false])
}

@MainActor
@Test
func liveSyncReconnectBackfillMergesPostsMissedWhileDisconnected() async throws {
    let service = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "test-token"
    ).liveSyncService()
    let store = try MattermostStore(inMemory: true)
    var backfillAttempts = 0

    let stream = service.events(
        to: store,
        options: MattermostLiveSyncOptions(channelIDs: ["channel-1"], maxBackfillChannels: 1),
        lifecycleEvents: {
            AsyncThrowingStream { continuation in
                continuation.yield(.connecting(attempt: 0))
                continuation.yield(.reconnecting(attempt: 0, delay: .milliseconds(1)))
                continuation.yield(.connecting(attempt: 1))
                continuation.finish()
            }
        },
        backfill: { store, teamID, _, _ in
            backfillAttempts += 1

            let post: MattermostPost
            switch backfillAttempts {
            case 1:
                post = liveSyncPost(
                    id: "before-disconnect",
                    channelID: "channel-1",
                    message: "synced before disconnect",
                    createAt: 100,
                    updateAt: 100
                )
            default:
                let cursor = try #require(try store.cachedSyncCursor(scope: "channel-posts:channel-1"))
                #expect(cursor.lastSyncAt == 100)
                post = liveSyncPost(
                    id: "missed-while-disconnected",
                    channelID: "channel-1",
                    message: "missed while disconnected",
                    createAt: 200,
                    updateAt: 210
                )
            }

            let postSync = try liveSyncStorePostSync(post, in: store)
            return liveSyncBackfillResult(
                teamID: teamID ?? "team-1",
                postSyncs: [postSync]
            )
        }
    )

    var backfilledPostIDs: [[String]] = []
    for try await event in stream {
        if case .backfilled(let result) = event {
            backfilledPostIDs.append(result.postSyncs.flatMap { $0.posts.map(\.id) })
        }
    }

    let cachedPost = try #require(try store.cachedPost(id: "missed-while-disconnected"))
    let cursor = try #require(try store.cachedSyncCursor(scope: "channel-posts:channel-1"))

    #expect(backfillAttempts == 2)
    #expect(backfilledPostIDs == [
        ["before-disconnect"],
        ["missed-while-disconnected"],
    ])
    #expect(cachedPost.message == "missed while disconnected")
    #expect(cursor.lastSyncAt == 210)
    #expect(cursor.lastItemID == "missed-while-disconnected")
}

@Test
func liveSyncBackfillChannelSelectionSupportsAllJoinedChannels() {
    let channels = [
        liveSyncChannel(id: "channel-1"),
        liveSyncChannel(id: "channel-2"),
        liveSyncChannel(id: "channel-3"),
    ]

    let capped = MattermostLiveSyncService.backfillChannelIDs(
        from: channels,
        options: MattermostLiveSyncOptions(maxBackfillChannels: 2)
    )
    let allJoined = MattermostLiveSyncService.backfillChannelIDs(
        from: channels,
        options: MattermostLiveSyncOptions(backfillAllJoinedChannelPosts: true, maxBackfillChannels: 0)
    )
    let disabled = MattermostLiveSyncService.backfillChannelIDs(
        from: channels,
        options: MattermostLiveSyncOptions(backfillJoinedChannelPosts: false, backfillAllJoinedChannelPosts: true)
    )
    let explicit = MattermostLiveSyncService.backfillChannelIDs(
        from: channels,
        options: MattermostLiveSyncOptions(channelIDs: ["explicit-1", "explicit-2"], backfillAllJoinedChannelPosts: true, maxBackfillChannels: 1)
    )

    #expect(capped == ["channel-1", "channel-2"])
    #expect(allJoined == ["channel-1", "channel-2", "channel-3"])
    #expect(disabled == [])
    #expect(explicit == ["explicit-1"])
}

@MainActor
@Test
func liveSyncAppliesInjectedLifecycleEventsToStore() async throws {
    let service = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "test-token"
    ).liveSyncService()
    let store = try MattermostStore(inMemory: true)
    let posted = MattermostLiveEvent(
        event: "posted",
        data: ["post": .string("""
        {
          "id": "post-1",
          "create_at": 1,
          "update_at": 2,
          "edit_at": 0,
          "delete_at": 0,
          "user_id": "user-1",
          "channel_id": "channel-1",
          "root_id": "",
          "message": "hello from live sync",
          "type": ""
        }
        """)],
        broadcast: nil,
        seq: 1
    )

    let stream = service.events(
        to: store,
        options: MattermostLiveSyncOptions(maxBackfillChannels: 1),
        lifecycleEvents: {
            AsyncThrowingStream { continuation in
                continuation.yield(.connecting(attempt: 0))
                continuation.yield(.event(posted))
                continuation.finish()
            }
        },
        backfill: { _, teamID, _, _ in
            liveSyncBackfillResult(teamID: teamID ?? "team-1")
        }
    )

    var appliedPostID: String?
    for try await event in stream {
        if case .eventApplied(_, .posted(let post)) = event {
            appliedPostID = post.id
        }
    }

    let cachedPost = try #require(try store.cachedPost(id: "post-1"))
    #expect(appliedPostID == "post-1")
    #expect(cachedPost.message == "hello from live sync")
}

@MainActor
@Test
func liveSyncRefreshesUnreadOnPostUnreadInvalidation() async throws {
    let service = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "test-token"
    ).liveSyncService()
    let store = try MattermostStore(inMemory: true)
    let postUnread = MattermostLiveEvent(
        event: "post_unread",
        data: [
            "channel_id": .string("channel-1"),
            "post_id": .string("post-1"),
        ],
        broadcast: nil,
        seq: 2
    )
    var unreadRefreshes: [(userID: String, channelID: String)] = []

    let stream = service.events(
        to: store,
        options: MattermostLiveSyncOptions(maxBackfillChannels: 1),
        lifecycleEvents: {
            AsyncThrowingStream { continuation in
                continuation.yield(.connecting(attempt: 0))
                continuation.yield(.event(postUnread))
                continuation.finish()
            }
        },
        backfill: { _, teamID, _, _ in
            liveSyncBackfillResult(teamID: teamID ?? "team-1")
        },
        refreshUnread: { userID, channelID in
            unreadRefreshes.append((userID, channelID))
            return MattermostChannelUnread(
                teamId: "team-1",
                channelId: channelID,
                msgCount: 4,
                mentionCount: 1,
                msgCountRoot: nil,
                mentionCountRoot: nil
            )
        }
    )

    var refreshedUnread: MattermostChannelUnread?
    var appliedInvalidation: MattermostCacheInvalidationEvent?
    var observedEvents: [String] = []
    for try await event in stream {
        switch event {
        case .eventApplied(_, .postUnread(let invalidation)):
            appliedInvalidation = invalidation
            observedEvents.append("eventApplied")
        case .channelUnreadRefreshed(let unread):
            refreshedUnread = unread
            observedEvents.append("channelUnreadRefreshed")
        default:
            break
        }
    }

    let cachedUnread = try #require(try store.cachedChannelUnread(channelID: "channel-1", userID: "user-1"))
    #expect(appliedInvalidation?.channelID == "channel-1")
    #expect(unreadRefreshes.count == 1)
    #expect(unreadRefreshes.first?.userID == "user-1")
    #expect(unreadRefreshes.first?.channelID == "channel-1")
    #expect(observedEvents == ["eventApplied", "channelUnreadRefreshed"])
    #expect(refreshedUnread?.msgCount == 4)
    #expect(cachedUnread.msgCount == 4)
    #expect(cachedUnread.mentionCount == 1)
}

@MainActor
@Test
func liveSyncAppliesEventBeforeRefreshFailureAndContinues() async throws {
    struct RefreshFailure: LocalizedError, Equatable {
        let errorDescription: String? = "refresh failed for test"
    }

    let service = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "test-token"
    ).liveSyncService()
    let store = try MattermostStore(inMemory: true)
    let postUnread = MattermostLiveEvent(
        event: "post_unread",
        data: [
            "channel_id": .string("channel-1"),
            "post_id": .string("post-1"),
        ],
        broadcast: nil,
        seq: 20
    )
    let posted = MattermostLiveEvent(
        event: "posted",
        data: ["post": .string("""
        {
          "id": "post-after-refresh-failure",
          "create_at": 10,
          "update_at": 10,
          "edit_at": 0,
          "delete_at": 0,
          "user_id": "user-1",
          "channel_id": "channel-1",
          "root_id": "",
          "message": "still applied",
          "type": ""
        }
        """)],
        broadcast: nil,
        seq: 21
    )
    var unreadRefreshCount = 0

    let stream = service.events(
        to: store,
        options: MattermostLiveSyncOptions(maxBackfillChannels: 1),
        lifecycleEvents: {
            AsyncThrowingStream { continuation in
                continuation.yield(.connecting(attempt: 0))
                continuation.yield(.event(postUnread))
                continuation.yield(.event(posted))
                continuation.finish()
            }
        },
        backfill: { _, teamID, _, _ in
            liveSyncBackfillResult(teamID: teamID ?? "team-1")
        },
        refreshUnread: { _, _ in
            unreadRefreshCount += 1
            throw RefreshFailure()
        }
    )

    var appliedEvents: [String] = []
    var refreshedUnread: MattermostChannelUnread?
    for try await event in stream {
        switch event {
        case .eventApplied(_, .postUnread):
            appliedEvents.append("post_unread")
        case .eventApplied(_, .posted(let post)):
            appliedEvents.append(post.id)
        case .channelUnreadRefreshed(let unread):
            refreshedUnread = unread
        default:
            break
        }
    }

    let cachedPost = try #require(try store.cachedPost(id: "post-after-refresh-failure"))
    #expect(appliedEvents == ["post_unread", "post-after-refresh-failure"])
    #expect(unreadRefreshCount == 1)
    #expect(refreshedUnread == nil)
    #expect(cachedPost.message == "still applied")
}

@MainActor
@Test
func liveSyncRefreshesThreadStateOnThreadInvalidation() async throws {
    let service = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "test-token"
    ).liveSyncService()
    let store = try MattermostStore(inMemory: true)
    let threadReadChanged = MattermostLiveEvent(
        event: "thread_read_changed",
        data: [
            "thread_id": .string("root-1"),
            "post_id": .string("reply-1"),
            "channel_id": .string("channel-1"),
        ],
        broadcast: MattermostLiveBroadcast(
            omitUsers: nil,
            userId: "user-1",
            channelId: "channel-1",
            teamId: "team-1"
        ),
        seq: 3
    )
    var threadRefreshes: [(userID: String, teamID: String, threadID: String)] = []

    let stream = service.events(
        to: store,
        options: MattermostLiveSyncOptions(maxBackfillChannels: 1),
        lifecycleEvents: {
            AsyncThrowingStream { continuation in
                continuation.yield(.connecting(attempt: 0))
                continuation.yield(.event(threadReadChanged))
                continuation.finish()
            }
        },
        backfill: { _, teamID, _, _ in
            liveSyncBackfillResult(teamID: teamID ?? "team-1")
        },
        refreshThreadState: { userID, teamID, threadID in
            threadRefreshes.append((userID, teamID, threadID))
            return MattermostThreadResponse(
                id: threadID,
                replyCount: 3,
                lastReplyAt: 70,
                lastViewedAt: 60,
                participants: [
                    MattermostUser(
                        id: userID,
                        username: "alice",
                        email: "alice@example.com",
                        firstName: nil,
                        lastName: nil,
                        nickname: nil,
                        position: nil,
                        locale: nil,
                        timezone: nil
                    ),
                ],
                post: MattermostPost(
                    id: threadID,
                    createAt: 10,
                    updateAt: 20,
                    editAt: 0,
                    deleteAt: 0,
                    userId: userID,
                    channelId: "channel-1",
                    rootId: "",
                    originalId: nil,
                    message: "root from refreshed thread state",
                    type: "",
                    hashtags: nil,
                    pendingPostId: nil,
                    fileIds: nil,
                    hasReactions: false
                ),
                unreadReplies: 1,
                unreadMentions: 1,
                isUrgent: false,
                deleteAt: 0
            )
        }
    )

    var refreshedThread: MattermostThreadResponse?
    var appliedThreadEvent: MattermostThreadEvent?
    for try await event in stream {
        switch event {
        case .eventApplied(_, .threadReadChanged(let threadEvent)):
            appliedThreadEvent = threadEvent
        case .threadStateRefreshed(let thread):
            refreshedThread = thread
        default:
            break
        }
    }

    let cachedThread = try #require(try store.cachedThreadState(rootID: "root-1", userID: "user-1", teamID: "team-1"))
    let cachedPost = try #require(try store.cachedPost(id: "root-1"))
    let cachedUser = try #require(try store.cachedUser(id: "user-1"))

    #expect(appliedThreadEvent?.threadID == "root-1")
    #expect(threadRefreshes.count == 1)
    #expect(threadRefreshes.first?.userID == "user-1")
    #expect(threadRefreshes.first?.teamID == "team-1")
    #expect(threadRefreshes.first?.threadID == "root-1")
    #expect(refreshedThread?.id == "root-1")
    #expect(cachedThread.replyCount == 3)
    #expect(cachedThread.unreadReplies == 1)
    #expect(cachedThread.unreadMentions == 1)
    #expect(cachedThread.participantIds == ["user-1"])
    #expect(cachedPost.message == "root from refreshed thread state")
    #expect(cachedUser.username == "alice")
}

private func liveSyncChannel(id: String, teamID: String = "team-1") -> MattermostChannel {
    MattermostChannel(
        id: id,
        createAt: 1,
        updateAt: 1,
        teamId: teamID,
        name: id,
        displayName: id,
        type: "O",
        header: nil,
        purpose: nil,
        deleteAt: nil,
        totalMsgCount: nil,
        totalMsgCountRoot: nil,
        lastPostAt: nil,
        lastRootPostAt: nil
    )
}

private func liveSyncBackfillResult(
    teamID: String,
    postSyncs: [MattermostChannelPostSyncResult] = []
) -> MattermostLiveBackfillResult {
    let channel = liveSyncChannel(id: "channel-1", teamID: teamID)
    let team = MattermostTeam(
        id: teamID,
        name: "team",
        displayName: "Team",
        description: nil,
        type: "O"
    )
    let sync = MattermostSyncResult(
        user: MattermostUser(
            id: "user-1",
            username: "alice",
            email: "alice@example.com",
            firstName: nil,
            lastName: nil,
            nickname: nil,
            position: nil,
            locale: nil,
            timezone: nil
        ),
        teams: [team],
        teamID: teamID,
        channels: [channel],
        postSync: nil,
        syncedTeamsCount: 1,
        syncedUsersCount: 1,
        syncedMembersCount: 0,
        syncedUnreadsCount: 0,
        syncedCategoriesCount: 0,
        cachedTeamsCount: 1,
        cachedUsersCount: 1,
        cachedChannelsCount: 1,
        cachedMembersCount: 0,
        cachedUnreadsCount: 0,
        teamCursorLastSyncAt: 1
    )

    return MattermostLiveBackfillResult(sync: sync, postSyncs: postSyncs)
}

private func liveSyncPost(
    id: String,
    channelID: String,
    message: String,
    createAt: Int64,
    updateAt: Int64
) -> MattermostPost {
    MattermostPost(
        id: id,
        createAt: createAt,
        updateAt: updateAt,
        editAt: 0,
        deleteAt: 0,
        userId: "user-1",
        channelId: channelID,
        rootId: "",
        originalId: nil,
        message: message,
        type: "",
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: false
    )
}

@MainActor
private func liveSyncStorePostSync(
    _ post: MattermostPost,
    in store: MattermostStore
) throws -> MattermostChannelPostSyncResult {
    let postList = MattermostPostList(
        order: [post.id],
        posts: [post.id: post],
        nextPostId: nil,
        prevPostId: nil,
        hasNext: nil
    )
    try store.upsert(postList: postList)
    try store.setSyncCursor(
        scope: "channel-posts:\(post.channelId)",
        lastSyncAt: post.cacheTimestamp,
        lastItemID: post.id
    )
    try store.save()
    return MattermostChannelPostSyncResult(
        channelID: post.channelId,
        posts: [post],
        pageCount: 1,
        cursorLastSyncAt: post.cacheTimestamp,
        cursorLastItemID: post.id
    )
}
