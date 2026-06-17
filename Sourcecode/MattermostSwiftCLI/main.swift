import Foundation
@_spi(Testing) import MattermostSwift

@main
struct MattermostSwiftCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let command = Command(arguments: Array(CommandLine.arguments.dropFirst()))
        if case .loginTest = command {
            try await runLoginTest()
            return
        }

        let client = try MattermostClient.liveFromEnvironment()

        switch command {
        case .me:
            let user = try await client.currentUser()
            printUser(user)
        case .getUser(let userID):
            let user = try await client.user(id: userID)
            printUser(user)
        case .profileImage(let userID):
            let resolvedUserID = try await resolvedUserID(userID, client: client)
            let data = try await client.userProfileImage(userID: resolvedUserID)
            printImageDownload(label: "profile-image", userID: resolvedUserID, data: data)
        case .defaultProfileImage(let userID):
            let resolvedUserID = try await resolvedUserID(userID, client: client)
            let data = try await client.defaultUserProfileImage(userID: resolvedUserID)
            printImageDownload(label: "default-profile-image", userID: resolvedUserID, data: data)
        case .getUsers(let userIDs):
            let users = try await client.users(ids: userIDs)
            printUsers(users)
        case .getUsersByUsername(let usernames):
            let users = try await client.users(usernames: usernames)
            printUsers(users)
        case .listChannelUsers(let channelID):
            let users = try await client.users(channelID: resolvedChannelID(channelID), perPage: 20)
            printUsers(users)
        case .searchUsers(let terms):
            let users = try await client.searchUsers(term: terms, limit: 20)
            printUsers(users)
        case .autocompleteUsers(let name):
            let autocomplete = try await client.autocompleteUsers(name: name, limit: 20)
            printUserAutocomplete(autocomplete)
        case .knownUsers(let includeProfiles):
            let userIDs = try await client.knownUserIDs()
            print("known-users: \(userIDs.count)")
            if includeProfiles {
                let users = try await client.users(ids: userIDs)
                printUsers(users)
            } else {
                for userID in userIDs.sorted() {
                    print(userID)
                }
            }
        case .status(let userID):
            let resolvedUserID = try await resolvedUserID(userID, client: client)
            let status = try await client.status(userID: resolvedUserID)
            printStatus(status)
        case .serverInfo:
            let serverInfo = try await client.serverInfo()
            printServerInfo(serverInfo)
        case .listTeams:
            let teams = try await client.teams()
            printTeams(teams)
        case .teamInfo(let teamID):
            let team = try await client.team(id: try await resolvedTeamID(teamID, client: client))
            printTeam(team)
        case .listTeamMembers(let teamID):
            let members = try await client.teamMembers(
                teamID: try await resolvedTeamID(teamID, client: client),
                page: 0,
                perPage: 20,
                excludeDeletedUsers: true
            )
            printTeamMembers(members)
        case .listChannels:
            let channels = try await loadChannels(client: client)
            printChannels(channels)
        case .listPublicChannels(let teamID):
            let channels = try await client.publicChannels(
                teamID: try await resolvedTeamID(teamID, client: client),
                page: 0,
                perPage: 20
            )
            printChannels(channels)
        case .channelInfo(let channelID):
            let channel = try await client.channel(id: resolvedChannelID(channelID))
            printChannel(channel)
        case .channelByName(let teamID, let name):
            let channel = try await client.channel(
                teamID: try await resolvedTeamID(teamID, client: client),
                name: name
            )
            printChannel(channel)
        case .channelByTeamName(let teamName, let channelName):
            let channel = try await client.channel(
                teamName: teamName,
                channelName: channelName
            )
            printChannel(channel)
        case .channelStats(let channelID):
            let stats = try await client.channelStats(channelID: resolvedChannelID(channelID))
            printChannelStats(stats)
        case .channelTimezones(let channelID):
            let timezones = try await client.channelTimezones(channelID: resolvedChannelID(channelID))
            printTimezones(timezones)
        case .channelMemberCounts(let channelIDs):
            let resolvedChannelIDs = try channelIDs.isEmpty ? [resolvedChannelID(nil)] : channelIDs
            let counts = try await client.channelMemberCounts(channelIDs: resolvedChannelIDs)
            printChannelMemberCounts(counts)
        case .searchChannels(let terms):
            if let teamID = try? await loadTeamID(client: client) {
                let channels = try await client.searchTeamChannels(teamID: teamID, term: terms)
                printChannels(channels)
            } else {
                let results = try await client.searchChannels(term: terms, perPage: 20)
                printChannels(results.channels)
            }
        case .searchGroupChannels(let terms):
            let channels = try await client.searchGroupChannels(term: terms)
            printChannels(channels)
        case .directChannelTest(let userID):
            try await runDirectChannelTest(client: client, userID: userID)
        case .createGroupChannel(let userIDs):
            let channel = try await client.createGroupChannel(userIDs: userIDs)
            printChannel(channel)
        case .channelMember(let channelID):
            let member = try await client.channelMember(channelID: resolvedChannelID(channelID))
            printChannelMember(member)
        case .listChannelMembers(let channelID):
            let members = try await client.channelMembers(
                channelID: resolvedChannelID(channelID),
                page: 0,
                perPage: 20
            )
            printChannelMembers(members)
        case .channelMembersByID(let channelID, let userIDs):
            let members = try await client.channelMembers(
                channelID: resolvedChannelID(channelID),
                userIDs: userIDs
            )
            printChannelMembers(members)
        case .addChannelMember(let channelID, let userID):
            let member = try await client.addChannelMember(
                channelID: resolvedChannelID(channelID),
                userID: userID
            )
            printChannelMember(member)
        case .removeChannelMember(let channelID, let userID):
            let status = try await client.removeChannelMember(
                channelID: resolvedChannelID(channelID),
                userID: userID
            )
            print("status: \(status.status)")
        case .channelUnread(let channelID):
            let unread = try await client.channelUnread(channelID: resolvedChannelID(channelID))
            printChannelUnread(unread)
        case .notifyPropsTest:
            try await runNotifyPropsTest(client: client)
        case .listUnreadPosts(let channelID):
            let postList = try await client.postsAroundLastUnread(
                channelID: resolvedChannelID(channelID),
                limitBefore: 20,
                limitAfter: 20,
                collapsedThreads: true,
                collapsedThreadsExtended: true
            )
            printPosts(postList.orderedPosts)
        case .viewChannel(let channelID):
            let response = try await client.viewChannel(channelID: resolvedChannelID(channelID))
            print("status: \(response.status)")
        case .sendTyping(let channelID):
            let status = try await client.sendTyping(channelID: resolvedChannelID(channelID))
            print("status: \(status.status)")
        case .listCategories:
            let categories = try await loadCategories(client: client)
            printCategories(categories)
        case .listThreads(let teamID):
            let threads = try await client.userThreads(
                teamID: try await resolvedTeamID(teamID, client: client),
                request: MattermostThreadListRequest(perPage: 20, extended: false)
            )
            printThreads(threads)
        case .listPreferences(let category):
            let preferences = if let category {
                try await client.preferences(category: category)
            } else {
                try await client.preferences()
            }
            printPreferences(preferences)
        case .preferencesTest:
            try await runPreferencesTest(client: client)
        case .preferenceRoundTripTest:
            try await runPreferenceRoundTripTest(client: client)
        case .sidebarCategoryTest:
            try await runSidebarCategoryTest(client: client)
        case .sidebarMoveTest:
            try await runSidebarMoveTest(client: client)
        case .createTestChannel:
            try await runCreateTestChannel(client: client)
        case .renameTestChannel(let channelID, let name):
            try await runRenameTestChannel(client: client, channelID: channelID, name: name)
        case .archiveChannel(let channelID):
            try await runArchiveChannel(client: client, channelID: channelID)
        case .listPosts(let channelID):
            let postList = try await client.posts(channelID: resolvedChannelID(channelID), perPage: 20)
            printPosts(postList.orderedPosts)
        case .pinnedPosts(let channelID):
            let postList = try await client.pinnedPosts(channelID: resolvedChannelID(channelID))
            printPosts(postList.orderedPosts)
        case .listPostUpdates(let channelID, let since):
            let postList = try await client.postsSince(channelID: resolvedChannelID(channelID), since: since)
            printPosts(postList.orderedPosts)
        case .sendMessage(let channelID, let message):
            let post = try await client.sendPost(channelID: resolvedChannelID(channelID), message: message)
            printPost(post)
        case .editMessage(let postID, let message):
            let post = try await client.editPost(id: postID, message: message)
            printPost(post)
        case .deleteMessage(let postID):
            let status = try await client.deletePost(id: postID)
            print("status: \(status.status)")
        case .threadTest:
            try await runThreadTest(client: client)
        case .timelineTest:
            try await runTimelineTest(client: client)
        case .sinceTest:
            try await runSinceTest(client: client)
        case .unreadPostsTest:
            try await runUnreadPostsTest(client: client)
        case .threadsTest:
            try await runThreadsTest(client: client)
        case .propsTest:
            try await runPropsTest(client: client)
        case .reactionTest:
            try await runReactionTest(client: client)
        case .search(let terms):
            let teamID = try await loadTeamID(client: client)
            let results = try await client.searchPosts(teamID: teamID, terms: terms, perPage: 20)
            printSearchResults(results)
        case .searchTest:
            try await runSearchTest(client: client)
        case .uploadFile(let channelID, let path):
            let fileInfo = try await uploadFile(client: client, channelID: channelID, path: path)
            printFileInfo(fileInfo)
        case .downloadFile(let fileID, let path):
            try await downloadFile(client: client, fileID: fileID, path: path)
        case .fileTest:
            try await runFileTest(client: client)
        case .listEmoji:
            let emoji = try await client.customEmoji(perPage: 20)
            printEmoji(emoji)
        case .searchEmoji(let term):
            let emoji = try await client.searchCustomEmoji(term: term)
            printEmoji(emoji)
        case .streamEvents(let limit):
            try await streamEvents(client: client, limit: limit)
        case .webSocketTest:
            try await runWebSocketTest(client: client)
        case .liveSyncTest:
            try await runLiveSyncTest(client: client)
        case .reconnectBackfillTest:
            try await runReconnectBackfillTest(client: client)
        case .deletionBackfillTest:
            try await runDeletionBackfillTest(client: client)
        case .liveSyncReconnectTest:
            try await runLiveSyncReconnectTest(client: client)
        case .allChannelBackfillTest:
            try await runAllChannelBackfillTest(client: client)
        case .allChannelReconnectTest:
            try await runAllChannelReconnectTest(client: client)
        case .failureCleanupTest:
            try await runFailureCleanupTest(client: client)
        case .residueAudit:
            try await runResidueAudit(client: client)
        case .typingTest:
            try await runTypingTest(client: client)
        case .channelTest:
            try await runChannelTest(client: client)
        case .e2eTest:
            try await runE2ETest(client: client)
        case .sync(let channelID):
            try await runSync(client: client, channelID: channelID)
        case .cacheCheck(let channelID):
            try await runCacheCheck(channelID: channelID)
        case .loginTest:
            try await runLoginTest()
        case .check:
            let user = try await client.currentUser()
            let channels = try await loadChannels(client: client)
            print("Authenticated as \(user.username) (\(user.id))")
            print("Loaded \(channels.count) channel\(channels.count == 1 ? "" : "s")")
        case .help:
            printHelp()
        }
    }

    private static func resolvedChannelID(_ channelID: String?) throws -> String {
        if let channelID, !channelID.isEmpty {
            return channelID
        }

        if let channelID = ProcessInfo.processInfo.environment["MATTERMOST_CHANNEL_ID"], !channelID.isEmpty {
            return channelID
        }

        throw CLIError.usage("Provide a channel id or set MATTERMOST_CHANNEL_ID.")
    }

    private static func resolvedUserID(_ userID: String?, client: MattermostClient) async throws -> String {
        if let userID, !userID.isEmpty {
            return userID
        }

        return try await client.currentUser().id
    }

    private static func resolvedTeamID(_ teamID: String?, client: MattermostClient) async throws -> String {
        if let teamID, !teamID.isEmpty {
            return teamID
        }

        return try await loadTeamID(client: client)
    }

    private static func loadTeamID(client: MattermostClient) async throws -> String {
        if let teamName = ProcessInfo.processInfo.environment["MATTERMOST_TEAM_NAME"], !teamName.isEmpty {
            return try await client.team(named: teamName).id
        }

        let channels = try await client.joinedChannelsAcrossTeams()
        if let teamID = channels.compactMap(\.teamId).first(where: { !$0.isEmpty }) {
            return teamID
        }

        throw MattermostError.missingEnvironmentVariable("MATTERMOST_TEAM_NAME")
    }

    private static func loadChannels(client: MattermostClient) async throws -> [MattermostChannel] {
        if let teamName = ProcessInfo.processInfo.environment["MATTERMOST_TEAM_NAME"], !teamName.isEmpty {
            let team = try await client.team(named: teamName)
            return try await client.joinedChannels(teamID: team.id)
        }

        return try await client.joinedChannelsAcrossTeams()
    }

    private static func loadCategories(client: MattermostClient) async throws -> [MattermostSidebarCategory] {
        let teamID = try await loadTeamID(client: client)
        return try await client.sidebarCategories(teamID: teamID)
    }

    @MainActor
    private static func runE2ETest(client: MattermostClient) async throws {
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

    private static func runLoginTest() async throws {
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

    private static func runThreadTest(client: MattermostClient) async throws {
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
    private static func runTimelineTest(client: MattermostClient) async throws {
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

    private static func runSinceTest(client: MattermostClient) async throws {
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

    private static func runUnreadPostsTest(client: MattermostClient) async throws {
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

    private static func runNotifyPropsTest(client: MattermostClient) async throws {
        let channelID = try resolvedChannelID(nil)
        let props = try await client.channelMember(channelID: channelID).channelNotifyProps

        print("channel: \(channelID)")
        printNotifyProps(props)
        print("notify-raw-count: \(props.rawValues.count)")
    }

    private static func runDirectChannelTest(client: MattermostClient, userID: String?) async throws {
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
    private static func runThreadsTest(client: MattermostClient) async throws {
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
    private static func runPropsTest(client: MattermostClient) async throws {
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

    private static func runReactionTest(client: MattermostClient) async throws {
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

    private static func runPreferencesTest(client: MattermostClient) async throws {
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

    private static func runPreferenceRoundTripTest(client: MattermostClient) async throws {
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

    private static func runSearchTest(client: MattermostClient) async throws {
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

    private static func uploadFile(
        client: MattermostClient,
        channelID: String?,
        path: String
    ) async throws -> MattermostFileInfo {
        let resolvedChannelID = try resolvedChannelID(channelID)
        let fileURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: fileURL)
        let response = try await client.uploadFile(
            channelID: resolvedChannelID,
            filename: fileURL.lastPathComponent,
            data: data,
            contentType: contentType(for: fileURL)
        )

        guard let fileInfo = response.fileInfos.first else {
            throw CLIError.usage("Mattermost did not return uploaded file metadata.")
        }

        return fileInfo
    }

    private static func downloadFile(
        client: MattermostClient,
        fileID: String,
        path: String?
    ) async throws {
        let data = try await client.downloadFile(id: fileID)
        if let path, !path.isEmpty {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            print("downloaded-bytes: \(data.count)")
            print("path: \(path)")
        } else {
            FileHandle.standardOutput.write(data)
        }
    }

    private static func runFileTest(client: MattermostClient) async throws {
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

    private static func streamEvents(client: MattermostClient, limit: Int) async throws {
        var count = 0
        for try await event in client.liveEventStream().events() {
            printLiveEvent(event)
            count += 1
            if count >= limit {
                break
            }
        }
    }

    private static func runWebSocketTest(client: MattermostClient) async throws {
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
    private static func runLiveSyncTest(client: MattermostClient) async throws {
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
    private static func runReconnectBackfillTest(client: MattermostClient) async throws {
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
    private static func runDeletionBackfillTest(client: MattermostClient) async throws {
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
    private static func runLiveSyncReconnectTest(client: MattermostClient) async throws {
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
    private static func runAllChannelBackfillTest(client: MattermostClient) async throws {
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
    private static func runAllChannelReconnectTest(client: MattermostClient) async throws {
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

    private static func runFailureCleanupTest(client: MattermostClient) async throws {
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

    private static func runResidueAudit(client: MattermostClient) async throws {
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

    private static func runTypingTest(client: MattermostClient) async throws {
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


    private static func runChannelTest(client: MattermostClient) async throws {
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

    private static func runCreateTestChannel(client: MattermostClient) async throws {
        let teamID = try await loadTeamID(client: client)
        let suffix = String(Int(Date.now.timeIntervalSince1970 * 1000))
        let name = "mmswift-test-\(suffix)"
        let displayName = "MattermostSwift Test \(suffix)"
        let channel = try await client.createChannel(
            teamID: teamID,
            name: name,
            displayName: displayName,
            purpose: "Created by MattermostSwiftCLI test-channel verification."
        )

        print("channel: \(channel.id)")
        print("team: \(teamID)")
        print("name: \(channel.name)")
        print("display-name: \(channel.displayName)")
    }

    private static func runRenameTestChannel(
        client: MattermostClient,
        channelID: String?,
        name: String?
    ) async throws {
        guard let channelID, !channelID.isEmpty else {
            throw CLIError.usage("Provide a test channel id to rename.")
        }

        let channel = try await client.channel(id: channelID)
        guard isTestChannel(channel) else {
            throw CLIError.usage("Refusing to rename a channel that does not look like a MattermostSwift test channel.")
        }

        let suffix = String(Int(Date.now.timeIntervalSince1970 * 1000))
        let newName = name ?? "mmswift-test-renamed-\(suffix)"
        guard isSafeTestChannelName(newName) else {
            throw CLIError.usage("New test channel names must start with mmswift-test and contain only lowercase letters, numbers, and hyphens.")
        }

        let renamed = try await client.patchChannel(
            id: channelID,
            name: newName,
            displayName: "MattermostSwift Test Renamed \(suffix)"
        )

        print("channel: \(renamed.id)")
        print("old-name: \(channel.name)")
        print("name: \(renamed.name)")
        print("display-name: \(renamed.displayName)")
    }

    private static func runArchiveChannel(client: MattermostClient, channelID: String?) async throws {
        guard let channelID, !channelID.isEmpty else {
            throw CLIError.usage("Provide a test channel id to archive.")
        }

        let channel = try await client.channel(id: channelID)
        guard isTestChannel(channel) else {
            throw CLIError.usage("Refusing to archive a channel that does not look like a MattermostSwift test channel.")
        }

        let status = try await client.deleteChannel(id: channelID)
        print("channel: \(channelID)")
        print("archive-status: \(status.status)")
    }

    private static func runSidebarCategoryTest(client: MattermostClient) async throws {
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

    private static func runSidebarMoveTest(client: MattermostClient) async throws {
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

    @MainActor
    private static func runSync(client: MattermostClient, channelID: String?) async throws {
        let storeURL = try resolvedStoreURL()
        let store = try MattermostStore(url: storeURL)
        let resolvedPostChannelID = try? resolvedChannelID(channelID)
        let teamName = ProcessInfo.processInfo.environment["MATTERMOST_TEAM_NAME"]
        let result = try await client.syncService().sync(
            to: store,
            teamName: teamName,
            channelID: resolvedPostChannelID,
            options: MattermostSyncOptions(
                postPageSize: 60,
                maxPostPages: 3,
                includeChannelUsers: true,
                includeSidebarCategories: true,
                refreshUnreadForAllJoinedChannels: true
            )
        )

        print("store: \(storeURL.path)")
        print("synced-user: \(result.user.username)")
        print("synced-teams: \(result.syncedTeamsCount)")
        print("synced-users: \(result.syncedUsersCount)")
        print("synced-channels: \(result.channels.count)")
        print("synced-members: \(result.syncedMembersCount)")
        print("synced-unreads: \(result.syncedUnreadsCount)")
        print("synced-categories: \(result.syncedCategoriesCount)")
        if let postSync = result.postSync {
            print("synced-post-channel: \(postSync.channelID)")
            print("synced-posts: \(postSync.posts.count)")
            print("synced-post-pages: \(postSync.pageCount)")
            print("synced-post-cursor: \(postSync.cursorLastSyncAt)")
        }
        print("cached-teams: \(result.cachedTeamsCount)")
        print("cached-users: \(result.cachedUsersCount)")
        print("cached-channels: \(result.cachedChannelsCount)")
        print("cached-members: \(result.cachedMembersCount)")
        print("cached-unreads: \(result.cachedUnreadsCount)")
    }

    @MainActor
    private static func runCacheCheck(channelID: String?) async throws {
        let storeURL = try resolvedStoreURL()
        let store = try MattermostStore(url: storeURL)
        let teams = try store.cachedTeams()
        let users = try store.cachedUsers()
        let channels = try store.cachedChannels()
        let members = try store.cachedChannelMembers()
        let unreads = try store.cachedChannelUnreads()
        let categories = try store.cachedSidebarCategories()

        guard !users.isEmpty, !channels.isEmpty else {
            throw CLIError.usage("Cache is empty. Run `swift run MattermostSwiftCLI sync` first.")
        }

        print("store: \(storeURL.path)")
        print("cached-teams: \(teams.count)")
        print("cached-users: \(users.count)")
        print("cached-channels: \(channels.count)")
        print("cached-members: \(members.count)")
        print("cached-unreads: \(unreads.count)")
        print("cached-categories: \(categories.count)")

        if let resolvedPostChannelID = try? resolvedChannelID(channelID) {
            let posts = try store.cachedPosts(channelID: resolvedPostChannelID, limit: 60)
            let cursor = try store.cachedSyncCursor(scope: "channel-posts:\(resolvedPostChannelID)")
            print("cached-post-channel: \(resolvedPostChannelID)")
            print("cached-posts: \(posts.count)")
            if let cursor {
                print("cached-post-cursor: \(cursor.lastSyncAt)")
            }
        }
    }

    private static func printServerInfo(_ serverInfo: MattermostServerInfo) {
        print("status: \(serverInfo.ping.status)")

        if let databaseStatus = serverInfo.ping.databaseStatus, !databaseStatus.isEmpty {
            print("database: \(databaseStatus)")
        }

        if let filestoreStatus = serverInfo.ping.filestoreStatus, !filestoreStatus.isEmpty {
            print("filestore: \(filestoreStatus)")
        }

        if let searchBackend = serverInfo.ping.activeSearchBackend, !searchBackend.isEmpty {
            print("search: \(searchBackend)")
        }

        if let buildNumber = serverInfo.clientConfig.buildNumber, !buildNumber.isEmpty {
            print("build: \(buildNumber)")
        }

        if let buildHash = serverInfo.clientConfig.buildHash, !buildHash.isEmpty {
            print("build-hash: \(buildHash)")
        }

        if let collapsedThreads = serverInfo.clientConfig.collapsedThreads, !collapsedThreads.isEmpty {
            print("collapsed-threads: \(collapsedThreads)")
        }
    }

    private static func printUser(_ user: MattermostUser) {
        print("id: \(user.id)")
        print("username: \(user.username)")

        if let email = user.email, !email.isEmpty {
            print("email: \(email)")
        }

        let displayName = [user.firstName, user.lastName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !displayName.isEmpty {
            print("name: \(displayName)")
        }

        if let nickname = user.nickname, !nickname.isEmpty {
            print("nickname: \(nickname)")
        }
    }

    private static func printUsers(_ users: [MattermostUser]) {
        for user in users.sorted(by: userSort) {
            print("\(user.id)\t\(user.username)")
        }
    }

    private static func printImageDownload(label: String, userID: String, data: Data) {
        print("\(label): \(userID)")
        print("bytes: \(data.count)")
        print("signature: \(imageSignature(for: data))")
    }

    private static func imageSignature(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpeg"
        }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "gif"
        }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            return "webp-or-riff"
        }
        return "unknown"
    }

    private static func printUserAutocomplete(_ autocomplete: MattermostUserAutocomplete) {
        print("users: \(autocomplete.users.count)")
        print("in-channel: \(autocomplete.inChannel.count)")
        print("out-of-channel: \(autocomplete.outOfChannel.count)")
        printUsers(autocomplete.allUsers)
    }

    private static func userSort(_ lhs: MattermostUser, _ rhs: MattermostUser) -> Bool {
        lhs.username.localizedStandardCompare(rhs.username) == .orderedAscending
    }

    private static func printStatus(_ status: MattermostUserStatus) {
        print("\(status.userId)\t\(status.status)")
    }

    private static func printTeam(_ team: MattermostTeam) {
        print("id: \(team.id)")
        print("name: \(team.name)")
        print("display-name: \(team.displayName)")

        if let type = team.type, !type.isEmpty {
            print("type: \(type)")
        }

        if let description = team.description, !description.isEmpty {
            print("description: \(description)")
        }
    }

    private static func printTeams(_ teams: [MattermostTeam]) {
        for team in teams.sorted(by: teamSort) {
            print("\(team.id)\t\(team.name)\t\(team.displayName)")
        }
    }

    private static func printTeamMembers(_ members: [MattermostTeamMember]) {
        for member in members.sorted(by: teamMemberSort) {
            print("\(member.teamId)\t\(member.userId)\t\(member.roles ?? "")")
        }
    }

    private static func teamSort(_ lhs: MattermostTeam, _ rhs: MattermostTeam) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    private static func teamMemberSort(_ lhs: MattermostTeamMember, _ rhs: MattermostTeamMember) -> Bool {
        if lhs.teamId == rhs.teamId {
            return lhs.userId.localizedStandardCompare(rhs.userId) == .orderedAscending
        }
        return lhs.teamId.localizedStandardCompare(rhs.teamId) == .orderedAscending
    }

    private static func printCategories(_ categories: [MattermostSidebarCategory]) {
        for category in categories {
            print("\(category.id)\t\(category.type)\t\(category.displayName)\t\(category.channelIds.count) channels")
        }
    }

    private static func printPreferences(_ preferences: [MattermostPreference]) {
        for preference in preferences.sorted(by: preferenceSort) {
            print("\(preference.category)\t\(preference.name)\tvalue-bytes:\(preference.value.utf8.count)")
        }
    }

    private static func preferenceSort(_ lhs: MattermostPreference, _ rhs: MattermostPreference) -> Bool {
        if lhs.category == rhs.category {
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return lhs.category.localizedStandardCompare(rhs.category) == .orderedAscending
    }

    private static func printChannelMember(_ member: MattermostChannelMember) {
        print("channel: \(member.channelId)")
        print("user: \(member.userId)")
        if let msgCount = member.msgCount {
            print("messages-read: \(msgCount)")
        }
        if let mentionCount = member.mentionCount {
            print("mentions: \(mentionCount)")
        }
        printNotifyProps(member.channelNotifyProps)
    }

    private static func printChannelMembers(_ members: [MattermostChannelMember]) {
        for member in members.sorted(by: channelMemberSort) {
            print("\(member.channelId)\t\(member.userId)\t\(member.roles ?? "")")
        }
    }

    private static func channelMemberSort(
        _ lhs: MattermostChannelMember,
        _ rhs: MattermostChannelMember
    ) -> Bool {
        if lhs.channelId == rhs.channelId {
            return lhs.userId.localizedStandardCompare(rhs.userId) == .orderedAscending
        }
        return lhs.channelId.localizedStandardCompare(rhs.channelId) == .orderedAscending
    }

    private static func printNotifyProps(_ props: MattermostChannelNotifyProps) {
        for (name, value) in props.rawValues.sorted(by: { $0.key < $1.key }) {
            print("notify.\(name): \(value)")
        }
    }

    private static func printChannelUnread(_ unread: MattermostChannelUnread) {
        print("channel: \(unread.channelId)")
        if let teamID = unread.teamId, !teamID.isEmpty {
            print("team: \(teamID)")
        }
        print("messages: \(unread.msgCount)")
        print("mentions: \(unread.mentionCount)")
    }

    private static func printPosts(_ posts: [MattermostPost]) {
        for post in posts {
            printPost(post)
        }
    }

    private static func printSearchResults(_ results: MattermostPostSearchResults) {
        for post in results.orderedPosts.prefix(20) {
            printPost(post)
        }
    }

    private static func printPost(_ post: MattermostPost) {
        let message = post.message.replacing("\n", with: " ")
        print("\(post.id)\t\(post.channelId)\t\(post.userId)\t\(message)")
    }

    private static func printFileInfo(_ fileInfo: MattermostFileInfo) {
        print("\(fileInfo.id)\t\(fileInfo.name)\t\(fileInfo.size ?? 0)")
    }

    private static func printEmoji(_ emoji: [MattermostCustomEmoji]) {
        for item in emoji.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            print("\(item.id)\t\(item.name)")
        }
    }

    private static func printLiveEvent(_ event: MattermostLiveEvent) {
        let channelID = event.broadcast?.channelId ?? "-"
        let postID = (try? event.decodedPost()?.id) ?? "-"
        print("\(event.event)\t\(channelID)\t\(postID)")
    }

    private static func waitForEvents(
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

    private static func waitForPostEvent(
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

    private static func waitForTypingEvent(
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

    private static func waitForLiveSyncBackfill(
        recorder: LiveSyncRecorder,
        timeoutSeconds: Int
    ) async throws -> MattermostLiveBackfillResult {
        try await waitForLiveSyncBackfillCount(
            recorder: recorder,
            count: 1,
            timeoutSeconds: timeoutSeconds
        )[0]
    }

    private static func waitForLiveSyncBackfillCount(
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

    private static func waitForLiveSyncPost(
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

    private static func waitForSearchResult(
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

    private static func optionalTypingEvent(
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


    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "txt", "md", "log":
            "text/plain"
        case "json":
            "application/json"
        case "png":
            "image/png"
        case "jpg", "jpeg":
            "image/jpeg"
        case "gif":
            "image/gif"
        case "pdf":
            "application/pdf"
        default:
            "application/octet-stream"
        }
    }

    private static func resolvedStoreURL() throws -> URL {
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

    private static func testSuffix() -> String {
        let timestamp = Int(Date.now.timeIntervalSince1970)
        let random = UUID().uuidString
            .lowercased()
            .prefix(8)
        return "\(timestamp)-\(random)"
    }

    private static func requireFirst<Value>(_ values: [Value], _ message: String) throws -> Value {
        guard let value = values.first else {
            throw CLIError.usage(message)
        }
        return value
    }

    private static func cleanupPosts<PostIDs: Sequence>(
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

    private static func cleanupE2EResources(
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

    private static func printChannels(_ channels: [MattermostChannel]) {
        for channel in channels.sorted(by: channelSort) {
            let displayName = channel.displayName.isEmpty ? channel.name : channel.displayName
            print("\(channel.id)\t\(channel.type)\t\(displayName)")
        }
    }

    private static func printChannel(_ channel: MattermostChannel) {
        print("channel: \(channel.id)")
        if let teamID = channel.teamId, !teamID.isEmpty {
            print("team: \(teamID)")
        }
        print("type: \(channel.type)")
        print("name: \(channel.name)")
        print("display-name: \(channel.displayName)")
    }

    private static func printChannelStats(_ stats: MattermostChannelStats) {
        if let channelID = stats.channelId, !channelID.isEmpty {
            print("channel: \(channelID)")
        }
        if let memberCount = stats.memberCount {
            print("members: \(memberCount)")
        }
        if let guestCount = stats.guestCount {
            print("guests: \(guestCount)")
        }
        if let pinnedPostCount = stats.pinnedPostCount {
            print("pinned-posts: \(pinnedPostCount)")
        }
        if let totalMessageCount = stats.totalMessageCount {
            print("total-messages: \(totalMessageCount)")
        }
    }

    private static func printTimezones(_ timezones: [String]) {
        for timezone in timezones.sorted() {
            print(timezone)
        }
    }

    private static func printChannelMemberCounts(_ counts: [String: Int64]) {
        for channelID in counts.keys.sorted() {
            print("\(channelID)\t\(counts[channelID] ?? 0)")
        }
    }

    private static func printThreads(_ threadList: MattermostThreadList) {
        print("total: \(threadList.total)")
        print("unread-threads: \(threadList.totalUnreadThreads)")
        print("unread-mentions: \(threadList.totalUnreadMentions)")
        for thread in threadList.threads {
            print("\(thread.id)\treplies:\(thread.replyCount)\tunread:\(thread.unreadReplies)\tmentions:\(thread.unreadMentions)\turgent:\(thread.isUrgent)")
        }
    }

    private static func channelSort(_ lhs: MattermostChannel, _ rhs: MattermostChannel) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    private static func sidebarCategorySort(
        _ lhs: MattermostSidebarCategory,
        _ rhs: MattermostSidebarCategory
    ) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    private static func isActiveTestChannel(_ channel: MattermostChannel) -> Bool {
        !channel.isDeleted && (
            isTestResourceName(channel.name)
                || isTestResourceName(channel.displayName)
                || isTestResourceName(channel.purpose ?? "")
        )
    }

    private static func isTestSidebarCategory(_ category: MattermostSidebarCategory) -> Bool {
        category.type == "custom" && isTestResourceName(category.displayName)
    }

    private static func isTestChannel(_ channel: MattermostChannel) -> Bool {
        isTestResourceName(channel.name) || isTestResourceName(channel.displayName)
    }

    private static func isSafeTestChannelName(_ value: String) -> Bool {
        value.hasPrefix("mmswift-test")
            && value.unicodeScalars.allSatisfy { scalar in
                (97...122).contains(scalar.value)
                    || (48...57).contains(scalar.value)
                    || scalar.value == 45
            }
    }

    private static func isTestResourceName(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("mmswift-test")
            || normalized.hasPrefix("mattermostswift test")
            || normalized.hasPrefix("mattermostswift move test")
            || normalized.hasPrefix("mattermostswift e2e")
            || normalized.hasPrefix("mattermostswift cleanup")
    }

    private static func printHelp() {
        print(
            """
            MattermostSwiftCLI

            Usage:
              swift run MattermostSwiftCLI me
              swift run MattermostSwiftCLI get-user [user-id]
              swift run MattermostSwiftCLI profile-image [user-id]
              swift run MattermostSwiftCLI default-profile-image [user-id]
              swift run MattermostSwiftCLI get-users user-id [user-id...]
              swift run MattermostSwiftCLI get-users-by-username username [username...]
              swift run MattermostSwiftCLI list-channel-users [channel-id]
              swift run MattermostSwiftCLI search-users terms
              swift run MattermostSwiftCLI autocomplete-users name
              swift run MattermostSwiftCLI known-users [--profiles]
              swift run MattermostSwiftCLI status [user-id]
              swift run MattermostSwiftCLI server-info
              swift run MattermostSwiftCLI list-teams
              swift run MattermostSwiftCLI team-info [team-id]
              swift run MattermostSwiftCLI list-team-members [team-id]
              swift run MattermostSwiftCLI list-channels
              swift run MattermostSwiftCLI list-public-channels [team-id]
              swift run MattermostSwiftCLI channel-info [channel-id]
              swift run MattermostSwiftCLI channel-by-name [--team team-id] channel-name
              swift run MattermostSwiftCLI channel-by-team-name team-name channel-name
              swift run MattermostSwiftCLI channel-stats [channel-id]
              swift run MattermostSwiftCLI channel-timezones [channel-id]
              swift run MattermostSwiftCLI channel-member-counts [channel-id...]
              swift run MattermostSwiftCLI search-channels terms
              swift run MattermostSwiftCLI search-group-channels terms
              swift run MattermostSwiftCLI direct-channel-test [user-id]
              swift run MattermostSwiftCLI create-group-channel user-id user-id [user-id...]
              swift run MattermostSwiftCLI channel-member [channel-id]
              swift run MattermostSwiftCLI list-channel-members [channel-id]
              swift run MattermostSwiftCLI channel-members-by-id [--channel channel-id] user-id [user-id...]
              swift run MattermostSwiftCLI add-channel-member [--channel channel-id] user-id
              swift run MattermostSwiftCLI remove-channel-member [--channel channel-id] user-id
              swift run MattermostSwiftCLI channel-unread [channel-id]
              swift run MattermostSwiftCLI notify-props-test
              swift run MattermostSwiftCLI list-unread-posts [channel-id]
              swift run MattermostSwiftCLI view-channel [channel-id]
              swift run MattermostSwiftCLI send-typing [channel-id]
              swift run MattermostSwiftCLI list-categories
              swift run MattermostSwiftCLI list-threads [team-id]
              swift run MattermostSwiftCLI list-preferences [category]
              swift run MattermostSwiftCLI preferences-test
              swift run MattermostSwiftCLI preference-roundtrip-test
              swift run MattermostSwiftCLI sidebar-category-test
              swift run MattermostSwiftCLI sidebar-move-test
              swift run MattermostSwiftCLI create-test-channel
              swift run MattermostSwiftCLI rename-test-channel channel-id [new-name]
              swift run MattermostSwiftCLI archive-channel channel-id
              swift run MattermostSwiftCLI list-posts [channel-id]
              swift run MattermostSwiftCLI pinned-posts [channel-id]
              swift run MattermostSwiftCLI list-post-updates since-ms [channel-id]
              swift run MattermostSwiftCLI send-message [--channel channel-id] message
              swift run MattermostSwiftCLI edit-message post-id message
              swift run MattermostSwiftCLI delete-message post-id
              swift run MattermostSwiftCLI thread-test
              swift run MattermostSwiftCLI timeline-test
              swift run MattermostSwiftCLI since-test
              swift run MattermostSwiftCLI unread-posts-test
              swift run MattermostSwiftCLI threads-test
              swift run MattermostSwiftCLI props-test
              swift run MattermostSwiftCLI reaction-test
              swift run MattermostSwiftCLI search terms
              swift run MattermostSwiftCLI search-test
              swift run MattermostSwiftCLI upload-file [--channel channel-id] path
              swift run MattermostSwiftCLI download-file file-id [path]
              swift run MattermostSwiftCLI file-test
              swift run MattermostSwiftCLI list-emoji
              swift run MattermostSwiftCLI search-emoji term
              swift run MattermostSwiftCLI stream-events [limit]
              swift run MattermostSwiftCLI websocket-test
              swift run MattermostSwiftCLI live-sync-test
              swift run MattermostSwiftCLI reconnect-backfill-test
              swift run MattermostSwiftCLI deletion-backfill-test
              swift run MattermostSwiftCLI live-sync-reconnect-test
              swift run MattermostSwiftCLI all-channel-backfill-test
              swift run MattermostSwiftCLI all-channel-reconnect-test
              swift run MattermostSwiftCLI failure-cleanup-test
              swift run MattermostSwiftCLI residue-audit
              swift run MattermostSwiftCLI typing-test
              swift run MattermostSwiftCLI channel-test
              swift run MattermostSwiftCLI e2e-test
              swift run MattermostSwiftCLI sync [channel-id]
              swift run MattermostSwiftCLI cache-check [channel-id]
              swift run MattermostSwiftCLI login-test
              swift run MattermostSwiftCLI check

            Environment:
              MATTERMOST_URL       Required. Server base URL.
              MATTERMOST_TOKEN     Required. Personal access token.
              MATTERMOST_CHANNEL_ID Optional. Channel id for post commands.
              MATTERMOST_TEAM_NAME Optional. Team name for team-scoped channel listing.
              MATTERMOST_STORE_PATH Optional. SQLite path for CLI cache probes.
              MATTERMOST_USERNAME  Optional. Username/email for login-test.
              MATTERMOST_PASSWORD  Optional. Password for login-test.
            """
        )
    }
}

private struct E2ECleanupResult {
    let deletedPosts: Int
    let deletedCategory: Bool
    let deletedChannel: Bool
    let restoredOrder: Bool
}

private enum Command: Equatable {
    case me
    case getUser(userID: String)
    case profileImage(userID: String?)
    case defaultProfileImage(userID: String?)
    case getUsers(userIDs: [String])
    case getUsersByUsername(usernames: [String])
    case listChannelUsers(channelID: String?)
    case searchUsers(terms: String)
    case autocompleteUsers(name: String)
    case knownUsers(includeProfiles: Bool)
    case status(userID: String?)
    case serverInfo
    case listTeams
    case teamInfo(teamID: String?)
    case listTeamMembers(teamID: String?)
    case listChannels
    case listPublicChannels(teamID: String?)
    case channelInfo(channelID: String?)
    case channelByName(teamID: String?, name: String)
    case channelByTeamName(teamName: String, channelName: String)
    case channelStats(channelID: String?)
    case channelTimezones(channelID: String?)
    case channelMemberCounts(channelIDs: [String])
    case searchChannels(terms: String)
    case searchGroupChannels(terms: String)
    case directChannelTest(userID: String?)
    case createGroupChannel(userIDs: [String])
    case channelMember(channelID: String?)
    case listChannelMembers(channelID: String?)
    case channelMembersByID(channelID: String?, userIDs: [String])
    case addChannelMember(channelID: String?, userID: String)
    case removeChannelMember(channelID: String?, userID: String)
    case channelUnread(channelID: String?)
    case notifyPropsTest
    case listUnreadPosts(channelID: String?)
    case viewChannel(channelID: String?)
    case sendTyping(channelID: String?)
    case listCategories
    case listThreads(teamID: String?)
    case listPreferences(category: String?)
    case preferencesTest
    case preferenceRoundTripTest
    case sidebarCategoryTest
    case sidebarMoveTest
    case createTestChannel
    case renameTestChannel(channelID: String?, name: String?)
    case archiveChannel(channelID: String?)
    case listPosts(channelID: String?)
    case pinnedPosts(channelID: String?)
    case listPostUpdates(channelID: String?, since: Int64)
    case sendMessage(channelID: String?, message: String)
    case editMessage(postID: String, message: String)
    case deleteMessage(postID: String)
    case threadTest
    case timelineTest
    case sinceTest
    case unreadPostsTest
    case threadsTest
    case propsTest
    case reactionTest
    case search(terms: String)
    case searchTest
    case uploadFile(channelID: String?, path: String)
    case downloadFile(fileID: String, path: String?)
    case fileTest
    case listEmoji
    case searchEmoji(term: String)
    case streamEvents(limit: Int)
    case webSocketTest
    case liveSyncTest
    case reconnectBackfillTest
    case deletionBackfillTest
    case liveSyncReconnectTest
    case allChannelBackfillTest
    case allChannelReconnectTest
    case failureCleanupTest
    case residueAudit
    case typingTest
    case channelTest
    case e2eTest
    case sync(channelID: String?)
    case cacheCheck(channelID: String?)
    case loginTest
    case check
    case help

    init(arguments: [String]) {
        switch arguments.first {
        case "me":
            self = .me
        case "get-user":
            self = .getUser(userID: arguments.dropFirst().first ?? "me")
        case "profile-image":
            self = .profileImage(userID: arguments.dropFirst().first)
        case "default-profile-image":
            self = .defaultProfileImage(userID: arguments.dropFirst().first)
        case "get-users":
            let userIDs = Array(arguments.dropFirst())
            self = userIDs.isEmpty ? .help : .getUsers(userIDs: userIDs)
        case "get-users-by-username":
            let usernames = Array(arguments.dropFirst())
            self = usernames.isEmpty ? .help : .getUsersByUsername(usernames: usernames)
        case "list-channel-users":
            self = .listChannelUsers(channelID: arguments.dropFirst().first)
        case "search-users":
            let terms = arguments.dropFirst().joined(separator: " ")
            self = terms.isEmpty ? .help : .searchUsers(terms: terms)
        case "autocomplete-users":
            let name = arguments.dropFirst().joined(separator: " ")
            self = name.isEmpty ? .help : .autocompleteUsers(name: name)
        case "known-users":
            self = .knownUsers(includeProfiles: arguments.dropFirst().contains("--profiles"))
        case "status":
            self = .status(userID: arguments.dropFirst().first)
        case "server-info":
            self = .serverInfo
        case "list-teams":
            self = .listTeams
        case "team-info":
            self = .teamInfo(teamID: arguments.dropFirst().first)
        case "list-team-members":
            self = .listTeamMembers(teamID: arguments.dropFirst().first)
        case "list-channels":
            self = .listChannels
        case "list-public-channels":
            self = .listPublicChannels(teamID: arguments.dropFirst().first)
        case "channel-info":
            self = .channelInfo(channelID: arguments.dropFirst().first)
        case "channel-by-name":
            self = Command.parseChannelByName(Array(arguments.dropFirst()))
        case "channel-by-team-name":
            let tail = Array(arguments.dropFirst())
            if tail.count == 2 {
                self = .channelByTeamName(teamName: tail[0], channelName: tail[1])
            } else {
                self = .help
            }
        case "channel-stats":
            self = .channelStats(channelID: arguments.dropFirst().first)
        case "channel-timezones":
            self = .channelTimezones(channelID: arguments.dropFirst().first)
        case "channel-member-counts":
            self = .channelMemberCounts(channelIDs: Array(arguments.dropFirst()))
        case "search-channels":
            let terms = arguments.dropFirst().joined(separator: " ")
            self = terms.isEmpty ? .help : .searchChannels(terms: terms)
        case "search-group-channels":
            let terms = arguments.dropFirst().joined(separator: " ")
            self = terms.isEmpty ? .help : .searchGroupChannels(terms: terms)
        case "direct-channel-test":
            self = .directChannelTest(userID: arguments.dropFirst().first)
        case "create-group-channel":
            let userIDs = Array(arguments.dropFirst())
            self = userIDs.count >= 2 ? .createGroupChannel(userIDs: userIDs) : .help
        case "channel-member":
            self = .channelMember(channelID: arguments.dropFirst().first)
        case "list-channel-members":
            self = .listChannelMembers(channelID: arguments.dropFirst().first)
        case "channel-members-by-id":
            self = Command.parseChannelMembersByID(Array(arguments.dropFirst()))
        case "add-channel-member":
            self = Command.parseChannelMemberMutation(Array(arguments.dropFirst()), mutation: .add)
        case "remove-channel-member":
            self = Command.parseChannelMemberMutation(Array(arguments.dropFirst()), mutation: .remove)
        case "channel-unread":
            self = .channelUnread(channelID: arguments.dropFirst().first)
        case "notify-props-test":
            self = .notifyPropsTest
        case "list-unread-posts":
            self = .listUnreadPosts(channelID: arguments.dropFirst().first)
        case "view-channel":
            self = .viewChannel(channelID: arguments.dropFirst().first)
        case "send-typing":
            self = .sendTyping(channelID: arguments.dropFirst().first)
        case "list-categories":
            self = .listCategories
        case "list-threads":
            self = .listThreads(teamID: arguments.dropFirst().first)
        case "list-preferences":
            self = .listPreferences(category: arguments.dropFirst().first)
        case "preferences-test":
            self = .preferencesTest
        case "preference-roundtrip-test":
            self = .preferenceRoundTripTest
        case "sidebar-category-test":
            self = .sidebarCategoryTest
        case "sidebar-move-test":
            self = .sidebarMoveTest
        case "create-test-channel":
            self = .createTestChannel
        case "rename-test-channel":
            let tail = Array(arguments.dropFirst())
            self = .renameTestChannel(channelID: tail.first, name: tail.dropFirst().first)
        case "archive-channel":
            self = .archiveChannel(channelID: arguments.dropFirst().first)
        case "list-posts":
            self = .listPosts(channelID: arguments.dropFirst().first)
        case "pinned-posts":
            self = .pinnedPosts(channelID: arguments.dropFirst().first)
        case "list-post-updates":
            self = Command.parseListPostUpdates(Array(arguments.dropFirst()))
        case "send-message":
            self = Command.parseSendMessage(Array(arguments.dropFirst()))
        case "edit-message":
            self = Command.parseEditMessage(Array(arguments.dropFirst()))
        case "delete-message":
            if let postID = arguments.dropFirst().first {
                self = .deleteMessage(postID: postID)
            } else {
                self = .help
            }
        case "thread-test":
            self = .threadTest
        case "timeline-test":
            self = .timelineTest
        case "since-test":
            self = .sinceTest
        case "unread-posts-test":
            self = .unreadPostsTest
        case "threads-test":
            self = .threadsTest
        case "props-test":
            self = .propsTest
        case "reaction-test":
            self = .reactionTest
        case "search":
            let terms = arguments.dropFirst().joined(separator: " ")
            self = terms.isEmpty ? .help : .search(terms: terms)
        case "search-test":
            self = .searchTest
        case "upload-file":
            self = Command.parseUploadFile(Array(arguments.dropFirst()))
        case "download-file":
            let tail = Array(arguments.dropFirst())
            if let fileID = tail.first {
                self = .downloadFile(fileID: fileID, path: tail.dropFirst().first)
            } else {
                self = .help
            }
        case "file-test":
            self = .fileTest
        case "list-emoji":
            self = .listEmoji
        case "search-emoji":
            let term = arguments.dropFirst().joined(separator: " ")
            self = term.isEmpty ? .help : .searchEmoji(term: term)
        case "stream-events":
            let limit = arguments.dropFirst().first.flatMap(Int.init) ?? 1
            self = .streamEvents(limit: max(1, limit))
        case "websocket-test":
            self = .webSocketTest
        case "live-sync-test":
            self = .liveSyncTest
        case "reconnect-backfill-test":
            self = .reconnectBackfillTest
        case "deletion-backfill-test":
            self = .deletionBackfillTest
        case "live-sync-reconnect-test":
            self = .liveSyncReconnectTest
        case "all-channel-backfill-test":
            self = .allChannelBackfillTest
        case "all-channel-reconnect-test":
            self = .allChannelReconnectTest
        case "failure-cleanup-test":
            self = .failureCleanupTest
        case "residue-audit":
            self = .residueAudit
        case "typing-test":
            self = .typingTest
        case "channel-test":
            self = .channelTest
        case "e2e-test":
            self = .e2eTest
        case "sync":
            self = .sync(channelID: arguments.dropFirst().first)
        case "cache-check":
            self = .cacheCheck(channelID: arguments.dropFirst().first)
        case "login-test":
            self = .loginTest
        case "check":
            self = .check
        default:
            self = .help
        }
    }

    private static func parseSendMessage(_ arguments: [String]) -> Command {
        if arguments.first == "--channel" {
            let remaining = Array(arguments.dropFirst(2))
            guard let channelID = arguments.dropFirst().first, !remaining.isEmpty else {
                return .help
            }
            return .sendMessage(channelID: channelID, message: remaining.joined(separator: " "))
        }

        guard !arguments.isEmpty else {
            return .help
        }

        return .sendMessage(channelID: nil, message: arguments.joined(separator: " "))
    }

    private static func parseChannelByName(_ arguments: [String]) -> Command {
        if arguments.first == "--team" {
            let tail = Array(arguments.dropFirst(2))
            guard let teamID = arguments.dropFirst().first, let name = tail.first, tail.count == 1 else {
                return .help
            }
            return .channelByName(teamID: teamID, name: name)
        }

        guard let name = arguments.first, arguments.count == 1 else {
            return .help
        }
        return .channelByName(teamID: nil, name: name)
    }

    private static func parseEditMessage(_ arguments: [String]) -> Command {
        guard let postID = arguments.first else {
            return .help
        }

        let messageParts = arguments.dropFirst()
        guard !messageParts.isEmpty else {
            return .help
        }

        return .editMessage(postID: postID, message: messageParts.joined(separator: " "))
    }

    private static func parseListPostUpdates(_ arguments: [String]) -> Command {
        if let since = arguments.first.flatMap(Int64.init) {
            return .listPostUpdates(channelID: arguments.dropFirst().first, since: since)
        }

        if arguments.count >= 2, let since = Int64(arguments[1]) {
            return .listPostUpdates(channelID: arguments[0], since: since)
        }

        return .help
    }

    private static func parseUploadFile(_ arguments: [String]) -> Command {
        if arguments.first == "--channel" {
            let tail = Array(arguments.dropFirst(2))
            guard let channelID = arguments.dropFirst().first, let path = tail.first else {
                return .help
            }
            return .uploadFile(channelID: channelID, path: path)
        }

        guard let path = arguments.first else {
            return .help
        }
        return .uploadFile(channelID: nil, path: path)
    }

    private static func parseChannelMembersByID(_ arguments: [String]) -> Command {
        let parsed = parseOptionalChannelArguments(arguments)
        guard !parsed.values.isEmpty else {
            return .help
        }
        return .channelMembersByID(channelID: parsed.channelID, userIDs: parsed.values)
    }

    private static func parseChannelMemberMutation(
        _ arguments: [String],
        mutation: ChannelMemberMutation
    ) -> Command {
        let parsed = parseOptionalChannelArguments(arguments)
        guard let userID = parsed.values.first, parsed.values.count == 1 else {
            return .help
        }

        switch mutation {
        case .add:
            return .addChannelMember(channelID: parsed.channelID, userID: userID)
        case .remove:
            return .removeChannelMember(channelID: parsed.channelID, userID: userID)
        }
    }

    private static func parseOptionalChannelArguments(_ arguments: [String]) -> (channelID: String?, values: [String]) {
        if arguments.first == "--channel" {
            return (arguments.dropFirst().first, Array(arguments.dropFirst(2)))
        }
        return (nil, arguments)
    }

    private enum ChannelMemberMutation {
        case add
        case remove
    }
}

private enum CLIError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            message
        }
    }
}

private actor LiveEventRecorder {
    private var events: [MattermostLiveEvent] = []
    private var storedError: (any Error)?

    var count: Int {
        events.count
    }

    var error: (any Error)? {
        storedError
    }

    func append(_ event: MattermostLiveEvent) {
        events.append(event)
    }

    func setError(_ error: any Error) {
        storedError = error
    }

    func postEvent(named eventName: String, postID: String) -> MattermostLiveEvent? {
        events.first { event in
            event.event == eventName && event.stringData("post")?.contains(postID) == true
        }
    }

    func typingEvent(channelID: String, userID: String) -> MattermostTypingEvent? {
        for event in events {
            guard case .typing(let typing) = try? event.typedEvent(),
                  typing.channelID == channelID,
                  typing.userID == userID else {
                continue
            }
            return typing
        }
        return nil
    }
}

private actor LiveSyncRecorder {
    private var events: [MattermostLiveSyncEvent] = []
    private var storedError: (any Error)?

    var error: (any Error)? {
        storedError
    }

    var backfill: MattermostLiveBackfillResult? {
        backfills.first
    }

    var backfills: [MattermostLiveBackfillResult] {
        events.compactMap { event in
            if case .backfilled(let result) = event {
                return result
            }
            return nil
        }
    }

    var reconnectingAttempts: [Int] {
        events.compactMap { event in
            if case .reconnecting(let attempt, _) = event {
                return attempt
            }
            return nil
        }
    }

    func append(_ event: MattermostLiveSyncEvent) {
        events.append(event)
    }

    func setError(_ error: any Error) {
        storedError = error
    }

    func appliedPost(id: String) -> MattermostPost? {
        for event in events {
            guard case .eventApplied(_, let typedEvent) = event,
                  case .posted(let post) = typedEvent,
                  post.id == id else {
                continue
            }
            return post
        }
        return nil
    }
}

private actor LiveSyncLifecycleDriver {
    private var continuation: AsyncThrowingStream<MattermostLiveEventStreamLifecycleEvent, Error>.Continuation?
    private var pending: [MattermostLiveEventStreamLifecycleEvent] = []

    func attach(_ continuation: AsyncThrowingStream<MattermostLiveEventStreamLifecycleEvent, Error>.Continuation) {
        self.continuation = continuation
        for event in pending {
            continuation.yield(event)
        }
        pending.removeAll()
    }

    func yield(_ event: MattermostLiveEventStreamLifecycleEvent) {
        if let continuation {
            continuation.yield(event)
        } else {
            pending.append(event)
        }
    }

    func finish() {
        continuation?.finish()
        continuation = nil
        pending.removeAll()
    }
}
