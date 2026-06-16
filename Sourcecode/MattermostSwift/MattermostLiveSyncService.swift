import Foundation

/// Options for continuous live cache maintenance.
public struct MattermostLiveSyncOptions: Equatable, Sendable {
    /// Sync options used for initial and reconnect backfill passes.
    public var syncOptions: MattermostSyncOptions

    /// Channel ids whose post timelines should be backfilled on connect/reconnect.
    public var channelIDs: [String]

    /// When `channelIDs` is empty, backfill joined channel timelines up to `maxBackfillChannels`.
    public var backfillJoinedChannelPosts: Bool

    /// When `channelIDs` is empty, backfill every joined channel timeline instead of applying `maxBackfillChannels`.
    public var backfillAllJoinedChannelPosts: Bool

    /// Upper bound for joined-channel timeline backfill in a single connect/reconnect pass.
    public var maxBackfillChannels: Int

    /// Refresh unread state when a live `channel_viewed` event includes a channel id.
    public var refreshUnreadOnChannelViewed: Bool

    /// Refresh unread state when live events such as `post_unread` invalidate channel unread counts.
    public var refreshUnreadOnPostUnread: Bool

    /// Refresh sidebar categories when preference events may affect sidebar state.
    public var refreshSidebarCategoriesOnPreferenceChange: Bool

    /// Refresh per-user thread state when live thread invalidation events include enough context.
    public var refreshThreadStateOnThreadEvent: Bool

    public init(
        syncOptions: MattermostSyncOptions = MattermostSyncOptions(postPageSize: 60, maxPostPages: 1),
        channelIDs: [String] = [],
        backfillJoinedChannelPosts: Bool = true,
        backfillAllJoinedChannelPosts: Bool = false,
        maxBackfillChannels: Int = 25,
        refreshUnreadOnChannelViewed: Bool = true,
        refreshUnreadOnPostUnread: Bool = true,
        refreshSidebarCategoriesOnPreferenceChange: Bool = true,
        refreshThreadStateOnThreadEvent: Bool = true
    ) {
        self.syncOptions = syncOptions
        self.channelIDs = channelIDs
        self.backfillJoinedChannelPosts = backfillJoinedChannelPosts
        self.backfillAllJoinedChannelPosts = backfillAllJoinedChannelPosts
        self.maxBackfillChannels = max(0, maxBackfillChannels)
        self.refreshUnreadOnChannelViewed = refreshUnreadOnChannelViewed
        self.refreshUnreadOnPostUnread = refreshUnreadOnPostUnread
        self.refreshSidebarCategoriesOnPreferenceChange = refreshSidebarCategoriesOnPreferenceChange
        self.refreshThreadStateOnThreadEvent = refreshThreadStateOnThreadEvent
    }
}

/// Summary of one live-sync backfill pass.
public struct MattermostLiveBackfillResult: Equatable, Sendable {
    public let sync: MattermostSyncResult
    public let postSyncs: [MattermostChannelPostSyncResult]

    public init(sync: MattermostSyncResult, postSyncs: [MattermostChannelPostSyncResult]) {
        self.sync = sync
        self.postSyncs = postSyncs
    }
}

/// Coarse connection phase derived from live-sync lifecycle events for host UI state.
public enum MattermostLiveSyncConnectionState: Equatable, Sendable {
    case connecting(attempt: Int)
    case connected(teamID: String?, backfilledChannelCount: Int)
    case reconnecting(attempt: Int, delay: Duration)
    case failed(attempt: Int, message: String)

    public var isRecovering: Bool {
        switch self {
        case .connecting, .reconnecting:
            true
        case .connected, .failed:
            false
        }
    }
}

/// Host-visible live-sync failure details.
public struct MattermostLiveSyncFailure: Equatable, Sendable {
    public let attempt: Int
    public let message: String

    public init(attempt: Int, message: String) {
        self.attempt = attempt
        self.message = message
    }
}

/// Events emitted by `MattermostLiveSyncService`.
public enum MattermostLiveSyncEvent: Sendable {
    case connecting(attempt: Int)
    case backfilled(MattermostLiveBackfillResult)
    case eventApplied(MattermostLiveEvent, MattermostTypedLiveEvent)
    case channelUnreadRefreshed(MattermostChannelUnread)
    case sidebarCategoriesRefreshed([MattermostSidebarCategory])
    case threadStateRefreshed(MattermostThreadResponse)
    case reconnecting(attempt: Int, delay: Duration)
    case backfillFailed(MattermostLiveSyncFailure)
}

