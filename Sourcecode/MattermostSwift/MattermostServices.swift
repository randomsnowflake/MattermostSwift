import Foundation

/// Server health and client capability operations.
public struct MattermostServerService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Loads combined server health and client capability metadata.
    public func info() async throws -> MattermostServerInfo {
        try await client.serverInfo()
    }

    /// Loads server health status using Mattermost REST semantics.
    public func ping() async throws -> MattermostServerPing {
        try await client.serverPing()
    }

    /// Loads the subset of server configuration exposed to Mattermost clients.
    public func clientConfig() async throws -> MattermostClientConfig {
        try await client.clientConfig()
    }
}

/// User and presence operations.
public struct MattermostUserService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Loads the authenticated Mattermost user.
    public func currentUser() async throws -> MattermostUser {
        try await client.currentUser()
    }

    /// Loads a user by id. Pass `"me"` to resolve the authenticated user through the server.
    public func user(id: String) async throws -> MattermostUser {
        try await client.user(id: id)
    }

    /// Downloads a user's current profile image bytes. Pass `"me"` for the authenticated user.
    public func profileImage(userID: String = "me") async throws -> Data {
        try await client.userProfileImage(userID: userID)
    }

    /// Downloads the generated default profile image for a user id.
    public func defaultProfileImage(userID: String) async throws -> Data {
        try await client.defaultUserProfileImage(userID: userID)
    }

    /// Loads users by id in one request.
    public func users(ids: [String]) async throws -> [MattermostUser] {
        try await client.users(ids: ids)
    }

    /// Loads users by username in one request.
    public func users(usernames: [String]) async throws -> [MattermostUser] {
        try await client.users(usernames: usernames)
    }

    /// Lists users who are members of a channel.
    public func users(channelID: String, page: Int = 0, perPage: Int = 60) async throws -> [MattermostUser] {
        try await client.users(channelID: channelID, page: page, perPage: perPage)
    }

    /// Searches users by username, full name, nickname, or email where the server permits it.
    public func search(
        term: String,
        teamID: String? = nil,
        notInTeamID: String? = nil,
        inChannelID: String? = nil,
        notInChannelID: String? = nil,
        allowInactive: Bool = false,
        withoutTeam: Bool = false,
        limit: Int = 20
    ) async throws -> [MattermostUser] {
        try await client.searchUsers(
            term: term,
            teamID: teamID,
            notInTeamID: notInTeamID,
            inChannelID: inChannelID,
            notInChannelID: notInChannelID,
            allowInactive: allowInactive,
            withoutTeam: withoutTeam,
            limit: limit
        )
    }

    /// Autocompletes users for composer/member pickers.
    public func autocomplete(
        name: String,
        teamID: String? = nil,
        channelID: String? = nil,
        limit: Int = 20
    ) async throws -> MattermostUserAutocomplete {
        try await client.autocompleteUsers(
            name: name,
            teamID: teamID,
            channelID: channelID,
            limit: limit
        )
    }

    /// Loads IDs of users known to the authenticated user through direct/shared channel relationships.
    public func knownUserIDs() async throws -> [String] {
        try await client.knownUserIDs()
    }

    /// Loads one user's presence state, such as online, away, or offline.
    public func status(userID: String) async throws -> MattermostUserStatus {
        try await client.status(userID: userID)
    }

    /// Loads presence states for multiple users in one request.
    public func statuses(userIDs: [String]) async throws -> [MattermostUserStatus] {
        try await client.statuses(userIDs: userIDs)
    }
}

/// Team metadata and membership operations.
public struct MattermostTeamService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Lists teams joined by the authenticated user.
    public func joinedTeams(userID: String = "me") async throws -> [MattermostTeam] {
        try await client.teams(userID: userID)
    }

    /// Lists team membership records for users on a team.
    public func members(
        teamID: String,
        page: Int = 0,
        perPage: Int = 60,
        sort: String? = nil,
        excludeDeletedUsers: Bool = false
    ) async throws -> [MattermostTeamMember] {
        try await client.teamMembers(
            teamID: teamID,
            page: page,
            perPage: perPage,
            sort: sort,
            excludeDeletedUsers: excludeDeletedUsers
        )
    }

    /// Loads team metadata by id.
    public func team(id: String) async throws -> MattermostTeam {
        try await client.team(id: id)
    }

    /// Resolves a team by its URL-safe Mattermost team name.
    public func team(named name: String) async throws -> MattermostTeam {
        try await client.team(named: name)
    }
}

