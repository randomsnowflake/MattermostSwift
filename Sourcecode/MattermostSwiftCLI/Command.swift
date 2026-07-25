import ArgumentParser
import Foundation

enum Command: Equatable, Sendable {
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
}

struct ParsedCLIInvocation: Equatable, Sendable {
    let command: Command
    let json: Bool
}

struct RootCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "MattermostSwiftCLI",
        abstract: "A command-line harness for the MattermostSwift SDK.",
        discussion: """
            Authentication and defaults are read from MATTERMOST_URL, MATTERMOST_TOKEN, \
            MATTERMOST_CHANNEL_ID, MATTERMOST_TEAM_NAME, and MATTERMOST_STORE_PATH.
            """,
        version: "0.1.0",
        subcommands: [
            Me.self,
            GetUser.self,
            ProfileImage.self,
            DefaultProfileImage.self,
            GetUsers.self,
            GetUsersByUsername.self,
            ListChannelUsers.self,
            SearchUsers.self,
            AutocompleteUsers.self,
            KnownUsers.self,
            UserStatus.self,
            ServerInfo.self,
            ListTeams.self,
            TeamInfo.self,
            ListTeamMembers.self,
            ListChannels.self,
            ListPublicChannels.self,
            ChannelInfo.self,
            ChannelByName.self,
            ChannelByTeamName.self,
            ChannelStats.self,
            ChannelTimezones.self,
            ChannelMemberCounts.self,
            SearchChannels.self,
            SearchGroupChannels.self,
            CreateGroupChannel.self,
            ChannelMember.self,
            ListChannelMembers.self,
            ChannelMembersByID.self,
            AddChannelMember.self,
            RemoveChannelMember.self,
            ChannelUnread.self,
            ListUnreadPosts.self,
            ViewChannel.self,
            SendTyping.self,
            ListCategories.self,
            ListThreads.self,
            ListPreferences.self,
            ListPosts.self,
            PinnedPosts.self,
            ListPostUpdates.self,
            SendMessage.self,
            EditMessage.self,
            DeleteMessage.self,
            SearchPosts.self,
            UploadFile.self,
            DownloadFile.self,
            ListEmoji.self,
            SearchEmoji.self,
            StreamEvents.self,
            Sync.self,
            CacheCheck.self,
            Check.self,
            Diagnostics.self,
        ]
    )

    @Flag(help: "Emit stable, lossless JSON to standard output.")
    var json = false
}

extension MattermostSwiftCLI {
    static func parseInvocation(_ arguments: [String]) throws -> ParsedCLIInvocation {
        let parsed = try RootCommand.parseAsRoot(arguments)
        if let command = parsed as? any RootCLICommand {
            return ParsedCLIInvocation(command: command.command, json: command.parent.json)
        }
        if let command = parsed as? any DiagnosticCLICommand {
            return ParsedCLIInvocation(
                command: command.command,
                json: command.parent.parent.json
            )
        }
        throw ValidationError("Expected a MattermostSwiftCLI subcommand.")
    }
}

protocol RootCLICommand: AsyncParsableCommand {
    var parent: RootCommand { get }
    var command: Command { get }
}

extension RootCLICommand {
    mutating func run() async throws {
        try await CLIOutputMode.$json.withValue(parent.json) {
            try await MattermostSwiftCLI.run(command: command)
        }
    }
}

private func joined(_ values: [String]) -> String {
    values.joined(separator: " ")
}

struct Me: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Show the current authenticated user.")
    @ParentCommand var parent: RootCommand
    var command: Command { .me }
}

struct GetUser: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Show a user by id, defaulting to the current user.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Mattermost user id.") var userID = "me"
    var command: Command { .getUser(userID: userID) }
}

struct ProfileImage: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Inspect a user's profile image download.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Mattermost user id. Defaults to the current user.") var userID: String?
    var command: Command { .profileImage(userID: userID) }
}

struct DefaultProfileImage: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Inspect a user's generated default profile image.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Mattermost user id. Defaults to the current user.") var userID: String?
    var command: Command { .defaultProfileImage(userID: userID) }
}

struct GetUsers: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Load users by id.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "One or more Mattermost user ids.") var userIDs: [String]
    var command: Command { .getUsers(userIDs: userIDs) }
}

struct GetUsersByUsername: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Load users by username.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "One or more Mattermost usernames.") var usernames: [String]
    var command: Command { .getUsersByUsername(usernames: usernames) }
}

struct ListChannelUsers: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List users in a channel.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .listChannelUsers(channelID: channelID) }
}

