import Foundation
@_spi(Testing) import MattermostSwift

extension MattermostSwiftCLI {
    @MainActor
    static func runE2ETest(client: MattermostClient) async throws {
        let teamID = try await loadTeamID(client: client)
        let suffix = testSuffix()
        let searchToken = suffix.replacingOccurrences(of: "-", with: "")
        let marker = "mmswifte2e\(searchToken)"
        let originalCategoryOrder = try await client.sidebarCategoryOrder(teamID: teamID)
        var createdChannel: MattermostChannel?
        var createdCategory: MattermostSidebarCategory?
        var createdPostIDs: [String] = []

        do {
            let channel = try await client.createChannel(
                teamID: teamID,
                name: "mmswift-test-e2e-\(suffix)",
                displayName: "MattermostSwift E2E \(suffix)",
                purpose: "Created by MattermostSwiftCLI isolated e2e verification."
            )
            createdChannel = channel

            let category = try await client.createSidebarCategory(
                teamID: teamID,
                displayName: "MattermostSwift E2E \(suffix)"
            )
            createdCategory = category

            let moveResult = try await client.moveChannelToSidebarCategory(
                teamID: teamID,
                channelID: channel.id,
                categoryID: category.id,
                position: 0
            )
            let movedCategory = moveResult.categories.first { $0.id == category.id }

            let root = try await client.sendPost(
                channelID: channel.id,
                message: "\(marker) root"
            )
            createdPostIDs.append(root.id)

            let editedRoot = try await client.editPost(
                id: root.id,
                message: "\(marker) root edited"
            )

            let reply = try await client.sendPost(
                channelID: channel.id,
                message: "\(marker) reply",
                rootID: root.id
            )
            createdPostIDs.append(reply.id)

            let thread = try await client.thread(postID: root.id)

            let user = try await client.currentUser()
            let reaction = try await client.addReaction(
                postID: root.id,
                userID: user.id,
                emojiName: "smile"
            )
            let reactions = try await client.reactions(postID: root.id)
            let reactionDeleteStatus = try await client.removeReaction(
                postID: root.id,
                userID: user.id,
                emojiName: reaction.emojiName
            )

            let payload = Data("hello from \(marker)\n".utf8)
            let upload = try await client.uploadFile(
                channelID: channel.id,
                filename: "\(marker).txt",
                data: payload,
                contentType: "text/plain"
            )
            let fileInfo = try requireFirst(upload.fileInfos, "Mattermost did not return uploaded file metadata.")
            let filePost = try await client.sendPost(
                channelID: channel.id,
                message: "\(marker) file",
                fileIDs: [fileInfo.id]
            )
            createdPostIDs.append(filePost.id)
            let attachedFileInfos = try await client.fileInfos(postID: filePost.id)
            let downloaded = try await client.downloadFile(id: fileInfo.id)

            let searchResults = try await waitForSearchResult(
                client: client,
                teamID: teamID,
                terms: marker,
                postID: root.id,
                timeoutSeconds: 15
            )
            let viewResponse = try await client.viewChannel(channelID: channel.id)
            let unread = try await client.channelUnread(channelID: channel.id)

            let store = try MattermostStore(inMemory: true)
            let sync = try await client.syncTimeline(
                .channel(id: channel.id),
                to: store,
                request: MattermostTimelineRequest(perPage: 20)
            )
            let cachedPosts = try store.cachedTimeline(.channel(id: channel.id))

            let cleanup = await cleanupE2EResources(
                client: client,
                teamID: teamID,
                postIDs: createdPostIDs,
                categoryID: createdCategory?.id,
                channelID: createdChannel?.id,
                originalCategoryOrder: originalCategoryOrder
            )

            print("team: \(teamID)")
            print("channel: \(channel.id)")
            print("category: \(category.id)")
            print("sidebar-moved: \(movedCategory?.channelIds.first == channel.id)")
            print("root-post: \(root.id)")
            print("edited-post: \(editedRoot.id)")
            print("reply-post: \(reply.id)")
            print("thread-contained-reply: \(thread.posts[reply.id] != nil)")
            print("reaction-count: \(reactions.count)")
            print("reaction-delete-status: \(reactionDeleteStatus.status)")
            print("file: \(fileInfo.id)")
            print("attached-files: \(attachedFileInfos.count)")
            print("download-matches: \(downloaded == payload)")
            print("search-found-root: \(searchResults.posts[root.id] != nil)")
            print("view-status: \(viewResponse.status)")
            print("unread-messages: \(unread.msgCount)")
            print("synced-posts: \(sync.posts.count)")
            print("cached-posts: \(cachedPosts.count)")
            print("cleanup-posts: \(cleanup.deletedPosts)")
            print("cleanup-category: \(cleanup.deletedCategory)")
            print("cleanup-channel: \(cleanup.deletedChannel)")
            print("cleanup-order-restored: \(cleanup.restoredOrder)")
        } catch {
            _ = await cleanupE2EResources(
                client: client,
                teamID: teamID,
                postIDs: createdPostIDs,
                categoryID: createdCategory?.id,
                channelID: createdChannel?.id,
                originalCategoryOrder: originalCategoryOrder
            )
            throw error
        }
    }