/// Team-scoped channel operations.
public struct MattermostChannelService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Resolves a team by its URL-safe Mattermost team name.
    public func team(named name: String) async throws -> MattermostTeam {
        try await client.team(named: name)
    }

    /// Lists channels in one team that the authenticated user has joined.
    public func joinedChannels(teamID: String) async throws -> [MattermostChannel] {
        try await client.joinedChannels(teamID: teamID)
    }

    /// Lists public channels on a team that the authenticated user may discover.
    public func publicChannels(teamID: String, page: Int = 0, perPage: Int = 60) async throws -> [MattermostChannel] {
        try await client.publicChannels(teamID: teamID, page: page, perPage: perPage)
    }

    /// Lists joined channels across all teams visible to the authenticated user.
    public func joinedChannelsAcrossTeams() async throws -> [MattermostChannel] {
        try await client.joinedChannelsAcrossTeams()
    }

    /// Loads channel metadata by id.
    public func channel(id: String) async throws -> MattermostChannel {
        try await client.channel(id: id)
    }

    /// Resolves channel metadata by team id and URL-safe channel name.
    public func channel(teamID: String, name: String, includeDeleted: Bool = false) async throws -> MattermostChannel {
        try await client.channel(teamID: teamID, name: name, includeDeleted: includeDeleted)
    }

    /// Resolves channel metadata by team name and URL-safe channel name.
    public func channel(
        teamName: String,
        channelName: String,
        includeDeleted: Bool = false
    ) async throws -> MattermostChannel {
        try await client.channel(teamName: teamName, channelName: channelName, includeDeleted: includeDeleted)
    }

    /// Loads aggregate statistics for one channel.
    public func stats(channelID: String) async throws -> MattermostChannelStats {
        try await client.channelStats(channelID: channelID)
    }

    /// Lists timezones represented by channel members.
    public func timezones(channelID: String) async throws -> [String] {
        try await client.channelTimezones(channelID: channelID)
    }

    /// Loads member counts for multiple channels keyed by channel id.
    public func memberCounts(channelIDs: [String]) async throws -> [String: Int64] {
        try await client.channelMemberCounts(channelIDs: channelIDs)
    }

    /// Searches channels across visible teams when the server permits broad channel search.
    public func searchChannels(
        term: String,
        teamIDs: [String] = [],
        excludeDefaultChannels: Bool = false,
        includeDeleted: Bool = false,
        page: Int = 0,
        perPage: Int = 60,
        includeSearchByID: Bool = false
    ) async throws -> MattermostChannelSearchResults {
        try await client.searchChannels(
            term: term,
            teamIDs: teamIDs,
            excludeDefaultChannels: excludeDefaultChannels,
            includeDeleted: includeDeleted,
            page: page,
            perPage: perPage,
            includeSearchByID: includeSearchByID
        )
    }

    /// Searches public channels within a specific team.
    public func searchTeamChannels(teamID: String, term: String) async throws -> [MattermostChannel] {
        try await client.searchTeamChannels(teamID: teamID, term: term)
    }

    /// Opens or creates a direct message channel between two users.
    public func createDirectChannel(userID: String, otherUserID: String) async throws -> MattermostChannel {
        try await client.createDirectChannel(userID: userID, otherUserID: otherUserID)
    }

    /// Opens or creates a group message channel.
    public func createGroupChannel(userIDs: [String]) async throws -> MattermostChannel {
        try await client.createGroupChannel(userIDs: userIDs)
    }

    /// Searches group message channels by member username.
    public func searchGroupChannels(term: String) async throws -> [MattermostChannel] {
        try await client.searchGroupChannels(term: term)
    }

    /// Creates a public (`"O"`) or private (`"P"`) channel on a team.
    public func createChannel(
        teamID: String,
        name: String,
        displayName: String,
        purpose: String? = nil,
        header: String? = nil,
        type: String = "O"
    ) async throws -> MattermostChannel {
        try await client.createChannel(
            teamID: teamID,
            name: name,
            displayName: displayName,
            purpose: purpose,
            header: header,
            type: type
        )
    }

    /// Updates mutable channel metadata such as name, display name, purpose, or header.
    public func patchChannel(
        id: String,
        name: String? = nil,
        displayName: String? = nil,
        purpose: String? = nil,
        header: String? = nil
    ) async throws -> MattermostChannel {
        try await client.patchChannel(
            id: id,
            name: name,
            displayName: displayName,
            purpose: purpose,
            header: header
        )
    }

    /// Archives a channel where the server and current user's permissions allow it.
    @discardableResult
    public func deleteChannel(id: String) async throws -> MattermostStatusOK {
        try await client.deleteChannel(id: id)
    }

    /// Loads a user's membership/read/notification state for a channel.
    public func channelMember(channelID: String, userID: String = "me") async throws -> MattermostChannelMember {
        try await client.channelMember(channelID: channelID, userID: userID)
    }

    /// Lists memberships for users in a channel.
    public func channelMembers(
        channelID: String,
        page: Int = 0,
        perPage: Int = 60
    ) async throws -> [MattermostChannelMember] {
        try await client.channelMembers(channelID: channelID, page: page, perPage: perPage)
    }

    /// Loads specific channel memberships by user id.
    public func channelMembers(channelID: String, userIDs: [String]) async throws -> [MattermostChannelMember] {
        try await client.channelMembers(channelID: channelID, userIDs: userIDs)
    }

    /// Lists a user's channel memberships within a team.
    public func channelMembersForUser(userID: String = "me", teamID: String) async throws -> [MattermostChannelMember] {
        try await client.channelMembersForUser(userID: userID, teamID: teamID)
    }

    /// Adds one user to a public or private channel where permissions allow it.
    public func addChannelMember(
        channelID: String,
        userID: String,
        postRootID: String? = nil
    ) async throws -> MattermostChannelMember {
        try await client.addChannelMember(channelID: channelID, userID: userID, postRootID: postRootID)
    }

    /// Adds one or more users to a public or private channel where permissions allow it.
    public func addChannelMembers(
        channelID: String,
        userIDs: [String],
        postRootID: String? = nil
    ) async throws -> MattermostChannelMember {
        try await client.addChannelMembers(channelID: channelID, userIDs: userIDs, postRootID: postRootID)
    }

    /// Removes a user from a public or private channel where permissions allow it.
    @discardableResult
    public func removeChannelMember(channelID: String, userID: String) async throws -> MattermostStatusOK {
        try await client.removeChannelMember(channelID: channelID, userID: userID)
    }
}

