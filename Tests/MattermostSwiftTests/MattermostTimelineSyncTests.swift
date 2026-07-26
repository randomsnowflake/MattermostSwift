import Foundation
import Testing
@testable import MattermostSwift

@MainActor
@Test
func saturatedPostsSinceRepaginatesCompleteHistoryAndAdvancesCursor() async throws {
    let requests = MattermostRequestLog()
    let client = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            requests.append(try #require(request.url?.absoluteString))
            return try MattermostTestSupport.response(
                statusCode: 200,
                body: Data(saturatedSyncResponse(for: request).utf8),
                request: request
            )
        }
    )
    let store = try MattermostStore(inMemory: true)
    try store.setSyncCursor(scope: "channel-posts:channel-1", lastSyncAt: 5, lastItemID: "old-post")
    try store.save()

    let result = try await client.syncChannelPosts(
        channelID: "channel-1",
        to: store,
        perPage: 2,
        maxPages: 2
    )

    #expect(result.posts.map(\.id) == ["history-3", "history-2", "history-1"])
    #expect(result.pageCount == 2)
    #expect(result.cursorLastSyncAt == 30)
    #expect(result.cursorLastItemID == "history-3")
    #expect(try store.cachedPosts(channelID: "channel-1").map(\.id) == [
        "history-3", "history-2", "history-1",
    ])
    let recordedRequests = requests.values
    try #require(recordedRequests.count == 3)
    #expect(recordedRequests[0].contains("since=5"))
    #expect(recordedRequests[1].contains("page=0"))
    #expect(recordedRequests[2].contains("page=1"))
}

@MainActor
@Test
func saturatedPostsSinceThrowsIncompleteSyncWithoutAdvancingCursor() async throws {
    let client = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            try MattermostTestSupport.response(
                statusCode: 200,
                body: Data(saturatedSyncResponse(for: request).utf8),
                request: request
            )
        }
    )
    let store = try MattermostStore(inMemory: true)
    try store.setSyncCursor(scope: "channel-posts:channel-1", lastSyncAt: 5, lastItemID: "old-post")
    try store.save()

    await #expect(throws: MattermostError.incompleteSync(
        "posts/since for channel channel-1 reached Mattermost's 1,000-post cap; increase maxPages before retrying"
    )) {
        _ = try await client.syncChannelPosts(
            channelID: "channel-1",
            to: store,
            perPage: 2,
            maxPages: 1
        )
    }

    let cursor = try #require(try store.cachedSyncCursor(scope: "channel-posts:channel-1"))
    #expect(cursor.lastSyncAt == 5)
    #expect(cursor.lastItemID == "old-post")
    #expect(try store.cachedPosts(channelID: "channel-1").isEmpty)
}

private func saturatedSyncResponse(for request: URLRequest) throws -> String {
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: components.queryItems?.compactMap { item in
        item.value.map { (item.name, $0) }
    } ?? [])

    if query["since"] != nil {
        return timelinePostListJSON(
            posts: (0..<1_000).map { index in
                (id: "incremental-\(index)", timestamp: Int64(index + 100))
            }
        )
    }
    if query["page"] == "0" {
        return timelinePostListJSON(posts: [
            (id: "history-3", timestamp: 30),
            (id: "history-2", timestamp: 20),
        ])
    }
    if query["page"] == "1" {
        return timelinePostListJSON(posts: [
            (id: "history-1", timestamp: 10),
        ])
    }

    Issue.record("Unhandled saturation request: \(url.absoluteString)")
    return timelinePostListJSON(posts: [])
}

private func timelinePostListJSON(posts: [(id: String, timestamp: Int64)]) -> String {
    let order = posts.map { "\"\($0.id)\"" }.joined(separator: ",")
    let records = posts.map { post in
        """
        "\(post.id)": {
          "id": "\(post.id)",
          "create_at": \(post.timestamp),
          "update_at": \(post.timestamp),
          "edit_at": 0,
          "delete_at": 0,
          "user_id": "user-1",
          "channel_id": "channel-1",
          "root_id": "",
          "message": "\(post.id)",
          "type": ""
        }
        """
    }.joined(separator: ",")
    return #"{"order":[\#(order)],"posts":{\#(records)}}"#
}
