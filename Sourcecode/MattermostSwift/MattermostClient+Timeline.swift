import Foundation

// MARK: - Timeline

extension MattermostClient {
    /// Loads a unified channel or thread timeline page.
    public func timeline(
        _ target: MattermostTimelineTarget,
        request: MattermostTimelineRequest = MattermostTimelineRequest()
    ) async throws -> MattermostTimelinePage {
        let postList: MattermostPostList
        switch target {
        case .channel(let channelID):
            postList = try await posts(
                channelID: channelID,
                page: request.page,
                perPage: request.perPage,
                since: request.since,
                before: request.before,
                after: request.after
            )
        case .thread(let rootPostID):
            postList = try await thread(
                postID: rootPostID,
                perPage: request.perPage,
                fromPost: request.fromPost,
                fromCreateAt: request.fromCreateAt,
                direction: request.direction,
                skipFetchThreads: request.skipFetchThreads,
                collapsedThreads: request.collapsedThreads,
                collapsedThreadsExtended: request.collapsedThreadsExtended
            )
        }

        return MattermostTimelinePage(target: target, postList: postList)
    }
}

public extension MattermostClient {
    /// Backfills posts for a channel using the store cursor and updates that cursor.
    @MainActor
    func syncChannelPosts(
        channelID: String,
        to store: MattermostStore,
        perPage: Int = 60,
        maxPages: Int = 1
    ) async throws -> MattermostChannelPostSyncResult {
        let cursorScope = "channel-posts:\(channelID)"
        let cursor = try store.cachedSyncCursor(scope: cursorScope)
        var allOrderedPosts: [MattermostPost] = []
        var pageCount = 0

        let postLists: [MattermostPostList]
        if let since = cursor?.lastSyncAt, since > 0 {
            postLists = [try await postsSince(channelID: channelID, since: since)]
        } else {
            var pages: [MattermostPostList] = []
            for page in 0..<max(1, maxPages) {
                let postList = try await posts(
                    channelID: channelID,
                    page: page,
                    perPage: max(1, perPage)
                )
                pages.append(postList)
                if postList.orderedPosts.count < max(1, perPage) {
                    break
                }
            }
            postLists = pages
        }

        for postList in postLists {
            try store.upsert(postList: postList)
            pageCount += 1
            allOrderedPosts.append(contentsOf: postList.orderedPosts)
        }

        // Deduplicate across pages, keeping first occurrence (matches the
        // previous `where postsByID[postID] == nil` accumulation semantics).
        var seen = Set<String>()
        let orderedPosts = allOrderedPosts.filter { seen.insert($0.id).inserted }
        let lastPost = orderedPosts.max { lhs, rhs in
            lhs.cacheTimestamp < rhs.cacheTimestamp
        }
        let cursorLastSyncAt = lastPost?.cacheTimestamp ?? cursor?.lastSyncAt ?? 0
        let cursorLastItemID = lastPost?.id ?? cursor?.lastItemID
        try store.setSyncCursor(
            scope: cursorScope,
            lastSyncAt: cursorLastSyncAt,
            lastItemID: cursorLastItemID
        )

        return MattermostChannelPostSyncResult(
            channelID: channelID,
            posts: orderedPosts,
            pageCount: pageCount,
            cursorLastSyncAt: cursorLastSyncAt,
            cursorLastItemID: cursorLastItemID
        )
    }

    /// Syncs a channel or thread timeline into the store and updates its cursor.
    @MainActor
    func syncTimeline(
        _ target: MattermostTimelineTarget,
        to store: MattermostStore,
        request: MattermostTimelineRequest = MattermostTimelineRequest(),
        maxPages: Int = 1
    ) async throws -> MattermostTimelineSyncResult {
        switch target {
        case .channel(let channelID):
            let result = try await syncChannelPosts(
                channelID: channelID,
                to: store,
                perPage: request.perPage,
                maxPages: maxPages
            )
            return MattermostTimelineSyncResult(
                target: target,
                posts: result.posts,
                pageCount: result.pageCount,
                cursorLastSyncAt: result.cursorLastSyncAt,
                cursorLastItemID: result.cursorLastItemID
            )

        case .thread:
            let page = try await timeline(target, request: request)
            try store.upsert(postList: page.postList)
            let lastPost = page.posts.max { lhs, rhs in
                lhs.cacheTimestamp < rhs.cacheTimestamp
            }
            let cursorLastSyncAt = lastPost?.cacheTimestamp ?? 0
            let cursorLastItemID = lastPost?.id
            try store.setSyncCursor(
                scope: target.cacheScope,
                lastSyncAt: cursorLastSyncAt,
                lastItemID: cursorLastItemID
            )
            try store.save()
            return MattermostTimelineSyncResult(
                target: target,
                posts: page.posts,
                pageCount: 1,
                cursorLastSyncAt: cursorLastSyncAt,
                cursorLastItemID: cursorLastItemID
            )
        }
    }
}