/// Unread, notification, and viewed-channel operations.
public struct MattermostNotificationService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Loads unread message and mention counts for a user in a channel.
    public func channelUnread(userID: String = "me", channelID: String) async throws -> MattermostChannelUnread {
        try await client.channelUnread(userID: userID, channelID: channelID)
    }

    /// Loads typed per-channel notification properties for a user.
    public func channelNotifyProps(
        channelID: String,
        userID: String = "me"
    ) async throws -> MattermostChannelNotifyProps {
        try await client.channelMember(channelID: channelID, userID: userID).channelNotifyProps
    }

    /// Updates the user's per-channel notification properties.
    @discardableResult
    public func updateChannelNotifyProps(
        channelID: String,
        userID: String = "me",
        notifyProps: [String: String]
    ) async throws -> MattermostStatusOK {
        try await client.updateChannelNotifyProps(
            channelID: channelID,
            userID: userID,
            notifyProps: notifyProps
        )
    }

    /// Updates the user's per-channel notification properties with typed accessors.
    @discardableResult
    public func updateChannelNotifyProps(
        channelID: String,
        userID: String = "me",
        notifyProps: MattermostChannelNotifyProps
    ) async throws -> MattermostStatusOK {
        try await client.updateChannelNotifyProps(
            channelID: channelID,
            userID: userID,
            notifyProps: notifyProps
        )
    }

    /// Marks a channel viewed and clears related unread state.
    @discardableResult
    public func viewChannel(
        channelID: String,
        userID: String = "me",
        previousChannelID: String? = nil
    ) async throws -> MattermostChannelViewResponse {
        try await client.viewChannel(
            channelID: channelID,
            userID: userID,
            previousChannelID: previousChannelID
        )
    }
}