struct SearchUsers: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Search users.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Search terms.") var terms: [String]
    var command: Command { .searchUsers(terms: joined(terms)) }
}

struct AutocompleteUsers: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Autocomplete users.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Name fragment.") var name: [String]
    var command: Command { .autocompleteUsers(name: joined(name)) }
}

struct KnownUsers: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List known user ids.")
    @ParentCommand var parent: RootCommand
    @Flag(help: "Load and output profiles instead of ids only.") var profiles = false
    var command: Command { .knownUsers(includeProfiles: profiles) }
}

struct UserStatus: RootCLICommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show a user's presence status.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "User id. Defaults to the current user.") var userID: String?
    var command: Command { .status(userID: userID) }
}

struct ServerInfo: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Probe server health and client configuration.")
    @ParentCommand var parent: RootCommand
    var command: Command { .serverInfo }
}

struct ListTeams: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List joined teams.")
    @ParentCommand var parent: RootCommand
    var command: Command { .listTeams }
}

struct TeamInfo: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Show team metadata.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Team id. Defaults to the configured or first joined team.") var teamID: String?
    var command: Command { .teamInfo(teamID: teamID) }
}

struct ListTeamMembers: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List members of a team.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Team id. Defaults to the configured or first joined team.") var teamID: String?
    var command: Command { .listTeamMembers(teamID: teamID) }
}

struct ListChannels: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List joined channels.")
    @ParentCommand var parent: RootCommand
    var command: Command { .listChannels }
}

struct ListPublicChannels: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List public channels in a team.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Team id. Defaults to the configured or first joined team.") var teamID: String?
    var command: Command { .listPublicChannels(teamID: teamID) }
}

struct ChannelInfo: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Show channel metadata.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .channelInfo(channelID: channelID) }
}

struct ChannelByName: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Resolve a channel by team id and channel name.")
    @ParentCommand var parent: RootCommand
    @Option(help: "Team id. Defaults to the configured or first joined team.") var team: String?
    @Argument(help: "Channel name.") var name: String
    var command: Command { .channelByName(teamID: team, name: name) }
}

struct ChannelByTeamName: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Resolve a channel by team name and channel name.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Team name.") var teamName: String
    @Argument(help: "Channel name.") var channelName: String
    var command: Command { .channelByTeamName(teamName: teamName, channelName: channelName) }
}

struct ChannelStats: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Show aggregate channel statistics.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .channelStats(channelID: channelID) }
}

struct ChannelTimezones: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List member timezones for a channel.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .channelTimezones(channelID: channelID) }
}

struct ChannelMemberCounts: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Show member counts for one or more channels.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel ids. Defaults to MATTERMOST_CHANNEL_ID.") var channelIDs: [String] = []
    var command: Command { .channelMemberCounts(channelIDs: channelIDs) }
}

struct SearchChannels: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Search channels.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Search terms.") var terms: [String]
    var command: Command { .searchChannels(terms: joined(terms)) }
}

struct SearchGroupChannels: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Search existing group-message channels.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Search terms.") var terms: [String]
    var command: Command { .searchGroupChannels(terms: joined(terms)) }
}

struct CreateGroupChannel: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Open a group-message channel.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "At least two user ids.") var userIDs: [String]

    mutating func validate() throws {
        guard userIDs.count >= 2 else {
            throw ValidationError("Provide at least two user ids.")
        }
    }

    var command: Command { .createGroupChannel(userIDs: userIDs) }
}

struct ChannelMember: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Show current-user membership in a channel.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .channelMember(channelID: channelID) }
}

struct ListChannelMembers: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List channel memberships.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .listChannelMembers(channelID: channelID) }
}

struct ChannelMembersByID: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Load channel memberships by user id.")
    @ParentCommand var parent: RootCommand
    @Option(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channel: String?
    @Argument(help: "One or more user ids.") var userIDs: [String]
    var command: Command { .channelMembersByID(channelID: channel, userIDs: userIDs) }
}

struct AddChannelMember: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Add a user to a channel.")
    @ParentCommand var parent: RootCommand
    @Option(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channel: String?
    @Argument(help: "User id.") var userID: String
    var command: Command { .addChannelMember(channelID: channel, userID: userID) }
}

struct RemoveChannelMember: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Remove a user from a channel.")
    @ParentCommand var parent: RootCommand
    @Option(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channel: String?
    @Argument(help: "User id.") var userID: String
    var command: Command { .removeChannelMember(channelID: channel, userID: userID) }
}

struct ChannelUnread: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Show unread counts for a channel.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .channelUnread(channelID: channelID) }
}

struct ListUnreadPosts: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List posts around the oldest unread post.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .listUnreadPosts(channelID: channelID) }
}

