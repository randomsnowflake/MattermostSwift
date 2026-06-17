import Foundation
@_spi(Testing) import MattermostSwift

extension MattermostSwiftCLI {
    static func uploadFile(
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

    static func downloadFile(
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

    static func streamEvents(client: MattermostClient, limit: Int) async throws {
        var count = 0
        for try await event in client.liveEventStream().events() {
            printLiveEvent(event)
            count += 1
            if count >= limit {
                break
            }
        }
    }

    static func runCreateTestChannel(client: MattermostClient) async throws {
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

    static func runRenameTestChannel(
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

    static func runArchiveChannel(client: MattermostClient, channelID: String?) async throws {
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

    @MainActor
    static func runSync(client: MattermostClient, channelID: String?) async throws {
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
    static func runCacheCheck(channelID: String?) async throws {
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

}