/// Typing indicator operations.
public struct MattermostTypingService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Publishes a typing indicator for a channel or thread.
    @discardableResult
    public func sendTyping(
        channelID: String,
        parentID: String? = nil,
        userID: String = "me"
    ) async throws -> MattermostStatusOK {
        try await client.sendTyping(channelID: channelID, parentID: parentID, userID: userID)
    }
}

/// User preference operations for client-side settings.
public struct MattermostPreferenceService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Lists all preferences for a user.
    public func list(userID: String = "me") async throws -> [MattermostPreference] {
        try await client.preferences(userID: userID)
    }

    /// Lists preferences within one Mattermost preference category.
    public func list(userID: String = "me", category: String) async throws -> [MattermostPreference] {
        try await client.preferences(userID: userID, category: category)
    }

    /// Loads a single preference by category and name.
    public func preference(
        userID: String = "me",
        category: String,
        name: String
    ) async throws -> MattermostPreference {
        try await client.preference(userID: userID, category: category, name: name)
    }

    /// Saves one or more preferences for a user.
    @discardableResult
    public func save(
        _ preferences: [MattermostPreference],
        userID: String = "me"
    ) async throws -> MattermostStatusOK {
        try await client.savePreferences(preferences, userID: userID)
    }

    /// Deletes one or more preferences for a user.
    @discardableResult
    public func delete(
        _ preferences: [MattermostPreference],
        userID: String = "me"
    ) async throws -> MattermostStatusOK {
        try await client.deletePreferences(preferences, userID: userID)
    }
}

/// Sidebar category operations for a team.
public struct MattermostSidebarCategoryService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Lists the user's sidebar categories for a team in server order.
    public func list(teamID: String) async throws -> [MattermostSidebarCategory] {
        try await client.sidebarCategories(teamID: teamID)
    }

    /// Creates a custom sidebar category, optionally with an initial ordered channel list.
    public func create(
        teamID: String,
        displayName: String,
        channelIDs: [String] = [],
        userID: String = "me"
    ) async throws -> MattermostSidebarCategory {
        try await client.createSidebarCategory(
            teamID: teamID,
            displayName: displayName,
            channelIDs: channelIDs,
            userID: userID
        )
    }

    /// Updates a sidebar category's display name, type, and ordered channel list.
    public func update(
        teamID: String,
        categoryID: String,
        displayName: String,
        channelIDs: [String],
        type: String = "custom",
        userID: String = "me"
    ) async throws -> MattermostSidebarCategory {
        try await client.updateSidebarCategory(
            teamID: teamID,
            categoryID: categoryID,
            displayName: displayName,
            channelIDs: channelIDs,
            type: type,
            userID: userID
        )
    }

    /// Deletes a custom sidebar category.
    @discardableResult
    public func delete(teamID: String, categoryID: String, userID: String = "me") async throws -> MattermostStatusOK {
        try await client.deleteSidebarCategory(teamID: teamID, categoryID: categoryID, userID: userID)
    }

    /// Moves a channel into a sidebar category, optionally at a specific position.
    public func moveChannel(
        teamID: String,
        channelID: String,
        categoryID: String,
        position: Int? = nil,
        userID: String = "me"
    ) async throws -> MattermostSidebarCategoryMoveResult {
        try await client.moveChannelToSidebarCategory(
            teamID: teamID,
            channelID: channelID,
            categoryID: categoryID,
            position: position,
            userID: userID
        )
    }

    /// Reorders one channel within a sidebar category.
    public func reorderChannel(
        teamID: String,
        categoryID: String,
        channelID: String,
        position: Int,
        userID: String = "me"
    ) async throws -> MattermostSidebarCategory {
        try await client.reorderChannelInSidebarCategory(
            teamID: teamID,
            categoryID: categoryID,
            channelID: channelID,
            position: position,
            userID: userID
        )
    }

    /// Loads the ordered category id list used by the Mattermost sidebar.
    public func order(teamID: String, userID: String = "me") async throws -> [String] {
        try await client.sidebarCategoryOrder(teamID: teamID, userID: userID)
    }

    /// Replaces the sidebar category order for a team.
    @discardableResult
    public func updateOrder(teamID: String, order: [String], userID: String = "me") async throws -> [String] {
        try await client.updateSidebarCategoryOrder(teamID: teamID, order: order, userID: userID)
    }
}

