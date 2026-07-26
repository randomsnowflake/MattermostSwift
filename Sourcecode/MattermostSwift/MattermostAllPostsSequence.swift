import Foundation

/// A cancellation-aware sequence that walks all available posts in a channel.
///
/// Pages are loaded lazily. Duplicate posts from shifting server-side pages are
/// emitted once, and repeated/missing cursors terminate iteration instead of
/// creating an infinite request loop.
public struct MattermostAllPostsSequence: AsyncSequence, Sendable {
    public typealias Element = MattermostPost

    let client: MattermostClient
    let channelID: String
    let pageSize: Int

    public struct AsyncIterator: AsyncIteratorProtocol {
        let client: MattermostClient
        let channelID: String
        let pageSize: Int

        var before: String?
        var seenCursors: Set<String> = []
        var seenPostIDs: Set<String> = []
        var bufferedPosts: [MattermostPost] = []
        var bufferIndex = 0
        var isFinished = false

        public mutating func next() async throws -> MattermostPost? {
            while true {
                try Task.checkCancellation()

                if bufferIndex < bufferedPosts.count {
                    defer { bufferIndex += 1 }
                    return bufferedPosts[bufferIndex]
                }

                guard !isFinished else {
                    return nil
                }

                try await loadNextPage()
            }
        }

        private mutating func loadNextPage() async throws {
            let postList = try await client.posts(
                channelID: channelID,
                options: MattermostPostsOptions(
                    perPage: pageSize,
                    before: before
                )
            )
            let orderedPosts = postList.orderedPosts
            bufferedPosts = orderedPosts.filter { seenPostIDs.insert($0.id).inserted }
            bufferIndex = 0

            let hasAnotherPage = postList.hasNext ?? (orderedPosts.count >= pageSize)
            guard hasAnotherPage else {
                isFinished = true
                return
            }

            guard let nextCursor = postList.prevPostID.nonEmpty ?? orderedPosts.last?.id,
                  !nextCursor.isEmpty,
                  nextCursor != before,
                  seenCursors.insert(nextCursor).inserted else {
                isFinished = true
                return
            }
            before = nextCursor
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(client: client, channelID: channelID, pageSize: pageSize)
    }
}

public extension MattermostClient {
    /// Lazily loads every available post in a channel from newest to oldest.
    func allPosts(
        channelID: String,
        pageSize: Int = 60
    ) -> MattermostAllPostsSequence {
        MattermostAllPostsSequence(
            client: self,
            channelID: channelID,
            pageSize: Self.clampedPerPage(pageSize)
        )
    }
}
