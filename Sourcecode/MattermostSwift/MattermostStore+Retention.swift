import Foundation
import SwiftData

// Retention and purge: bounded pruning keeps cursors; a full channel purge drops them in the
// same operation, so a later sync cannot resume from a cursor whose content is gone.
extension MattermostStore {
    /// Permanently removes older cached posts and their cached reactions, files, and thread rows.
    /// - Parameters:
    ///   - channelID: The channel whose cache to bound.
    ///   - keepCount: The number of newest rows to retain. Negative values are treated as zero.
    ///
    /// Tombstones count toward `keepCount`. The deletions remain staged until ``save()``.
    /// This method scans the channel on the main actor. Call it only when a main-thread hitch is
    /// acceptable, such as an app-controlled idle window.
    public func prunePosts(channelID: String, keepCount: Int = 200) throws {
        let keepCount = max(0, keepCount)
        let posts = try cachedPosts(channelID: channelID, includeDeleted: true)
        let prunedPosts = Array(posts.dropFirst(keepCount))
        try deleteCachedPostContent(postIDs: prunedPosts.map(\.id))
        for post in prunedPosts {
            context.delete(post)
        }
    }

    /// Permanently deletes a channel's cached posts, unreads, reactions, files, members, thread
    /// rows, and the channel/thread timeline sync cursors.
    ///
    /// Dropping the cursors makes the next timeline sync take the initial-history path; an
    /// incremental `since` request would otherwise never refill the now-empty cache.
    ///
    /// This method preserves the channel row and is not a tombstone operation. The deletions
    /// remain staged until ``save()``. It scans the channel on the main actor, so call it only
    /// when a main-thread hitch is acceptable, typically when the channel leaves the host's
    /// retention scope.
    public func deleteChannelContent(channelID: String) throws {
        let posts = try cachedPosts(channelID: channelID, includeDeleted: true)

        for post in posts {
            context.delete(post)
        }
        for unread in try context.fetch(FetchDescriptor<MattermostCachedChannelUnread>(
            predicate: #Predicate { $0.channelId == channelID }
        )) {
            context.delete(unread)
        }
        for member in try context.fetch(FetchDescriptor<MattermostCachedChannelMember>(
            predicate: #Predicate { $0.channelId == channelID }
        )) {
            context.delete(member)
        }
        let cursorScopes = [MattermostTimelineTarget.channel(id: channelID).cacheScope]
            + posts.map { MattermostTimelineTarget.thread(rootPostID: $0.id).cacheScope }
        for cursor in try fetchInBatches(ids: cursorScopes, descriptor: { chunkScopes in
            FetchDescriptor<MattermostSyncCursor>(predicate: #Predicate { chunkScopes.contains($0.scope) })
        }) {
            context.delete(cursor)
        }
        try deleteCachedPostContent(postIDs: posts.map(\.id))
    }

    private func deleteCachedPostContent(postIDs: [String]) throws {
        guard !postIDs.isEmpty else {
            return
        }
        for reaction in try fetchInBatches(ids: postIDs, descriptor: { chunkIDs in
            FetchDescriptor<MattermostCachedReaction>(predicate: #Predicate { chunkIDs.contains($0.postId) })
        }) {
            context.delete(reaction)
        }
        for file in try fetchInBatches(ids: postIDs, descriptor: { chunkIDs in
            FetchDescriptor<MattermostCachedFile>(predicate: #Predicate { file in
                if let pid = file.postId { return chunkIDs.contains(pid) } else { return false }
            })
        }) {
            context.delete(file)
        }
        for thread in try fetchInBatches(ids: postIDs, descriptor: { chunkIDs in
            FetchDescriptor<MattermostCachedThread>(predicate: #Predicate { chunkIDs.contains($0.rootId) })
        }) {
            context.delete(thread)
        }
    }
}