struct ViewChannel: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Mark a channel viewed.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .viewChannel(channelID: channelID) }
}

struct SendTyping: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Publish a typing event.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .sendTyping(channelID: channelID) }
}

struct ListCategories: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List sidebar categories.")
    @ParentCommand var parent: RootCommand
    var command: Command { .listCategories }
}

struct ListThreads: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List the current user's thread inbox.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Team id. Defaults to the configured or first joined team.") var teamID: String?
    var command: Command { .listThreads(teamID: teamID) }
}

struct ListPreferences: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List user preferences without exposing values in human output.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Optional preference category.") var category: String?
    var command: Command { .listPreferences(category: category) }
}

struct ListPosts: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List recent channel posts.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .listPosts(channelID: channelID) }
}

struct PinnedPosts: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List pinned channel posts.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .pinnedPosts(channelID: channelID) }
}

struct ListPostUpdates: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List posts created or updated since a millisecond timestamp.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Mattermost millisecond timestamp.") var since: Int64
    @Argument(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channelID: String?
    var command: Command { .listPostUpdates(channelID: channelID, since: since) }
}

struct SendMessage: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Send a message to a channel.")
    @ParentCommand var parent: RootCommand
    @Option(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channel: String?
    @Argument(help: "Message text.") var message: [String]
    var command: Command { .sendMessage(channelID: channel, message: joined(message)) }
}

struct EditMessage: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Edit an existing post.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Post id.") var postID: String
    @Argument(help: "Replacement message text.") var message: [String]
    var command: Command { .editMessage(postID: postID, message: joined(message)) }
}

struct DeleteMessage: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Delete a post.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Post id.") var postID: String
    var command: Command { .deleteMessage(postID: postID) }
}

struct SearchPosts: RootCLICommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: "Search posts in the configured team.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Search terms.") var terms: [String]
    var command: Command { .search(terms: joined(terms)) }
}

struct UploadFile: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Upload a file.")
    @ParentCommand var parent: RootCommand
    @Option(help: "Channel id. Defaults to MATTERMOST_CHANNEL_ID.") var channel: String?
    @Argument(help: "Local file path.") var path: String
    var command: Command { .uploadFile(channelID: channel, path: path) }
}

struct DownloadFile: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Download a file to a path or, when piped, standard output.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Mattermost file id.") var fileID: String
    @Argument(help: "Optional destination path.") var path: String?
    var command: Command { .downloadFile(fileID: fileID, path: path) }
}

struct ListEmoji: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "List custom emoji.")
    @ParentCommand var parent: RootCommand
    var command: Command { .listEmoji }
}

struct SearchEmoji: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Search custom emoji.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Search term.") var term: [String]
    var command: Command { .searchEmoji(term: joined(term)) }
}

struct StreamEvents: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Stream a bounded number of WebSocket events.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Number of events to receive.") var limit = 1

    mutating func validate() throws {
        guard limit > 0 else {
            throw ValidationError("The event limit must be greater than zero.")
        }
    }

    var command: Command { .streamEvents(limit: limit) }
}

struct Sync: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Hydrate the local SwiftData cache.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Optional channel id whose posts should also be synced.") var channelID: String?
    var command: Command { .sync(channelID: channelID) }
}

struct CacheCheck: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Inspect the local cache without network access.")
    @ParentCommand var parent: RootCommand
    @Argument(help: "Optional channel id whose cached posts should be counted.") var channelID: String?
    var command: Command { .cacheCheck(channelID: channelID) }
}

struct Check: RootCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify authentication and joined-channel loading.")
    @ParentCommand var parent: RootCommand
    var command: Command { .check }
}

struct Diagnostics: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diag",
        abstract: "Run live-server and mutating verification diagnostics.",
        discussion: "These commands may require extra credentials and some mutate the configured workspace.",
        subcommands: [
            DirectChannelTest.self,
            NotifyPropsTest.self,
            PreferencesTest.self,
            PreferenceRoundTripTest.self,
            SidebarCategoryTest.self,
            SidebarMoveTest.self,
            CreateTestChannel.self,
            RenameTestChannel.self,
            ArchiveChannel.self,
            ThreadTest.self,
            TimelineTest.self,
            SinceTest.self,
            UnreadPostsTest.self,
            ThreadsTest.self,
            PropsTest.self,
            ReactionTest.self,
            SearchTest.self,
            FileTest.self,
            WebSocketTest.self,
            LiveSyncTest.self,
            ReconnectBackfillTest.self,
            DeletionBackfillTest.self,
            LiveSyncReconnectTest.self,
            AllChannelBackfillTest.self,
            AllChannelReconnectTest.self,
            FailureCleanupTest.self,
            ResidueAudit.self,
            TypingTest.self,
            ChannelTest.self,
            E2ETest.self,
            LoginTest.self,
        ]
    )

    @ParentCommand var parent: RootCommand
}

