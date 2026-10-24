import Foundation
@_spi(Testing) import MattermostSwift

// WebSocket, live-sync and reconnect/backfill scenarios.
extension MattermostSwiftCLI {
    static func runWebSocketTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let recorder = LiveEventRecorder()
        let eventTask = Task {
            do {
                for try await event in client.liveEventStream().events() {
                    await recorder.append(event)
                }
            } catch {
                await recorder.setError(error)
            }
        }
        defer {
            eventTask.cancel()
        }

        try await waitForEvents(recorder: recorder, minimumCount: 1, timeoutSeconds: 10)

        let marker = "mmswift-test-websocket-\(Int(Date.now.timeIntervalSince1970))"
        let post = try await client.sendPost(channelID: channelID, message: marker)
        var postDeleted = false

        do {
            let postedEvent = try await waitForPostEvent(
                recorder: recorder,
                eventName: "posted",
                postID: post.id,
                timeoutSeconds: 10
            )

            let edited = try await client.editPost(id: post.id, message: "\(marker)-edited")
            let editedEvent = try await waitForPostEvent(
                recorder: recorder,
                eventName: "post_edited",
                postID: edited.id,
                timeoutSeconds: 10
            )

            let deleteStatus = try await client.deletePost(id: post.id)
            postDeleted = true
            let deletedEvent = try await waitForPostEvent(
                recorder: recorder,
                eventName: "post_deleted",
                postID: post.id,
                timeoutSeconds: 10
            )

            print("post: \(post.id)")
            print("posted-event: \(postedEvent.event)")
            print("edited-event: \(editedEvent.event)")
            print("deleted-event: \(deletedEvent.event)")
            print("event-post: \(postedEvent.stringData("post")?.contains(post.id) == true)")
            print("event-edit: \(editedEvent.stringData("post")?.contains(edited.id) == true)")
            print("event-delete: \(deletedEvent.stringData("post")?.contains(post.id) == true)")
            print("post-delete-status: \(deleteStatus.status)")
        } catch {
            if !postDeleted {
                _ = try? await client.deletePost(id: post.id)
            }
            throw error
        }
    }

    @MainActor
    static func runLiveSyncTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let storeURL = try resolvedStoreURL()
        let store = try MattermostStore(url: storeURL)
        let recorder = LiveSyncRecorder()
        let stream = client.liveSyncService().events(
            to: store,
            options: MattermostLiveSyncOptions(
                syncOptions: MattermostSyncOptions(
                    postPageSize: 20,
                    maxPostPages: 1,
                    includeChannelUsers: false,
                    includeSidebarCategories: true,
                    refreshUnreadForAllJoinedChannels: false
                ),
                channelIDs: [channelID],
                backfillJoinedChannelPosts: false,
                maxBackfillChannels: 1
            ),
            reconnectPolicy: .disabled
        )
        let eventTask = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch {
                await recorder.setError(error)
            }
        }
        defer {
            eventTask.cancel()
        }

        let backfill = try await waitForLiveSyncBackfill(recorder: recorder, timeoutSeconds: 15)
        let marker = "mmswift-test-live-sync-\(Int(Date.now.timeIntervalSince1970))"
        var post: MattermostPost?

        do {
            let createdPost = try await client.sendPost(channelID: channelID, message: marker)
            post = createdPost
            let appliedPost = try await waitForLiveSyncPost(
                recorder: recorder,
                postID: createdPost.id,
                timeoutSeconds: 15
            )
            let cachedPost = try store.cachedPost(id: createdPost.id)
            let deleteStatus = try await client.deletePost(id: createdPost.id)

            print("store: \(storeURL.path)")
            print("backfill-channels: \(backfill.postSyncs.count)")
            print("post: \(createdPost.id)")
            print("event-post: \(appliedPost.id == createdPost.id)")
            print("cached-post: \(cachedPost?.id == createdPost.id)")
            print("post-delete-status: \(deleteStatus.status)")
        } catch {
            _ = await cleanupPosts(client: client, postIDs: [post?.id].compactMap(\.self))
            throw error
        }
    }

    @MainActor
    static func runReconnectBackfillTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let store = try MattermostStore(inMemory: true)
        let cursorScope = "channel-posts:\(channelID)"
        let initialSync = try await client.syncChannelPosts(
            channelID: channelID,
            to: store,
            perPage: 20,
            maxPages: 1
        )
        let since = Int64(Date.now.timeIntervalSince1970 * 1000) - 1000
        try store.setSyncCursor(
            scope: cursorScope,
            lastSyncAt: since,
            lastItemID: initialSync.cursorLastItemID
        )
        try store.save()

        let marker = "mmswift-test-reconnect-backfill-\(Int(Date.now.timeIntervalSince1970))"
        var post: MattermostPost?

        do {
            let createdPost = try await client.sendPost(channelID: channelID, message: marker)
            post = createdPost
            let backfill = try await client.syncChannelPosts(
                channelID: channelID,
                to: store,
                perPage: 20,
                maxPages: 1
            )
            let cachedPost = try store.cachedPost(id: createdPost.id)
            let cursor = try store.cachedSyncCursor(scope: cursorScope)

            guard backfill.posts.contains(where: { $0.id == createdPost.id }) else {
                throw CLIError.usage("Reconnect backfill did not return the post created after the stored cursor.")
            }
            guard cachedPost?.id == createdPost.id else {
                throw CLIError.usage("Reconnect backfill did not cache the post created after the stored cursor.")
            }
            guard let cursor, cursor.lastSyncAt >= createdPost.cacheTimestamp else {
                throw CLIError.usage("Reconnect backfill did not advance the channel post cursor.")
            }

            let deleteStatus = try await client.deletePost(id: createdPost.id)
            post = nil

            print("channel: \(channelID)")
            print("seed-cursor: \(since)")
            print("post: \(createdPost.id)")
            print("backfill-posts: \(backfill.posts.count)")
            print("found-created-post: true")
            print("cached-created-post: true")
            print("advanced-cursor: \(cursor.lastSyncAt)")
            print("post-delete-status: \(deleteStatus.status)")
        } catch {
            _ = await cleanupPosts(client: client, postIDs: [post?.id].compactMap(\.self))
            throw error
        }
    }

    @MainActor
    static func runDeletionBackfillTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let store = try MattermostStore(inMemory: true)
        let cursorScope = "channel-posts:\(channelID)"
        let marker = "mmswift-test-delete-backfill-\(Int(Date.now.timeIntervalSince1970))"
        var postID: String?

        do {
            let createdPost = try await client.sendPost(channelID: channelID, message: marker)
            postID = createdPost.id

            let initialSync = try await client.syncChannelPosts(
                channelID: channelID,
                to: store,
                perPage: 20,
                maxPages: 1
            )
            guard initialSync.posts.contains(where: { $0.id == createdPost.id }) else {
                throw CLIError.usage("Initial deletion backfill setup did not cache the created post.")
            }

            let since = Int64(Date.now.timeIntervalSince1970 * 1000)
            try store.setSyncCursor(
                scope: cursorScope,
                lastSyncAt: since,
                lastItemID: createdPost.id
            )
            try store.save()
            try await Task.sleep(for: .milliseconds(1_000))

            let deleteStatus = try await client.deletePost(id: createdPost.id)
            postID = nil

            let deletionSync = try await client.syncChannelPosts(
                channelID: channelID,
                to: store,
                perPage: 20,
                maxPages: 1
            )
            let deletedFromBackfill = deletionSync.posts.first { $0.id == createdPost.id }
            let cachedPost = try store.cachedPost(id: createdPost.id)
            let visiblePosts = try store.cachedPosts(
                channelID: channelID,
                limit: 60,
                includeDeleted: false
            )
            let cursor = try store.cachedSyncCursor(scope: cursorScope)

            guard deletedFromBackfill?.isDeleted == true else {
                throw CLIError.usage("Deletion backfill did not return the deleted post tombstone.")
            }
            guard cachedPost?.isDeleted == true else {
                throw CLIError.usage("Deletion backfill did not mark the cached post as deleted.")
            }
            guard !visiblePosts.contains(where: { $0.id == createdPost.id }) else {
                throw CLIError.usage("Deleted post remained in visible cached channel posts.")
            }
            guard let cursor, cursor.lastSyncAt >= (cachedPost?.deleteAt ?? 0) else {
                throw CLIError.usage("Deletion backfill did not advance the channel post cursor to the delete timestamp.")
            }

            print("channel: \(channelID)")
            print("seed-cursor: \(since)")
            print("post: \(createdPost.id)")
            print("delete-status: \(deleteStatus.status)")
            print("backfill-posts: \(deletionSync.posts.count)")
            print("found-deleted-post: true")
            print("cached-deleted-post: true")
            print("visible-cache-filtered: true")
            print("advanced-cursor: \(cursor.lastSyncAt)")
        } catch {
            _ = await cleanupPosts(client: client, postIDs: [postID].compactMap(\.self))
            throw error
        }
    }

    @MainActor
    static func runLiveSyncReconnectTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let store = try MattermostStore(inMemory: true)
        let lifecycle = LiveSyncLifecycleDriver()
        let recorder = LiveSyncRecorder()
        let stream = client.liveSyncService().events(
            to: store,
            options: MattermostLiveSyncOptions(
                syncOptions: MattermostSyncOptions(
                    postPageSize: 20,
                    maxPostPages: 1,
                    includeChannelUsers: false,
                    includeSidebarCategories: false,
                    refreshUnreadForAllJoinedChannels: false
                ),
                channelIDs: [channelID],
                backfillJoinedChannelPosts: false,
                maxBackfillChannels: 1,
                minimumBackfillGap: nil,
                refreshUnreadOnChannelViewed: false,
                refreshUnreadOnPostUnread: false,
                refreshSidebarCategoriesOnPreferenceChange: false,
                refreshThreadStateOnThreadEvent: false
            ),
            lifecycleEvents: {
                AsyncThrowingStream { continuation in
                    Task {
                        await lifecycle.attach(continuation)
                    }
                }
            }
        )
        let eventTask = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch {
                await recorder.setError(error)
            }
        }
        defer {
            eventTask.cancel()
        }

        await lifecycle.yield(.connecting(attempt: 0))
        let firstBackfill = try await waitForLiveSyncBackfillCount(
            recorder: recorder,
            count: 1,
            timeoutSeconds: 15
        ).last

        let marker = "mmswift-test-live-reconnect-\(Int(Date.now.timeIntervalSince1970))"
        var post: MattermostPost?

        do {
            await lifecycle.yield(.reconnecting(attempt: 0, delay: .milliseconds(1)))
            let createdPost = try await client.sendPost(channelID: channelID, message: marker)
            post = createdPost
            await lifecycle.yield(.connecting(attempt: 1))

            let backfills = try await waitForLiveSyncBackfillCount(
                recorder: recorder,
                count: 2,
                timeoutSeconds: 20
            )
            let secondBackfill = try requireFirst(
                Array(backfills.dropFirst()),
                "Live sync reconnect test did not receive a second backfill."
            )
            let cachedPost = try store.cachedPost(id: createdPost.id)
            let reconnectAttempts = await recorder.reconnectingAttempts

            guard secondBackfill.postSyncs.flatMap(\.posts).contains(where: { $0.id == createdPost.id }) else {
                throw CLIError.usage("Live sync reconnect backfill did not return the post created while disconnected.")
            }
            guard cachedPost?.id == createdPost.id else {
                throw CLIError.usage("Live sync reconnect backfill did not cache the post created while disconnected.")
            }
            guard reconnectAttempts == [0] else {
                throw CLIError.usage("Live sync reconnect lifecycle did not emit the expected reconnecting attempt.")
            }

            let deleteStatus = try await client.deletePost(id: createdPost.id)
            post = nil
            await lifecycle.finish()

            print("channel: \(channelID)")
            print("initial-backfill-channels: \(firstBackfill?.postSyncs.count ?? 0)")
            print("reconnect-attempts: \(reconnectAttempts.count)")
            print("post: \(createdPost.id)")
            print("reconnect-backfill-channels: \(secondBackfill.postSyncs.count)")
            print("found-created-post: true")
            print("cached-created-post: true")
            print("post-delete-status: \(deleteStatus.status)")
        } catch {
            await lifecycle.finish()
            _ = await cleanupPosts(client: client, postIDs: [post?.id].compactMap(\.self))
            throw error
        }
    }

    @MainActor
    static func runAllChannelBackfillTest(client: MattermostClient) async throws {
        let teamName = ProcessInfo.processInfo.environment["MATTERMOST_TEAM_NAME"]
        progress("Loading joined channels for the all-channel backfill…")
        let channels = try await loadChannels(client: client)
        guard !channels.isEmpty else {
            throw CLIError.usage("No joined channels are available for all-channel backfill verification.")
        }

        let store = try MattermostStore(inMemory: true)
        let recorder = LiveSyncRecorder()
        progress("Starting a one-page backfill across \(channels.count) joined channel(s)…")
        let stream = client.liveSyncService().events(
            to: store,
            teamName: teamName,
            options: MattermostLiveSyncOptions(
                syncOptions: MattermostSyncOptions(
                    postPageSize: 1,
                    maxPostPages: 1,
                    includeChannelUsers: false,
                    includeSidebarCategories: false,
                    refreshUnreadForAllJoinedChannels: false
                ),
                channelIDs: [],
                backfillJoinedChannelPosts: true,
                backfillAllJoinedChannelPosts: true,
                maxBackfillChannels: 0,
                refreshUnreadOnChannelViewed: false,
                refreshUnreadOnPostUnread: false,
                refreshSidebarCategoriesOnPreferenceChange: false,
                refreshThreadStateOnThreadEvent: false
            ),
            reconnectPolicy: .disabled
        )
        let eventTask = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch {
                await recorder.setError(error)
            }
        }
        defer {
            eventTask.cancel()
        }

        progress("Waiting for the all-channel backfill to finish…")
        let backfill = try await waitForLiveSyncBackfill(recorder: recorder, timeoutSeconds: 30)
        guard backfill.postSyncs.count == channels.count else {
            throw CLIError.usage(
                "All-channel backfill synced \(backfill.postSyncs.count) channel(s), expected \(channels.count)."
            )
        }

        let backfilledPosts = backfill.postSyncs.reduce(0) { count, sync in
            count + sync.posts.count
        }
        progress("All-channel backfill finished.")

        print("store: in-memory")
        print("team: \(backfill.sync.teamID ?? "-")")
        print("joined-channels: \(channels.count)")
        print("backfilled-channels: \(backfill.postSyncs.count)")
        print("backfilled-posts: \(backfilledPosts)")
        print("all-joined-backfill: true")
    }

    @MainActor
    static func runAllChannelReconnectTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let teamName = ProcessInfo.processInfo.environment["MATTERMOST_TEAM_NAME"]
        progress("Loading joined channels for the all-channel reconnect test…")
        let channels = try await loadChannels(client: client)
        guard !channels.isEmpty else {
            throw CLIError.usage("No joined channels are available for all-channel reconnect verification.")
        }

        let store = try MattermostStore(inMemory: true)
        let lifecycle = LiveSyncLifecycleDriver()
        let recorder = LiveSyncRecorder()
        let stream = client.liveSyncService().events(
            to: store,
            teamName: teamName,
            options: MattermostLiveSyncOptions(
                syncOptions: MattermostSyncOptions(
                    postPageSize: 1,
                    maxPostPages: 1,
                    includeChannelUsers: false,
                    includeSidebarCategories: false,
                    refreshUnreadForAllJoinedChannels: false
                ),
                channelIDs: [],
                backfillJoinedChannelPosts: true,
                backfillAllJoinedChannelPosts: true,
                maxBackfillChannels: 0,
                minimumBackfillGap: nil,
                refreshUnreadOnChannelViewed: false,
                refreshUnreadOnPostUnread: false,
                refreshSidebarCategoriesOnPreferenceChange: false,
                refreshThreadStateOnThreadEvent: false
            ),
            lifecycleEvents: {
                AsyncThrowingStream { continuation in
                    Task {
                        await lifecycle.attach(continuation)
                    }
                }
            }
        )
        let eventTask = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch {
                await recorder.setError(error)
            }
        }
        defer {
            eventTask.cancel()
        }

        progress("Waiting for the initial \(channels.count)-channel backfill…")
        await lifecycle.yield(.connecting(attempt: 0))
        let firstBackfill = try await waitForLiveSyncBackfillCount(
            recorder: recorder,
            count: 1,
            timeoutSeconds: 30
        )[0]

        let marker = "mmswift-test-all-channel-reconnect-\(Int(Date.now.timeIntervalSince1970))"
        var post: MattermostPost?

        do {
            guard firstBackfill.postSyncs.count == channels.count else {
                throw CLIError.usage(
                    "Initial all-channel backfill synced \(firstBackfill.postSyncs.count) channel(s), expected \(channels.count)."
                )
            }

            await lifecycle.yield(.reconnecting(attempt: 0, delay: .milliseconds(1)))
            let createdPost = try await client.sendPost(channelID: channelID, message: marker)
            post = createdPost
            await lifecycle.yield(.connecting(attempt: 1))

            progress("Waiting for the reconnect backfill across all joined channels…")
            let backfills = try await waitForLiveSyncBackfillCount(
                recorder: recorder,
                count: 2,
                timeoutSeconds: 45
            )
            let secondBackfill = try requireFirst(
                Array(backfills.dropFirst()),
                "All-channel reconnect test did not receive a second backfill."
            )
            let cachedPost = try store.cachedPost(id: createdPost.id)
            let reconnectAttempts = await recorder.reconnectingAttempts

            guard secondBackfill.postSyncs.count == channels.count else {
                throw CLIError.usage(
                    "Reconnect all-channel backfill synced \(secondBackfill.postSyncs.count) channel(s), expected \(channels.count)."
                )
            }
            guard secondBackfill.postSyncs.flatMap(\.posts).contains(where: { $0.id == createdPost.id }) else {
                throw CLIError.usage("All-channel reconnect backfill did not return the post created while disconnected.")
            }
            guard cachedPost?.id == createdPost.id else {
                throw CLIError.usage("All-channel reconnect backfill did not cache the post created while disconnected.")
            }
            guard reconnectAttempts == [0] else {
                throw CLIError.usage("All-channel reconnect lifecycle did not emit the expected reconnecting attempt.")
            }

            let deleteStatus = try await client.deletePost(id: createdPost.id)
            post = nil
            await lifecycle.finish()
            progress("All-channel reconnect backfill finished.")

            print("store: in-memory")
            print("channel: \(channelID)")
            print("joined-channels: \(channels.count)")
            print("initial-backfill-channels: \(firstBackfill.postSyncs.count)")
            print("reconnect-attempts: \(reconnectAttempts.count)")
            print("post: \(createdPost.id)")
            print("reconnect-backfill-channels: \(secondBackfill.postSyncs.count)")
            print("found-created-post: true")
            print("cached-created-post: true")
            print("post-delete-status: \(deleteStatus.status)")
        } catch {
            await lifecycle.finish()
            _ = await cleanupPosts(client: client, postIDs: [post?.id].compactMap(\.self))
            throw error
        }
    }
}
