import Foundation
@_spi(Testing) import MattermostSwift

// Shared waits, cleanup and test-resource guards used by every scenario family.
extension MattermostSwiftCLI {
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


    static func resolvedStoreURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL? = nil
    ) throws -> URL {
        let url: URL

        if let rawPath = environment["MATTERMOST_STORE_PATH"], !rawPath.isEmpty {
            url = URL(fileURLWithPath: rawPath).standardizedFileURL
        } else {
            let currentDirectory = currentDirectoryURL ?? URL(
                fileURLWithPath: fileManager.currentDirectoryPath,
                isDirectory: true
            )
            url = currentDirectory
                .appendingPathComponent(".mattermostswift", isDirectory: true)
                .appendingPathComponent("MattermostSwift.sqlite")
                .standardizedFileURL
        }

        let directory = url.deletingLastPathComponent()
        let permissions = NSNumber(value: UInt16(0o700))
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: permissions]
        )
        try fileManager.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: directory.path
        )
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
        category.type == .custom && isTestResourceName(category.displayName)
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