protocol DiagnosticCLICommand: AsyncParsableCommand {
    var parent: Diagnostics { get }
    var command: Command { get }
}

extension DiagnosticCLICommand {
    mutating func run() async throws {
        try await CLIOutputMode.$json.withValue(parent.parent.json) {
            try await MattermostSwiftCLI.run(command: command)
        }
    }
}

struct DirectChannelTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify direct-channel opening.")
    @ParentCommand var parent: Diagnostics
    @Argument(help: "Other user id. Defaults to another known user.") var userID: String?
    var command: Command { .directChannelTest(userID: userID) }
}

struct NotifyPropsTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify typed channel notification properties.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .notifyPropsTest }
}

struct PreferencesTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify preference decoding.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .preferencesTest }
}

struct PreferenceRoundTripTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(
        commandName: "preference-roundtrip-test",
        abstract: "Verify temporary preference save/load/delete."
    )
    @ParentCommand var parent: Diagnostics
    var command: Command { .preferenceRoundTripTest }
}

struct SidebarCategoryTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify sidebar category lifecycle.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .sidebarCategoryTest }
}

struct SidebarMoveTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify moving a channel in sidebar categories.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .sidebarMoveTest }
}

struct CreateTestChannel: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Create a guarded MattermostSwift test channel.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .createTestChannel }
}

struct RenameTestChannel: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Rename a guarded MattermostSwift test channel.")
    @ParentCommand var parent: Diagnostics
    @Argument(help: "Test channel id.") var channelID: String
    @Argument(help: "Optional new mmswift-test-* channel name.") var name: String?
    var command: Command { .renameTestChannel(channelID: channelID, name: name) }
}

struct ArchiveChannel: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Archive a guarded MattermostSwift test channel.")
    @ParentCommand var parent: Diagnostics
    @Argument(help: "Test channel id.") var channelID: String
    var command: Command { .archiveChannel(channelID: channelID) }
}

struct ThreadTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify root/reply thread behavior.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .threadTest }
}

struct TimelineTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify channel/thread timeline behavior.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .timelineTest }
}

struct SinceTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify post-update fetching by timestamp.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .sinceTest }
}

struct UnreadPostsTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify unread-context post loading.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .unreadPostsTest }
}

struct ThreadsTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify thread inbox decoding and caching.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .threadsTest }
}

struct PropsTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify post props round-trip and caching.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .propsTest }
}

struct ReactionTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify reaction add/list/remove.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .reactionTest }
}

struct SearchTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify post search against a temporary post.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .searchTest }
}

struct FileTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify file upload/attach/download.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .fileTest }
}

struct WebSocketTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(
        commandName: "websocket-test",
        abstract: "Verify posted/edit/delete WebSocket events."
    )
    @ParentCommand var parent: Diagnostics
    var command: Command { .webSocketTest }
}

struct LiveSyncTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify live-sync event application.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .liveSyncTest }
}

struct ReconnectBackfillTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify cursor-based reconnect backfill.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .reconnectBackfillTest }
}

struct DeletionBackfillTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify deletion reconciliation during backfill.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .deletionBackfillTest }
}

struct LiveSyncReconnectTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify deterministic live-sync reconnect behavior.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .liveSyncReconnectTest }
}

struct AllChannelBackfillTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify an all-joined-channel backfill sweep.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .allChannelBackfillTest }
}

struct AllChannelReconnectTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify all-channel reconnect backfill.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .allChannelReconnectTest }
}

struct FailureCleanupTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify cleanup after a forced intermediate failure.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .failureCleanupTest }
}

struct ResidueAudit: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Audit for active MattermostSwift test residue.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .residueAudit }
}

struct TypingTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify typing publication and opportunistic receive.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .typingTest }
}

struct ChannelTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify channel create/rename/view/archive.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .channelTest }
}

struct E2ETest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(
        commandName: "e2e-test",
        abstract: "Run the isolated full end-to-end verification flow."
    )
    @ParentCommand var parent: Diagnostics
    var command: Command { .e2eTest }
}

struct LoginTest: DiagnosticCLICommand {
    static let configuration = CommandConfiguration(abstract: "Verify username/password login and logout.")
    @ParentCommand var parent: Diagnostics
    var command: Command { .loginTest }
}