public extension MattermostLiveSyncEvent {
    /// Lifecycle state for host apps that want one UI-friendly connection indicator.
    var connectionState: MattermostLiveSyncConnectionState? {
        switch self {
        case .connecting(let attempt):
            .connecting(attempt: attempt)
        case .backfilled(let result):
            .connected(
                teamID: result.sync.teamID,
                backfilledChannelCount: result.postSyncs.count
            )
        case .reconnecting(let attempt, let delay):
            .reconnecting(attempt: attempt, delay: delay)
        case .backfillFailed(let failure):
            .failed(attempt: failure.attempt, message: failure.message)
        case .eventApplied,
             .channelUnreadRefreshed,
             .sidebarCategoriesRefreshed,
             .threadStateRefreshed:
            nil
        }
    }
}

typealias MattermostLiveSyncLifecycleEvents = @Sendable () -> AsyncThrowingStream<MattermostLiveEventStreamLifecycleEvent, Error>
typealias MattermostLiveSyncBackfill = @MainActor @Sendable (
    _ store: MattermostStore,
    _ teamID: String?,
    _ teamName: String?,
    _ options: MattermostLiveSyncOptions
) async throws -> MattermostLiveBackfillResult
typealias MattermostLiveSyncUnreadRefresh = @MainActor @Sendable (
    _ userID: String,
    _ channelID: String
) async throws -> MattermostChannelUnread
typealias MattermostLiveSyncSidebarRefresh = @MainActor @Sendable (
    _ teamID: String
) async throws -> [MattermostSidebarCategory]
typealias MattermostLiveSyncThreadStateRefresh = @MainActor @Sendable (
    _ userID: String,
    _ teamID: String,
    _ threadID: String
) async throws -> MattermostThreadResponse

/// Keeps a `MattermostStore` updated from WebSocket events with bounded REST backfill.
public struct MattermostLiveSyncService: Sendable {
    private let client: MattermostClient

    public init(client: MattermostClient) {
        self.client = client
    }

    /// Starts live cache maintenance.
    ///
    /// The returned sequence performs a bounded REST sync before each socket connection attempt,
    /// then applies typed live events into `store` as they arrive. Cancelling iteration shuts down
    /// the underlying WebSocket task.
    @MainActor
    public func events(
        to store: MattermostStore,
        teamID: String? = nil,
        teamName: String? = nil,
        options: MattermostLiveSyncOptions = MattermostLiveSyncOptions(),
        reconnectPolicy: MattermostLiveEventReconnectPolicy = .default
    ) -> AsyncThrowingStream<MattermostLiveSyncEvent, Error> {
        events(
            to: store,
            teamID: teamID,
            teamName: teamName,
            options: options,
            lifecycleEvents: { client.liveEventStream().lifecycleEvents(policy: reconnectPolicy) },
            backfill: { store, teamID, teamName, options in
                try await backfill(
                    store: store,
                    teamID: teamID,
                    teamName: teamName,
                    options: options
                )
            },
            refreshUnread: { userID, channelID in
                try await client.channelUnread(userID: userID, channelID: channelID)
            },
            refreshSidebarCategories: { teamID in
                try await client.sidebarCategories(teamID: teamID)
            },
            refreshThreadState: { userID, teamID, threadID in
                try await client.userThread(
                    userID: userID,
                    teamID: teamID,
                    threadID: threadID,
                    extended: true
                )
            }
        )
    }