/// Channel timeline and post mutation operations.
public struct MattermostPostService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Loads a channel post page with Mattermost pagination and cursor parameters.
    public func posts(
        channelID: String,
        page: Int = 0,
        perPage: Int = 60,
        since: Int64? = nil,
        before: String? = nil,
        after: String? = nil
    ) async throws -> MattermostPostList {
        try await client.posts(
            channelID: channelID,
            page: page,
            perPage: perPage,
            since: since,
            before: before,
            after: after
        )
    }

    /// Loads posts pinned in a channel.
    public func pinnedPosts(channelID: String) async throws -> MattermostPostList {
        try await client.pinnedPosts(channelID: channelID)
    }

    /// Loads one post by id.
    public func post(id: String) async throws -> MattermostPost {
        try await client.post(id: id)
    }

    /// Loads posts updated since a Mattermost millisecond timestamp.
    public func postsSince(channelID: String, since: Int64) async throws -> MattermostPostList {
        try await client.postsSince(channelID: channelID, since: since)
    }

    /// Loads context around the user's oldest unread post in a channel.
    public func postsAroundLastUnread(
        userID: String = "me",
        channelID: String,
        limitBefore: Int = 30,
        limitAfter: Int = 30,
        skipFetchThreads: Bool = false,
        collapsedThreads: Bool = false,
        collapsedThreadsExtended: Bool = false
    ) async throws -> MattermostPostList {
        try await client.postsAroundLastUnread(
            userID: userID,
            channelID: channelID,
            limitBefore: limitBefore,
            limitAfter: limitAfter,
            skipFetchThreads: skipFetchThreads,
            collapsedThreads: collapsedThreads,
            collapsedThreadsExtended: collapsedThreadsExtended
        )
    }

    /// Creates a root post or reply when `rootID` is supplied.
    public func sendPost(
        channelID: String,
        message: String,
        rootID: String? = nil,
        fileIDs: [String] = [],
        props: [String: MattermostJSONValue] = [:]
    ) async throws -> MattermostPost {
        try await client.sendPost(
            channelID: channelID,
            message: message,
            rootID: rootID,
            fileIDs: fileIDs,
            props: props
        )
    }

    /// Edits a post's message and, when supplied, replaces its props.
    public func editPost(
        id: String,
        message: String,
        props: [String: MattermostJSONValue]? = nil
    ) async throws -> MattermostPost {
        try await client.editPost(id: id, message: message, props: props)
    }

    /// Soft-deletes a post where the server and current user's permissions allow it.
    @discardableResult
    public func deletePost(id: String) async throws -> MattermostStatusOK {
        try await client.deletePost(id: id)
    }

    /// Syncs recent channel posts into a `MattermostStore` and advances that channel's cursor.
    @MainActor
    public func syncChannelPosts(
        channelID: String,
        to store: MattermostStore,
        perPage: Int = 60,
        maxPages: Int = 1
    ) async throws -> MattermostChannelPostSyncResult {
        try await client.syncChannelPosts(channelID: channelID, to: store, perPage: perPage, maxPages: maxPages)
    }
}

