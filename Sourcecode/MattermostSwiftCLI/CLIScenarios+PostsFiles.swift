import Foundation
@_spi(Testing) import MattermostSwift

// Posts, threads, reactions, preferences, search, files, channels and typing scenarios.
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

            let thread = try await client.thread(
                postID: root.id,
                options: MattermostThreadOptions()
            )

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
            print("sidebar-moved: \(movedCategory?.channelIDs.first == channel.id)")
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
            let thread = try await client.thread(
                postID: createdRoot.id,
                options: MattermostThreadOptions()
            )
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
        let decodedPosts = postList.posts.values.allSatisfy { !$0.id.isEmpty && $0.channelID == channelID }

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
        let unread = try await client.channelUnread(channelID: channel.id, userID: currentUser.id)

        print("channel: \(channel.id)")
        print("type: \(channel.type.rawValue)")
        print("self-user: \(currentUser.id)")
        print("other-user: \(otherUserID)")
        print("member-user: \(member.userID)")
        print("unread-messages: \(unread.msgCount)")
    }

    @MainActor
    static func runThreadsTest(client: MattermostClient) async throws {
        let user = try await client.currentUser()
        let teamID = try await resolvedTeamID(nil, client: client)
        let threadList = try await client.userThreads(
            teamID: teamID,
            userID: user.id,
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
                teamID: teamID,
                threadID: firstThread.id,
                userID: user.id,
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
                "count": .integer(1),
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

            let fetchedPropsMatch = fetched.props?["mmswift_test"] == props["mmswift_test"]
            let cachedPropsMatch = cachedProps?["mmswift_test"] == props["mmswift_test"]
            guard fetchedPropsMatch else {
                throw CLIError.usage("Mattermost post props changed during the server round trip.")
            }
            guard cachedPropsMatch else {
                throw CLIError.usage("Mattermost post props changed during the cache round trip.")
            }

            print("post: \(post.id)")
            print("fetched-props: \(fetchedPropsMatch)")
            print("cached-props: \(cachedPropsMatch)")
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
        print("decoded-preferences: \(preferences.allSatisfy { !$0.userID.isEmpty && !$0.category.isEmpty && !$0.name.isEmpty })")
    }

    static func runPreferenceRoundTripTest(client: MattermostClient) async throws {
        let user = try await client.currentUser()
        let suffix = Int(Date.now.timeIntervalSince1970)
        let category = "mmswift_test"
        let name = "preference_roundtrip_\(suffix)"
        let preference = MattermostPreference(
            userID: user.id,
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
            } catch MattermostError.httpStatus(let code, _, _) where code == 404 {
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
        let teamID = if let channelTeamID = channel.teamID, !channelTeamID.isEmpty {
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
            print("member-user: \(member.userID)")
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
}