    /// Starts live cache maintenance with caller-supplied lifecycle events.
    ///
    /// This SPI is for package verification harnesses that need deterministic reconnect
    /// lifecycle control while still using the production REST backfill and refresh logic.
    @_spi(Testing)
    @MainActor
    public func events(
        to store: MattermostStore,
        teamID: String? = nil,
        teamName: String? = nil,
        options: MattermostLiveSyncOptions = MattermostLiveSyncOptions(),
        lifecycleEvents: @escaping @Sendable () -> AsyncThrowingStream<MattermostLiveEventStreamLifecycleEvent, Error>
    ) -> AsyncThrowingStream<MattermostLiveSyncEvent, Error> {
        events(
            to: store,
            teamID: teamID,
            teamName: teamName,
            options: options,
            lifecycleEvents: lifecycleEvents,
            backfill: { store, teamID, teamName, options in
                try await backfill(
                    store: store,
                    teamID: teamID,
                    teamName: teamName,
                    options: options
                )
            },
            refreshUnread: { userID, channelID in
                try await client.channelUnread(userID: userID, channelID: channelID)
            },
            refreshSidebarCategories: { teamID in
                try await client.sidebarCategories(teamID: teamID)
            },
            refreshThreadState: { userID, teamID, threadID in
                try await client.userThread(
                    userID: userID,
                    teamID: teamID,
                    threadID: threadID,
                    extended: true
                )
            }
        )
    }

    @MainActor
    func events(
        to store: MattermostStore,
        teamID: String? = nil,
        teamName: String? = nil,
        options: MattermostLiveSyncOptions = MattermostLiveSyncOptions(),
        lifecycleEvents: @escaping MattermostLiveSyncLifecycleEvents,
        backfill: @escaping MattermostLiveSyncBackfill,
        refreshUnread: MattermostLiveSyncUnreadRefresh? = nil,
        refreshSidebarCategories: MattermostLiveSyncSidebarRefresh? = nil,
        refreshThreadState: MattermostLiveSyncThreadStateRefresh? = nil
    ) -> AsyncThrowingStream<MattermostLiveSyncEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            let streamTask = Task { @MainActor in
                do {
                    var activeTeamID = teamID
                    var activeUserID: String?
                    for try await lifecycleEvent in lifecycleEvents() {
                        try Task.checkCancellation()

                        switch lifecycleEvent {
                        case .connecting(let attempt):
                            continuation.yield(.connecting(attempt: attempt))
                            // A backfill failure is reported but no longer terminates the stream:
                            // the lifecycle loop keeps running so the socket can connect and a later
                            // reconnect can retry the backfill. Only cancellation tears the stream down.
                            do {
                                let backfillResult = try await backfill(
                                    store,
                                    activeTeamID,
                                    teamName,
                                    options
                                )
                                activeTeamID = backfillResult.sync.teamID ?? activeTeamID
                                activeUserID = backfillResult.sync.user.id
                                continuation.yield(.backfilled(backfillResult))
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                continuation.yield(.backfillFailed(MattermostLiveSyncFailure(
                                    attempt: attempt,
                                    message: Self.failureMessage(for: error)
                                )))
                            }

                        case .event(let event):
                            let typedEvent = try store.apply(liveEvent: event)
                            try store.save()
                            continuation.yield(.eventApplied(event, typedEvent))

                            if let refreshUnread,
                               let unreadRefresh = typedEvent.unreadRefresh(
                                   options: options,
                                   fallbackUserID: activeUserID
                               ) {
                                let unread = try await refreshUnread(
                                    unreadRefresh.userID,
                                    unreadRefresh.channelID
                                )
                                try store.upsert(unread: unread, userID: unreadRefresh.userID)
                                try store.save()
                                continuation.yield(.channelUnreadRefreshed(unread))
                            }

                            if options.refreshSidebarCategoriesOnPreferenceChange,
                               let refreshSidebarCategories,
                               let activeTeamID,
                               typedEvent.invalidatesSidebarCategories {
                                let categories = try await refreshSidebarCategories(activeTeamID)
                                try store.upsert(sidebarCategories: categories)
                                try store.save()
                                continuation.yield(.sidebarCategoriesRefreshed(categories))
                            }

                            if options.refreshThreadStateOnThreadEvent,
                               let refreshThreadState,
                               let threadRefresh = typedEvent.threadStateRefresh(
                                   fallbackUserID: activeUserID,
                                   fallbackTeamID: activeTeamID
                               ) {
                                let thread = try await refreshThreadState(
                                    threadRefresh.userID,
                                    threadRefresh.teamID,
                                    threadRefresh.threadID
                                )
                                try store.upsert(
                                    thread: thread,
                                    userID: threadRefresh.userID,
                                    teamID: threadRefresh.teamID
                                )
                                try store.save()
                                continuation.yield(.threadStateRefreshed(thread))
                            }

                        case .reconnecting(let attempt, let delay):
                            continuation.yield(.reconnecting(attempt: attempt, delay: delay))
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
            }
        }
    }

    @MainActor
    private func backfill(
        store: MattermostStore,
        teamID: String?,
        teamName: String?,
        options: MattermostLiveSyncOptions
    ) async throws -> MattermostLiveBackfillResult {
        let sync = try await client.syncService().sync(
            to: store,
            teamID: teamID,
            teamName: teamName,
            channelID: nil,
            options: options.syncOptions
        )

        let channelIDs = Self.backfillChannelIDs(from: sync.channels, options: options)
        var postSyncs: [MattermostChannelPostSyncResult] = []
        for channelID in channelIDs {
            let postSync = try await client.syncChannelPosts(
                channelID: channelID,
                to: store,
                perPage: options.syncOptions.postPageSize,
                maxPages: options.syncOptions.maxPostPages
            )
            postSyncs.append(postSync)
        }
        try store.save()

        return MattermostLiveBackfillResult(sync: sync, postSyncs: postSyncs)
    }

    static func backfillChannelIDs(
        from joinedChannels: [MattermostChannel],
        options: MattermostLiveSyncOptions
    ) -> [String] {
        if !options.channelIDs.isEmpty {
            return Array(options.channelIDs.prefix(options.maxBackfillChannels))
        }

        guard options.backfillJoinedChannelPosts else {
            return []
        }

        if options.backfillAllJoinedChannelPosts {
            return joinedChannels.map(\.id)
        }

        return joinedChannels
            .prefix(options.maxBackfillChannels)
            .map(\.id)
    }

    private static func failureMessage(for error: any Error) -> String {
        let message = error.localizedDescription
        if !message.isEmpty {
            return message
        }
        return String(describing: error)
    }
}

/// Lifecycle-level WebSocket events used by live sync orchestration.
public enum MattermostLiveEventStreamLifecycleEvent: Sendable {
    case connecting(attempt: Int)
    case event(MattermostLiveEvent)
    case reconnecting(attempt: Int, delay: Duration)
}

public extension MattermostClient {
    /// Creates a live sync coordinator for this client.
    func liveSyncService() -> MattermostLiveSyncService {
        MattermostLiveSyncService(client: self)
    }
}

private struct MattermostLiveSyncThreadStateRefreshRequest: Equatable {
    let userID: String
    let teamID: String
    let threadID: String
}

private extension MattermostTypedLiveEvent {
    var invalidatesSidebarCategories: Bool {
        switch self {
        case .preferencesChanged, .preferencesDeleted:
            true
        default:
            false
        }
    }