/// Thread loading and reply operations.
public struct MattermostThreadService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Lists collapsed-reply-thread inbox state for a user on a team.
    public func list(
        userID: String = "me",
        teamID: String,
        request: MattermostThreadListRequest = MattermostThreadListRequest()
    ) async throws -> MattermostThreadList {
        try await client.userThreads(userID: userID, teamID: teamID, request: request)
    }

    /// Loads one thread's inbox/read state for a user on a team.
    public func state(
        userID: String = "me",
        teamID: String,
        threadID: String,
        extended: Bool = false
    ) async throws -> MattermostThreadResponse {
        try await client.userThread(userID: userID, teamID: teamID, threadID: threadID, extended: extended)
    }

    /// Loads a root post and its replies using Mattermost thread pagination semantics.
    public func thread(
        postID: String,
        perPage: Int = 0,
        fromPost: String? = nil,
        fromCreateAt: Int64? = nil,
        direction: MattermostThreadDirection? = nil,
        skipFetchThreads: Bool? = nil,
        collapsedThreads: Bool? = nil,
        collapsedThreadsExtended: Bool? = nil
    ) async throws -> MattermostPostList {
        try await client.thread(
            postID: postID,
            perPage: perPage,
            fromPost: fromPost,
            fromCreateAt: fromCreateAt,
            direction: direction,
            skipFetchThreads: skipFetchThreads,
            collapsedThreads: collapsedThreads,
            collapsedThreadsExtended: collapsedThreadsExtended
        )
    }

    /// Sends a reply into an existing thread.
    public func reply(
        channelID: String,
        rootID: String,
        message: String,
        fileIDs: [String] = [],
        props: [String: MattermostJSONValue] = [:]
    ) async throws -> MattermostPost {
        try await client.sendPost(
            channelID: channelID,
            message: message,
            rootID: rootID,
            fileIDs: fileIDs,
            props: props
        )
    }
}

/// Unified channel and thread timeline operations.
public struct MattermostTimelineService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Loads a channel or thread timeline through a common request shape.
    public func load(
        _ target: MattermostTimelineTarget,
        request: MattermostTimelineRequest = MattermostTimelineRequest()
    ) async throws -> MattermostTimelinePage {
        try await client.timeline(target, request: request)
    }

    /// Syncs a channel or thread timeline into a `MattermostStore`.
    @MainActor
    public func sync(
        _ target: MattermostTimelineTarget,
        to store: MattermostStore,
        request: MattermostTimelineRequest = MattermostTimelineRequest(),
        maxPages: Int = 1
    ) async throws -> MattermostTimelineSyncResult {
        try await client.syncTimeline(target, to: store, request: request, maxPages: maxPages)
    }

    /// Reads cached timeline posts from a `MattermostStore`.
    @MainActor
    public func cachedPosts(
        _ target: MattermostTimelineTarget,
        in store: MattermostStore,
        limit: Int? = nil,
        includeDeleted: Bool = true
    ) throws -> [MattermostCachedPost] {
        try store.cachedTimeline(target, limit: limit, includeDeleted: includeDeleted)
    }
}

/// Emoji reaction operations.
public struct MattermostReactionService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Adds an emoji reaction to a post.
    public func add(postID: String, userID: String, emojiName: String) async throws -> MattermostReaction {
        try await client.addReaction(postID: postID, userID: userID, emojiName: emojiName)
    }

    /// Lists reactions attached to a post.
    public func list(postID: String) async throws -> [MattermostReaction] {
        try await client.reactions(postID: postID)
    }

    /// Removes an emoji reaction from a post.
    @discardableResult
    public func remove(postID: String, userID: String, emojiName: String) async throws -> MattermostStatusOK {
        try await client.removeReaction(postID: postID, userID: userID, emojiName: emojiName)
    }
}

/// Message and channel search operations.
public struct MattermostSearchService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Searches posts within a team using Mattermost's search query language.
    public func posts(
        teamID: String,
        terms: String,
        isOrSearch: Bool = false,
        page: Int = 0,
        perPage: Int = 60
    ) async throws -> MattermostPostSearchResults {
        try await client.searchPosts(
            teamID: teamID,
            terms: terms,
            isOrSearch: isOrSearch,
            page: page,
            perPage: perPage
        )
    }

    /// Searches channels visible to the user.
    public func channels(term: String, teamIDs: [String] = [], page: Int = 0, perPage: Int = 60) async throws -> MattermostChannelSearchResults {
        try await client.searchChannels(term: term, teamIDs: teamIDs, page: page, perPage: perPage)
    }
}

