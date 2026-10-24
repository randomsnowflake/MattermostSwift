import Foundation
import SwiftData

// Live-event application: one exhaustive switch both stages the change and reports whether
// the store mutated, so live-sync persistence cannot drift from the no-op cases.
extension MattermostStore {
    /// Decodes and stages cache changes for a supported WebSocket event.
    ///
    /// The returned typed event lets callers handle UI-specific behavior. Unsupported or
    /// invalidation-only events produce no direct cache mutation. Channel deletion removes
    /// related cached content while retaining a channel tombstone; post deletion retains a post
    /// tombstone when the post is known. All changes remain staged until ``save()``.
    @discardableResult
    public func apply(liveEvent: MattermostLiveEvent) throws -> MattermostTypedLiveEvent {
        try applyReportingMutation(liveEvent: liveEvent).typedEvent
    }

    // Report mutation from the same exhaustive switch that applies the event so live-sync
    // persistence cannot drift from this method's no-op cases.
    func applyReportingMutation(
        liveEvent: MattermostLiveEvent
    ) throws -> MattermostLiveEventApplication {
        let typedEvent = try liveEvent.typedEvent()
        let mutatesStore: Bool

        switch typedEvent {
        case .posted(let post), .postEdited(let post):
            try upsert(post: post)
            mutatesStore = true
        case .postDeleted(let post):
            if let post {
                try upsert(post: post)
                mutatesStore = true
            } else if let postID = liveEvent.stringData("post_id") ?? liveEvent.stringData("postId") {
                let cachedPostExists = try cachedPost(id: postID) != nil
                let deletedAt = liveEvent.int64Data("delete_at")
                    ?? liveEvent.int64Data("deleteAt")
                    ?? liveEvent.int64Data("update_at")
                    ?? liveEvent.int64Data("updateAt")
                    ?? Int64(Date.now.timeIntervalSince1970 * 1000)
                try markPostDeleted(id: postID, at: deletedAt)
                mutatesStore = cachedPostExists
            } else {
                mutatesStore = false
            }
        case .reactionAdded(let reaction):
            if let reaction {
                try upsert(reaction: reaction)
                mutatesStore = true
            } else {
                mutatesStore = false
            }
        case .reactionRemoved(let reaction):
            if let reaction {
                let id = MattermostCachedReaction.cacheID(
                    userID: reaction.userID,
                    postID: reaction.postID,
                    emojiName: reaction.emojiName
                )
                let cachedReactionExists = try cachedReaction(id: id) != nil
                try deleteCachedReaction(id: id)
                mutatesStore = cachedReactionExists
            } else {
                mutatesStore = false
            }
        case .statusChange(let statusChange):
            if let userID = statusChange.userID, let status = statusChange.status {
                let cachedStatus = MattermostCachedUserStatus(
                    userID: userID,
                    status: status,
                    manual: statusChange.manual
                )
                if let existing = try cachedUserStatus(userID: userID) {
                    existing.status = cachedStatus.status
                    existing.manual = cachedStatus.manual
                } else {
                    context.insert(cachedStatus)
                }
                mutatesStore = true
            } else {
                mutatesStore = false
            }
        case .channelCreated(let channel), .channelUpdated(let channel):
            if let channel {
                try upsert(channel: channel)
                mutatesStore = true
            } else {
                mutatesStore = false
            }
        case .channelDeleted(let channel, let channelID):
            if let channel {
                try upsert(channel: channel)
                try markChannelDeleted(id: channel.id, at: channel.deleteAt ?? Int64(Date.now.timeIntervalSince1970 * 1000))
                try deleteChannelContent(channelID: channel.id)
                mutatesStore = true
            } else if let channelID {
                let cachedChannelExists = try cachedChannel(id: channelID, includeDeleted: true) != nil
                let cachedContentExists = !(try cachedPosts(channelID: channelID, includeDeleted: true)).isEmpty
                try markChannelDeleted(id: channelID)
                try deleteChannelContent(channelID: channelID)
                mutatesStore = cachedChannelExists || cachedContentExists
            } else {
                mutatesStore = false
            }
        case .channelMemberUpdated(let member):
            if let member {
                try upsert(member: member)
                mutatesStore = true
            } else {
                mutatesStore = false
            }
        case .userUpdated(let user):
            if let user {
                try upsert(user: user)
                mutatesStore = true
            } else {
                mutatesStore = false
            }
        case .hello,
             .typing,
             .channelViewed,
             .multipleChannelsViewed,
             .preferencesChanged,
             .preferencesDeleted,
             .postUnread,
             .response,
             .threadUpdated,
             .threadFollowChanged,
             .threadReadChanged,
             .draftCreated,
             .draftUpdated,
             .draftDeleted,
             .cacheInvalidated,
             .unknown:
            mutatesStore = false
        }

        return MattermostLiveEventApplication(
            typedEvent: typedEvent,
            mutatesStore: mutatesStore
        )
    }
}

struct MattermostLiveEventApplication {
    let typedEvent: MattermostTypedLiveEvent
    let mutatesStore: Bool
}
