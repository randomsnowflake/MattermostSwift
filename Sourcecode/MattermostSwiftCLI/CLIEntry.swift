import Foundation
@_spi(Testing) import MattermostSwift

@main
struct MattermostSwiftCLI {
}

struct E2ECleanupResult {
    let deletedPosts: Int
    let deletedCategory: Bool
    let deletedChannel: Bool
    let restoredOrder: Bool
}

enum CLIError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            message
        }
    }
}

actor LiveEventRecorder {
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

actor LiveSyncRecorder {
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

actor LiveSyncLifecycleDriver {
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