/// File upload, metadata, and download operations.
public struct MattermostFileService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Uploads file bytes to Mattermost for later attachment to a post.
    public func upload(
        channelID: String,
        filename: String,
        data: Data,
        contentType: String = "application/octet-stream",
        clientID: String? = nil
    ) async throws -> MattermostFileUploadResponse {
        try await client.uploadFile(
            channelID: channelID,
            filename: filename,
            data: data,
            contentType: contentType,
            clientID: clientID
        )
    }

    /// Loads file metadata by file id.
    public func info(id: String) async throws -> MattermostFileInfo {
        try await client.fileInfo(id: id)
    }

    /// Lists file metadata attached to a post.
    public func infos(postID: String) async throws -> [MattermostFileInfo] {
        try await client.fileInfos(postID: postID)
    }

    /// Downloads raw file bytes by file id.
    public func download(id: String) async throws -> Data {
        try await client.downloadFile(id: id)
    }
}

/// Custom emoji operations.
public struct MattermostEmojiService: Sendable {
    private let client: MattermostClient

    init(client: MattermostClient) {
        self.client = client
    }

    /// Lists custom emoji metadata.
    public func list(page: Int = 0, perPage: Int = 60, sort: String = "name") async throws -> [MattermostCustomEmoji] {
        try await client.customEmoji(page: page, perPage: perPage, sort: sort)
    }

    /// Loads custom emoji metadata by id.
    public func emoji(id: String) async throws -> MattermostCustomEmoji {
        try await client.customEmoji(id: id)
    }

    /// Loads custom emoji metadata by name.
    public func emoji(named name: String) async throws -> MattermostCustomEmoji {
        try await client.customEmoji(named: name)
    }

    /// Searches custom emoji by term.
    public func search(term: String, prefixOnly: Bool = false) async throws -> [MattermostCustomEmoji] {
        try await client.searchCustomEmoji(term: term, prefixOnly: prefixOnly)
    }

    /// Returns custom emoji autocomplete suggestions for a partial name.
    public func autocomplete(name: String) async throws -> [MattermostCustomEmoji] {
        try await client.autocompleteCustomEmoji(name: name)
    }

    /// Downloads the custom emoji image bytes.
    public func image(id: String) async throws -> Data {
        try await client.customEmojiImage(id: id)
    }
}

public extension MattermostClient {
    /// Server health and client capability operations.
    func serverService() -> MattermostServerService {
        MattermostServerService(client: self)
    }

    /// User and presence operations.
    func userService() -> MattermostUserService {
        MattermostUserService(client: self)
    }

    /// Team metadata and membership operations.
    func teamService() -> MattermostTeamService {
        MattermostTeamService(client: self)
    }

    /// Team and channel operations.
    func channelService() -> MattermostChannelService {
        MattermostChannelService(client: self)
    }

    /// Unread, notification, and viewed-channel operations.
    func notificationService() -> MattermostNotificationService {
        MattermostNotificationService(client: self)
    }

    /// Typing indicator operations.
    func typingService() -> MattermostTypingService {
        MattermostTypingService(client: self)
    }

    /// User preference operations.
    func preferenceService() -> MattermostPreferenceService {
        MattermostPreferenceService(client: self)
    }

    /// Sidebar category operations.
    func sidebarCategoryService() -> MattermostSidebarCategoryService {
        MattermostSidebarCategoryService(client: self)
    }

    /// Channel timeline and post mutation operations.
    func postService() -> MattermostPostService {
        MattermostPostService(client: self)
    }

    /// Thread loading and reply operations.
    func threadService() -> MattermostThreadService {
        MattermostThreadService(client: self)
    }

    /// Unified channel and thread timeline operations.
    func timelineService() -> MattermostTimelineService {
        MattermostTimelineService(client: self)
    }

    /// Emoji reaction operations.
    func reactionService() -> MattermostReactionService {
        MattermostReactionService(client: self)
    }

    /// Message and channel search operations.
    func searchService() -> MattermostSearchService {
        MattermostSearchService(client: self)
    }

    /// File upload, metadata, and download operations.
    func fileService() -> MattermostFileService {
        MattermostFileService(client: self)
    }

    /// Custom emoji operations.
    func emojiService() -> MattermostEmojiService {
        MattermostEmojiService(client: self)
    }
}
