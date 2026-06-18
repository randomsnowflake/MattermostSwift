import Foundation
@_spi(Testing) import MattermostSwift

extension MattermostSwiftCLI {
    static func main() async {
        do {
            try await run()
        } catch let error as CLIError {
            // Usage/argument errors exit with a distinct code so CI and scripts can tell
            // "you called it wrong" (2) apart from a runtime/server failure (1).
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(2)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func run() async throws {
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
            // `get-user` with no argument defaults to "me"; route that through the
            // dedicated current-user endpoint rather than `GET /users/me`.
            if userID == "me" {
                printUser(try await client.currentUser())
            } else {
                printUser(try await client.user(id: userID))
            }
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

}
