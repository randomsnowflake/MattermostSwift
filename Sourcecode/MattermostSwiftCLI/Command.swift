import Foundation
@_spi(Testing) import MattermostSwift

extension MattermostSwiftCLI {
    static func printHelp() {
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

            Commands ending in -test are live-server diagnostics that use the configured Mattermost environment.

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

enum Command: Equatable {
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