    func unreadRefresh(
        options: MattermostLiveSyncOptions,
        fallbackUserID: String?
    ) -> (userID: String, channelID: String)? {
        switch self {
        case .channelViewed(let channelViewed) where options.refreshUnreadOnChannelViewed:
            guard let channelID = channelViewed.channelID,
                  let userID = channelViewed.userID ?? fallbackUserID else {
                return nil
            }
            return (userID, channelID)

        case .postUnread(let invalidation) where options.refreshUnreadOnPostUnread:
            guard let channelID = invalidation.channelID,
                  let userID = invalidation.userID ?? fallbackUserID else {
                return nil
            }
            return (userID, channelID)

        default:
            return nil
        }
    }

    func threadStateRefresh(
        fallbackUserID: String?,
        fallbackTeamID: String?
    ) -> MattermostLiveSyncThreadStateRefreshRequest? {
        let threadEvent: MattermostThreadEvent
        switch self {
        case .response(let event),
             .threadUpdated(let event),
             .threadFollowChanged(let event),
             .threadReadChanged(let event):
            threadEvent = event
        default:
            return nil
        }

        guard let userID = nonEmpty(threadEvent.userID ?? fallbackUserID),
              let teamID = nonEmpty(threadEvent.teamID ?? fallbackTeamID),
              let threadID = nonEmpty(threadEvent.threadID ?? threadEvent.rootID ?? threadEvent.postID) else {
            return nil
        }

        return MattermostLiveSyncThreadStateRefreshRequest(
            userID: userID,
            teamID: teamID,
            threadID: threadID
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}