    static func runLoginTest() async throws {
        let environment = ProcessInfo.processInfo.environment
        let session = try await MattermostClient.loginFromEnvironment(environment)
        guard let rawURL = environment["MATTERMOST_URL"],
              let serverURL = URL(string: rawURL) else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_URL")
        }

        let client = try session.client(serverURL: serverURL)
        let user = try await client.currentUser()

        print("login-user: \(session.user.username)")
        print("token-received: \(!session.token.isEmpty)")
        print("token-source: \(session.tokenSource.rawValue)")
        print("me-user: \(user.username)")
    }

    static func runThreadTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let marker = "mmswift-test-thread-\(Int(Date.now.timeIntervalSince1970))"
        var root: MattermostPost?
        var reply: MattermostPost?

        do {
            let createdRoot = try await client.sendPost(channelID: channelID, message: "\(marker) root")
            root = createdRoot
            let createdReply = try await client.sendPost(
                channelID: channelID,
                message: "\(marker) reply",
                rootID: createdRoot.id
            )
            reply = createdReply
            let thread = try await client.thread(postID: createdRoot.id)
            let replyDeleteStatus = try await client.deletePost(id: createdReply.id)
            let rootDeleteStatus = try await client.deletePost(id: createdRoot.id)

            print("root-post: \(createdRoot.id)")
            print("reply-post: \(createdReply.id)")
            print("thread-posts: \(thread.orderedPosts.count)")
            print("reply-delete-status: \(replyDeleteStatus.status)")
            print("root-delete-status: \(rootDeleteStatus.status)")
        } catch {
            _ = await cleanupPosts(client: client, postIDs: [reply?.id, root?.id].compactMap(\.self))
            throw error
        }
    }

    @MainActor
    static func runTimelineTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let marker = "mmswift-test-timeline-\(Int(Date.now.timeIntervalSince1970))"
        let root = try await client.sendPost(channelID: channelID, message: "\(marker) root")
        var reply: MattermostPost?
        var deletedRoot = false

        do {
            let createdReply = try await client.sendPost(
                channelID: channelID,
                message: "\(marker) reply",
                rootID: root.id
            )
            reply = createdReply

            let channelTimeline = try await client.timeline(
                .channel(id: channelID),
                request: MattermostTimelineRequest(perPage: 20)
            )
            let threadTimeline = try await client.timeline(
                .thread(rootPostID: root.id),
                request: MattermostTimelineRequest(perPage: 20)
            )

            let store = try MattermostStore(url: try resolvedStoreURL())
            let sync = try await client.syncTimeline(
                .thread(rootPostID: root.id),
                to: store,
                request: MattermostTimelineRequest(perPage: 20)
            )
            let cachedThread = try store.cachedTimeline(.thread(rootPostID: root.id))

            let replyDeleteStatus = try await client.deletePost(id: createdReply.id)
            let rootDeleteStatus = try await client.deletePost(id: root.id)
            deletedRoot = true

            print("root-post: \(root.id)")
            print("reply-post: \(createdReply.id)")
            print("channel-timeline-posts: \(channelTimeline.posts.count)")
            print("channel-contained-root: \(channelTimeline.posts.contains { $0.id == root.id })")
            print("thread-timeline-posts: \(threadTimeline.posts.count)")
            print("thread-contained-reply: \(threadTimeline.posts.contains { $0.id == createdReply.id })")
            print("synced-thread-posts: \(sync.posts.count)")
            print("cached-thread-posts: \(cachedThread.count)")
            print("reply-delete-status: \(replyDeleteStatus.status)")
            print("root-delete-status: \(rootDeleteStatus.status)")
        } catch {
            if let reply {
                _ = try? await client.deletePost(id: reply.id)
            }
            if !deletedRoot {
                _ = try? await client.deletePost(id: root.id)
            }
            throw error
        }
    }

    static func runSinceTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let since = Int64(Date.now.timeIntervalSince1970 * 1000) - 1000
        let marker = "mmswift-test-since-\(Int(Date.now.timeIntervalSince1970))"
        let post = try await client.sendPost(channelID: channelID, message: marker)
        var deletedPost = false

        do {
            let updates = try await client.postsSince(channelID: channelID, since: since)
            let deleteStatus = try await client.deletePost(id: post.id)
            deletedPost = true

            print("since: \(since)")
            print("post: \(post.id)")
            print("updates: \(updates.orderedPosts.count)")
            print("found-created-post: \(updates.posts[post.id] != nil)")
            print("post-delete-status: \(deleteStatus.status)")
        } catch {
            if !deletedPost {
                _ = try? await client.deletePost(id: post.id)
            }
            throw error
        }
    }

    static func runUnreadPostsTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let postList = try await client.postsAroundLastUnread(
            channelID: channelID,
            limitBefore: 5,
            limitAfter: 5,
            skipFetchThreads: false,
            collapsedThreads: true,
            collapsedThreadsExtended: true
        )
        let decodedPosts = postList.posts.values.allSatisfy { !$0.id.isEmpty && $0.channelId == channelID }

        print("channel: \(channelID)")
        print("unread-context-posts: \(postList.orderedPosts.count)")
        print("has-order: \(!postList.order.isEmpty || postList.posts.isEmpty)")
        print("decoded-posts: \(decodedPosts)")
    }

    static func runNotifyPropsTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let props = try await client.channelMember(channelID: channelID).channelNotifyProps

        print("channel: \(channelID)")
        printNotifyProps(props)
        print("notify-raw-count: \(props.rawValues.count)")
    }

    static func runDirectChannelTest(client: MattermostClient, userID: String?) async throws {
        let currentUser = try await client.currentUser()
        let otherUserID: String
        if let userID, !userID.isEmpty {
            otherUserID = userID
        } else {
            let users = try await client.users(channelID: resolvedChannelID(nil), perPage: 20)
            guard let peer = users.first(where: { $0.id != currentUser.id }) else {
                throw CLIError.usage("Provide a user id or set MATTERMOST_CHANNEL_ID to a channel with another user.")
            }
            otherUserID = peer.id
        }

        let channel = try await client.createDirectChannel(
            userID: currentUser.id,
            otherUserID: otherUserID
        )
        let member = try await client.channelMember(channelID: channel.id, userID: currentUser.id)
        let unread = try await client.channelUnread(userID: currentUser.id, channelID: channel.id)

        print("channel: \(channel.id)")
        print("type: \(channel.type)")
        print("self-user: \(currentUser.id)")
        print("other-user: \(otherUserID)")
        print("member-user: \(member.userId)")
        print("unread-messages: \(unread.msgCount)")
    }

    @MainActor
    static func runThreadsTest(client: MattermostClient) async throws {
        let user = try await client.currentUser()
        let teamID = try await resolvedTeamID(nil, client: client)
        let threadList = try await client.userThreads(
            userID: user.id,
            teamID: teamID,
            request: MattermostThreadListRequest(perPage: 5, extended: true)
        )
        let store = try MattermostStore(inMemory: true)
        try store.upsert(threads: threadList, userID: user.id, teamID: teamID)
        try store.save()

        let cachedThreads = try store.cachedThreadStates(userID: user.id, teamID: teamID)

        print("team: \(teamID)")
        print("threads: \(threadList.threads.count)")
        print("total-threads: \(threadList.total)")
        print("total-unread-threads: \(threadList.totalUnreadThreads)")
        print("decoded-threads: \(threadList.threads.allSatisfy { !$0.id.isEmpty })")
        print("cached-threads: \(cachedThreads.count)")

        if let firstThread = threadList.threads.first {
            let thread = try await client.userThread(
                userID: user.id,
                teamID: teamID,
                threadID: firstThread.id,
                extended: true
            )
            print("first-thread: \(thread.id)")
            print("first-thread-participants: \(thread.participants.count)")
        }
    }

    @MainActor
    static func runPropsTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let marker = "mmswift-test-props-\(Int(Date.now.timeIntervalSince1970))"
        let props: [String: MattermostJSONValue] = [
            "mmswift_test": .object([
                "marker": .string(marker),
                "ok": .bool(true),
                "count": .number(1),
            ]),
        ]
        let post = try await client.sendPost(channelID: channelID, message: marker, props: props)
        var deletedPost = false

        do {
            let fetched = try await client.post(id: post.id)
            let store = try MattermostStore(inMemory: true)
            try store.upsert(post: fetched)
            try store.save()
            let cachedPost = try store.cachedPost(id: post.id)
            let cachedProps = try cachedPost?.decodedProps()
            let deleteStatus = try await client.deletePost(id: post.id)
            deletedPost = true

            print("post: \(post.id)")
            print("fetched-props: \(fetched.props?["mmswift_test"] == props["mmswift_test"])")
            print("cached-props: \(cachedProps?["mmswift_test"] == props["mmswift_test"])")
            print("post-delete-status: \(deleteStatus.status)")
        } catch {
            if !deletedPost {
                _ = try? await client.deletePost(id: post.id)
            }
            throw error
        }
    }

    static func runReactionTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let user = try await client.currentUser()
        let marker = "mmswift-test-reaction-\(Int(Date.now.timeIntervalSince1970))"
        var post: MattermostPost?
        var reactionEmojiName: String?

        do {
            let createdPost = try await client.sendPost(channelID: channelID, message: marker)
            post = createdPost
            let reaction = try await client.addReaction(
                postID: createdPost.id,
                userID: user.id,
                emojiName: "smile"
            )
            reactionEmojiName = reaction.emojiName
            let reactions = try await client.reactions(postID: createdPost.id)
            let reactionDeleteStatus = try await client.removeReaction(
                postID: createdPost.id,
                userID: user.id,
                emojiName: reaction.emojiName
            )
            let postDeleteStatus = try await client.deletePost(id: createdPost.id)

            print("post: \(createdPost.id)")
            print("reaction: \(reaction.emojiName)")
            print("reaction-count: \(reactions.count)")
            print("reaction-delete-status: \(reactionDeleteStatus.status)")
            print("post-delete-status: \(postDeleteStatus.status)")
        } catch {
            if let postID = post?.id, let reactionEmojiName {
                _ = try? await client.removeReaction(postID: postID, userID: user.id, emojiName: reactionEmojiName)
            }
            _ = await cleanupPosts(client: client, postIDs: [post?.id].compactMap(\.self))
            throw error
        }
    }

    static func runPreferencesTest(client: MattermostClient) async throws {
        let preferences = try await client.preferences()
        let firstCategory = preferences.first?.category
        let categoryPreferences: [MattermostPreference]

        if let firstCategory, !firstCategory.isEmpty {
            categoryPreferences = try await client.preferences(category: firstCategory)
        } else {
            categoryPreferences = []
        }

        print("preferences: \(preferences.count)")
        print("first-category: \(firstCategory ?? "-")")
        print("category-preferences: \(categoryPreferences.count)")
        print("decoded-preferences: \(preferences.allSatisfy { !$0.userId.isEmpty && !$0.category.isEmpty && !$0.name.isEmpty })")
    }

    static func runPreferenceRoundTripTest(client: MattermostClient) async throws {
        let user = try await client.currentUser()
        let suffix = Int(Date.now.timeIntervalSince1970)
        let category = "mmswift_test"
        let name = "preference_roundtrip_\(suffix)"
        let preference = MattermostPreference(
            userId: user.id,
            category: category,
            name: name,
            value: "created-\(suffix)"
        )
        var saved = false

        do {
            let saveStatus = try await client.savePreferences([preference], userID: user.id)
            saved = true
            let loaded = try await client.preference(userID: user.id, category: category, name: name)
            let categoryPreferences = try await client.preferences(userID: user.id, category: category)
            let deleteStatus = try await client.deletePreferences([preference], userID: user.id)
            saved = false
            let afterDelete: [MattermostPreference]
            do {
                afterDelete = try await client.preferences(userID: user.id, category: category)
            } catch MattermostError.httpStatus(let code, _) where code == 404 {
                afterDelete = []
            }
            let stillPresent = afterDelete.contains { $0.category == category && $0.name == name }

            print("preference: \(preference.id)")
            print("save-status: \(saveStatus.status)")
            print("loaded: \(loaded == preference)")
            print("listed-in-category: \(categoryPreferences.contains(preference))")
            print("delete-status: \(deleteStatus.status)")
            print("deleted: \(!stillPresent)")
        } catch {
            if saved {
                _ = try? await client.deletePreferences([preference], userID: user.id)
            }
            throw error
        }
    }

    static func runSearchTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let channel = try await client.channel(id: channelID)
        let teamID = if let channelTeamID = channel.teamId, !channelTeamID.isEmpty {
            channelTeamID
        } else {
            try await loadTeamID(client: client)
        }
        let marker = "mmswifttestsearch\(Int(Date.now.timeIntervalSince1970))"
        var post: MattermostPost?

        do {
            let createdPost = try await client.sendPost(channelID: channelID, message: marker)
            post = createdPost
            let results = try await waitForSearchResult(
                client: client,
                teamID: teamID,
                terms: marker,
                postID: createdPost.id,
                timeoutSeconds: 15
            )
            let deleteStatus = try await client.deletePost(id: createdPost.id)

            print("post: \(createdPost.id)")
            print("search-results: \(results.orderedPosts.count)")
            print("found-created-post: \(results.posts[createdPost.id] != nil)")
            print("post-delete-status: \(deleteStatus.status)")
        } catch {
            _ = await cleanupPosts(client: client, postIDs: [post?.id].compactMap(\.self))
            throw error
        }
    }

    static func runFileTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let marker = "mmswift-test-file-\(Int(Date.now.timeIntervalSince1970))"
        let filename = "\(marker).txt"
        let payload = Data("hello from \(marker)\n".utf8)
        let upload = try await client.uploadFile(
            channelID: channelID,
            filename: filename,
            data: payload,
            contentType: "text/plain"
        )
        guard let fileInfo = upload.fileInfos.first else {
            throw CLIError.usage("Mattermost did not return uploaded file metadata.")
        }

        var post: MattermostPost?

        do {
            let createdPost = try await client.sendPost(
                channelID: channelID,
                message: marker,
                fileIDs: [fileInfo.id]
            )
            post = createdPost
            let attachedFileInfos = try await client.fileInfos(postID: createdPost.id)
            let downloaded = try await client.downloadFile(id: fileInfo.id)
            let deleteStatus = try await client.deletePost(id: createdPost.id)

            print("file: \(fileInfo.id)")
            print("post: \(createdPost.id)")
            print("attached-files: \(attachedFileInfos.count)")
            print("downloaded-bytes: \(downloaded.count)")
            print("download-matches: \(downloaded == payload)")
            print("post-delete-status: \(deleteStatus.status)")
        } catch {
            _ = await cleanupPosts(client: client, postIDs: [post?.id].compactMap(\.self))
            throw error
        }
    }

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
        let channels = try await loadChannels(client: client)
        guard !channels.isEmpty else {
            throw CLIError.usage("No joined channels are available for all-channel backfill verification.")
        }

        let store = try MattermostStore(inMemory: true)
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

        let backfill = try await waitForLiveSyncBackfill(recorder: recorder, timeoutSeconds: 30)
        guard backfill.postSyncs.count == channels.count else {
            throw CLIError.usage(
                "All-channel backfill synced \(backfill.postSyncs.count) channel(s), expected \(channels.count)."
            )
        }

        let backfilledPosts = backfill.postSyncs.reduce(0) { count, sync in
            count + sync.posts.count
        }

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

    static func runFailureCleanupTest(client: MattermostClient) async throws {
        let teamID = try await loadTeamID(client: client)
        let suffix = testSuffix()
        let originalCategoryOrder = try await client.sidebarCategoryOrder(teamID: teamID)
        var createdChannel: MattermostChannel?
        var createdCategory: MattermostSidebarCategory?
        var createdPostIDs: [String] = []
        var simulatedFailureReached = false

        do {
            let channel = try await client.createChannel(
                teamID: teamID,
                name: "mmswift-test-cleanup-\(suffix)",
                displayName: "MattermostSwift Cleanup \(suffix)",
                purpose: "Created by MattermostSwiftCLI forced cleanup verification."
            )
            createdChannel = channel

            let category = try await client.createSidebarCategory(
                teamID: teamID,
                displayName: "MattermostSwift Cleanup \(suffix)"
            )
            createdCategory = category

            _ = try await client.moveChannelToSidebarCategory(
                teamID: teamID,
                channelID: channel.id,
                categoryID: category.id,
                position: 0
            )

            let post = try await client.sendPost(
                channelID: channel.id,
                message: "mmswift-test-cleanup-\(suffix)"
            )
            createdPostIDs.append(post.id)

            simulatedFailureReached = true
            throw CLIError.usage("Simulated failure after creating temporary e2e resources.")
        } catch {
            let cleanup = await cleanupE2EResources(
                client: client,
                teamID: teamID,
                postIDs: createdPostIDs,
                categoryID: createdCategory?.id,
                channelID: createdChannel?.id,
                originalCategoryOrder: originalCategoryOrder
            )

            guard simulatedFailureReached else {
                throw error
            }
            guard cleanup.deletedPosts == createdPostIDs.count,
                  cleanup.deletedCategory,
                  cleanup.deletedChannel,
                  cleanup.restoredOrder else {
                throw CLIError.usage("Forced cleanup verification left temporary e2e resources behind.")
            }

            print("team: \(teamID)")
            print("channel: \(createdChannel?.id ?? "-")")
            print("category: \(createdCategory?.id ?? "-")")
            print("posts: \(createdPostIDs.count)")
            print("simulated-failure: true")
            print("cleanup-posts: \(cleanup.deletedPosts)")
            print("cleanup-category: \(cleanup.deletedCategory)")
            print("cleanup-channel: \(cleanup.deletedChannel)")
            print("cleanup-order-restored: \(cleanup.restoredOrder)")
        }
    }

    static func runResidueAudit(client: MattermostClient) async throws {
        let teamID = try await loadTeamID(client: client)
        let channels = try await loadChannels(client: client)
            .filter(isActiveTestChannel)
            .sorted(by: channelSort)
        let categories = try await client.sidebarCategories(teamID: teamID)
            .filter(isTestSidebarCategory)
            .sorted(by: sidebarCategorySort)

        print("team: \(teamID)")
        print("residue-channels: \(channels.count)")
        for channel in channels {
            print("channel: \(channel.id)\t\(channel.name)\t\(channel.displayName)")
        }
        print("residue-categories: \(categories.count)")
        for category in categories {
            print("category: \(category.id)\t\(category.displayName)")
        }

        guard channels.isEmpty, categories.isEmpty else {
            throw CLIError.usage("Temporary MattermostSwift e2e resources remain on the server.")
        }
    }

    static func runTypingTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let currentUser = try await client.currentUser()
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
        let status = try await client.sendTyping(channelID: channelID)

        print("status: \(status.status)")

        if let typing = try await optionalTypingEvent(
            recorder: recorder,
            channelID: channelID,
            userID: currentUser.id,
            timeoutSeconds: 10
        ) {
            print("event-received: true")
            print("event: typing")
            print("event-channel: \(typing.channelID ?? "-")")
            print("event-user: \(typing.userID ?? "-")")
        } else {
            print("event-received: false")
        }
    }


    static func runChannelTest(client: MattermostClient) async throws {
        let teamID = try await loadTeamID(client: client)
        let suffix = String(Int(Date.now.timeIntervalSince1970))
        let name = "mmswift-test-\(suffix)"
        let renamedName = "mmswift-test-renamed-\(suffix)"
        var channel: MattermostChannel?

        do {
            let createdChannel = try await client.createChannel(
                teamID: teamID,
                name: name,
                displayName: "MattermostSwift Test \(suffix)",
                purpose: "Created by MattermostSwiftCLI e2e verification."
            )
            channel = createdChannel
            let patched = try await client.patchChannel(
                id: createdChannel.id,
                name: renamedName,
                displayName: "MattermostSwift Test Renamed \(suffix)"
            )
            let member = try await client.channelMember(channelID: createdChannel.id)
            let unread = try await client.channelUnread(channelID: createdChannel.id)
            let view = try await client.viewChannel(channelID: createdChannel.id)
            let deleteStatus = try await client.deleteChannel(id: createdChannel.id)

            print("channel: \(createdChannel.id)")
            print("created-name: \(createdChannel.name)")
            print("renamed-name: \(patched.name)")
            print("member-user: \(member.userId)")
            print("unread-messages: \(unread.msgCount)")
            print("view-status: \(view.status)")
            print("delete-status: \(deleteStatus.status)")
        } catch {
            if let channelID = channel?.id {
                _ = try? await client.deleteChannel(id: channelID)
            }
            throw error
        }
    }

    static func runSidebarCategoryTest(client: MattermostClient) async throws {
        let teamID = try await loadTeamID(client: client)
        let suffix = String(Int(Date.now.timeIntervalSince1970))
        let originalOrder = try await client.sidebarCategoryOrder(teamID: teamID)
        var category: MattermostSidebarCategory?

        do {
            let createdCategory = try await client.createSidebarCategory(
                teamID: teamID,
                displayName: "MattermostSwift Test \(suffix)"
            )
            category = createdCategory
            let updated = try await client.updateSidebarCategory(
                teamID: teamID,
                categoryID: createdCategory.id,
                displayName: "MattermostSwift Test Renamed \(suffix)",
                channelIDs: createdCategory.channelIds
            )
            let orderWithCategory = try await client.sidebarCategoryOrder(teamID: teamID)
            let deleted = try await client.deleteSidebarCategory(teamID: teamID, categoryID: createdCategory.id)
            let restoredOrder = try await client.updateSidebarCategoryOrder(
                teamID: teamID,
                order: originalOrder.filter { $0 != createdCategory.id }
            )

            print("category: \(createdCategory.id)")
            print("created-name: \(createdCategory.displayName)")
            print("renamed-name: \(updated.displayName)")
            print("order-contained-category: \(orderWithCategory.contains(createdCategory.id))")
            print("delete-status: \(deleted.status)")
            print("restored-order-count: \(restoredOrder.count)")
        } catch {
            let categoryID = category?.id
            if let categoryID {
                _ = try? await client.deleteSidebarCategory(teamID: teamID, categoryID: categoryID)
            }
            _ = try? await client.updateSidebarCategoryOrder(
                teamID: teamID,
                order: categoryID.map { id in originalOrder.filter { $0 != id } } ?? originalOrder
            )
            throw error
        }
    }

    static func runSidebarMoveTest(client: MattermostClient) async throws {
        let teamID = try await loadTeamID(client: client)
        let suffix = String(Int(Date.now.timeIntervalSince1970))
        let originalOrder = try await client.sidebarCategoryOrder(teamID: teamID)
        var channel: MattermostChannel?
        var category: MattermostSidebarCategory?

        do {
            let createdChannel = try await client.createChannel(
                teamID: teamID,
                name: "mmswift-test-move-\(suffix)",
                displayName: "MattermostSwift Move Test \(suffix)",
                purpose: "Created by MattermostSwiftCLI sidebar move verification."
            )
            channel = createdChannel
            let createdCategory = try await client.createSidebarCategory(
                teamID: teamID,
                displayName: "MattermostSwift Move Test \(suffix)"
            )
            category = createdCategory

            let moveResult = try await client.moveChannelToSidebarCategory(
                teamID: teamID,
                channelID: createdChannel.id,
                categoryID: createdCategory.id,
                position: 0
            )
            let movedCategory = moveResult.categories.first { $0.id == createdCategory.id }
            let deletedCategory = try await client.deleteSidebarCategory(teamID: teamID, categoryID: createdCategory.id)
            let deleteChannelStatus = try await client.deleteChannel(id: createdChannel.id)
            let restoredOrder = try await client.updateSidebarCategoryOrder(
                teamID: teamID,
                order: originalOrder.filter { $0 != createdCategory.id }
            )

            print("channel: \(createdChannel.id)")
            print("category: \(createdCategory.id)")
            print("updated-categories: \(moveResult.updatedCategories.count)")
            print("category-contained-channel: \(movedCategory?.channelIds.contains(createdChannel.id) == true)")
            print("category-first-channel: \(movedCategory?.channelIds.first == createdChannel.id)")
            print("delete-category-status: \(deletedCategory.status)")
            print("delete-channel-status: \(deleteChannelStatus.status)")
            print("restored-order-count: \(restoredOrder.count)")
        } catch {
            let categoryID = category?.id
            if let categoryID {
                _ = try? await client.deleteSidebarCategory(teamID: teamID, categoryID: categoryID)
            }
            if let channelID = channel?.id {
                _ = try? await client.deleteChannel(id: channelID)
            }
            _ = try? await client.updateSidebarCategoryOrder(
                teamID: teamID,
                order: categoryID.map { id in originalOrder.filter { $0 != id } } ?? originalOrder
            )
            throw error
        }
    }

    static func waitForEvents(
        recorder: LiveEventRecorder,
        minimumCount: Int,
        timeoutSeconds: Int
    ) async throws {
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date.now < deadline {
            if let error = await recorder.error {
                throw error
            }
            if await recorder.count >= minimumCount {
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        throw CLIError.usage("Timed out waiting for Mattermost WebSocket events.")
    }

    static func waitForPostEvent(
        recorder: LiveEventRecorder,
        eventName: String,
        postID: String,
        timeoutSeconds: Int
    ) async throws -> MattermostLiveEvent {
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date.now < deadline {
            if let error = await recorder.error {
                throw error
            }
            if let event = await recorder.postEvent(named: eventName, postID: postID) {
                return event
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        throw CLIError.usage("Timed out waiting for Mattermost WebSocket \(eventName) event.")
    }

    static func waitForTypingEvent(
        recorder: LiveEventRecorder,
        channelID: String,
        userID: String,
        timeoutSeconds: Int
    ) async throws -> MattermostTypingEvent {
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date.now < deadline {
            if let error = await recorder.error {
                throw error
            }
            if let event = await recorder.typingEvent(channelID: channelID, userID: userID) {
                return event
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        throw CLIError.usage("Timed out waiting for Mattermost WebSocket typing event.")
    }

    static func waitForLiveSyncBackfill(
        recorder: LiveSyncRecorder,
        timeoutSeconds: Int
    ) async throws -> MattermostLiveBackfillResult {
        try await waitForLiveSyncBackfillCount(
            recorder: recorder,
            count: 1,
            timeoutSeconds: timeoutSeconds
        )[0]
    }

    static func waitForLiveSyncBackfillCount(
        recorder: LiveSyncRecorder,
        count: Int,
        timeoutSeconds: Int
    ) async throws -> [MattermostLiveBackfillResult] {
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date.now < deadline {
            if let error = await recorder.error {
                throw error
            }
            let backfills = await recorder.backfills
            if backfills.count >= count {
                return backfills
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        throw CLIError.usage("Timed out waiting for Mattermost live sync backfill count \(count).")
    }

    static func waitForLiveSyncPost(
        recorder: LiveSyncRecorder,
        postID: String,
        timeoutSeconds: Int
    ) async throws -> MattermostPost {
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date.now < deadline {
            if let error = await recorder.error {
                throw error
            }
            if let post = await recorder.appliedPost(id: postID) {
                return post
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        throw CLIError.usage("Timed out waiting for Mattermost live sync posted event.")
    }

    static func waitForSearchResult(
        client: MattermostClient,
        teamID: String,
        terms: String,
        postID: String,
        timeoutSeconds: Int
    ) async throws -> MattermostPostSearchResults {
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeoutSeconds))
        var latestResults: MattermostPostSearchResults?
        while Date.now < deadline {
            let results = try await client.searchPosts(teamID: teamID, terms: terms)
            latestResults = results
            if results.posts[postID] != nil {
                return results
            }
            try await Task.sleep(for: .milliseconds(500))
        }

        let count = latestResults?.orderedPosts.count ?? 0
        throw CLIError.usage("Timed out waiting for Mattermost search to index post \(postID); latest result count: \(count).")
    }

    static func optionalTypingEvent(
        recorder: LiveEventRecorder,
        channelID: String,
        userID: String,
        timeoutSeconds: Int
    ) async throws -> MattermostTypingEvent? {
        do {
            return try await waitForTypingEvent(
                recorder: recorder,
                channelID: channelID,
                userID: userID,
                timeoutSeconds: timeoutSeconds
            )
        } catch CLIError.usage(let message) where message.contains("typing event") {
            return nil
        }
    }


    static func resolvedStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let url: URL

        if let rawPath = ProcessInfo.processInfo.environment["MATTERMOST_STORE_PATH"], !rawPath.isEmpty {
            url = URL(fileURLWithPath: rawPath).standardizedFileURL
        } else {
            let currentDirectory = URL(
                fileURLWithPath: fileManager.currentDirectoryPath,
                isDirectory: true
            )
            url = currentDirectory
                .appendingPathComponent(".mattermostswift", isDirectory: true)
                .appendingPathComponent("MattermostSwift.sqlite")
                .standardizedFileURL
        }

        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return url
    }

    static func testSuffix() -> String {
        let timestamp = Int(Date.now.timeIntervalSince1970)
        let random = UUID().uuidString
            .lowercased()
            .prefix(8)
        return "\(timestamp)-\(random)"
    }

    static func requireFirst<Value>(_ values: [Value], _ message: String) throws -> Value {
        guard let value = values.first else {
            throw CLIError.usage(message)
        }
        return value
    }

    static func cleanupPosts<PostIDs: Sequence>(
        client: MattermostClient,
        postIDs: PostIDs
    ) async -> Int where PostIDs.Element == String {
        var deletedPosts = 0
        for postID in postIDs {
            if (try? await client.deletePost(id: postID)) != nil {
                deletedPosts += 1
            }
        }
        return deletedPosts
    }

    static func cleanupE2EResources(
        client: MattermostClient,
        teamID: String,
        postIDs: [String],
        categoryID: String?,
        channelID: String?,
        originalCategoryOrder: [String]
    ) async -> E2ECleanupResult {
        let deletedPosts = await cleanupPosts(client: client, postIDs: postIDs.reversed())

        let deletedCategory: Bool
        if let categoryID {
            deletedCategory = (try? await client.deleteSidebarCategory(teamID: teamID, categoryID: categoryID)) != nil
        } else {
            deletedCategory = false
        }

        let deletedChannel: Bool
        if let channelID {
            deletedChannel = (try? await client.deleteChannel(id: channelID)) != nil
        } else {
            deletedChannel = false
        }

        let restoredOrder = (try? await client.updateSidebarCategoryOrder(
            teamID: teamID,
            order: originalCategoryOrder.filter { $0 != categoryID }
        )) != nil

        return E2ECleanupResult(
            deletedPosts: deletedPosts,
            deletedCategory: deletedCategory,
            deletedChannel: deletedChannel,
            restoredOrder: restoredOrder
        )
    }

    static func isActiveTestChannel(_ channel: MattermostChannel) -> Bool {
        !channel.isDeleted && (
            isTestResourceName(channel.name)
                || isTestResourceName(channel.displayName)
                || isTestResourceName(channel.purpose ?? "")
        )
    }

    static func isTestSidebarCategory(_ category: MattermostSidebarCategory) -> Bool {
        category.type == "custom" && isTestResourceName(category.displayName)
    }

    static func isTestChannel(_ channel: MattermostChannel) -> Bool {
        isTestResourceName(channel.name) || isTestResourceName(channel.displayName)
    }

    static func isSafeTestChannelName(_ value: String) -> Bool {
        value.hasPrefix("mmswift-test")
            && value.unicodeScalars.allSatisfy { scalar in
                (97...122).contains(scalar.value)
                    || (48...57).contains(scalar.value)
                    || scalar.value == 45
            }
    }

    static func isTestResourceName(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("mmswift-test")
            || normalized.hasPrefix("mattermostswift test")
            || normalized.hasPrefix("mattermostswift move test")
            || normalized.hasPrefix("mattermostswift e2e")
            || normalized.hasPrefix("mattermostswift cleanup")
    }

}
