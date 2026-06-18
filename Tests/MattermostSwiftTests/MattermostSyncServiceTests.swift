import Foundation
import Testing
@testable import MattermostSwift

@MainActor
@Test
func syncServiceHydratesStoreCursorsAndBoundedUnreadRefresh() async throws {
    let tracker = MattermostSyncServiceRequestTracker()
    let client = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            try tracker.response(for: request)
        }
    )
    let store = try MattermostStore(inMemory: true)

    let result = try await client.syncService().sync(
        to: store,
        teamID: "team-1",
        channelID: "channel-1",
        options: MattermostSyncOptions(
            postPageSize: 2,
            maxPostPages: 2,
            includeChannelUsers: true,
            includeSidebarCategories: true,
            refreshUnreadForAllJoinedChannels: true
        )
    )

    let cursor = try #require(try store.cachedSyncCursor(scope: "team:team-1"))
    #expect(result.teamID == "team-1")
    #expect(result.postSync?.pageCount == 2)
    #expect(result.postSync?.posts.map(\.id) == ["post-2", "post-1", "post-3"])
    #expect(result.syncedMembersCount == 2)
    #expect(result.syncedUnreadsCount == 6)
    #expect(result.syncedCategoriesCount == 1)
    #expect(result.cachedTeamsCount == 1)
    #expect(result.cachedUsersCount == 2)
    #expect(result.cachedChannelsCount == 6)
    #expect(result.cachedMembersCount == 2)
    #expect(result.cachedUnreadsCount == 6)
    #expect(cursor.lastSyncAt == result.teamCursorLastSyncAt)
    #expect(try store.cachedPosts(channelID: "channel-1").map(\.id) == ["post-3", "post-2", "post-1"])
    #expect(try store.cachedSidebarCategories(teamID: "team-1").map(\.id) == ["category-1"])
    #expect(tracker.maxConcurrentUnreadRequests <= 4)
}

@MainActor
@Test
func syncServiceResolvesTeamByNameAndInferredChannels() async throws {
    let namedClient = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            try MattermostSyncServiceRequestTracker().response(for: request)
        }
    )
    let namedStore = try MattermostStore(inMemory: true)

    let namedResult = try await namedClient.syncService().sync(
        to: namedStore,
        teamName: "team",
        options: MattermostSyncOptions(includeSidebarCategories: false, refreshUnreadForAllJoinedChannels: false)
    )

    let inferredClient = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            try MattermostSyncServiceRequestTracker().response(for: request)
        }
    )
    let inferredStore = try MattermostStore(inMemory: true)
    let inferredResult = try await inferredClient.syncService().sync(
        to: inferredStore,
        options: MattermostSyncOptions(includeSidebarCategories: false, refreshUnreadForAllJoinedChannels: false)
    )

    #expect(namedResult.teamID == "team-1")
    #expect(namedResult.channels.map(\.id) == ["channel-1", "channel-2", "channel-3", "channel-4", "channel-5", "channel-6"])
    #expect(inferredResult.teamID == "team-1")
    #expect(inferredResult.channels.map(\.id) == ["channel-1", "channel-2", "channel-3", "channel-4", "channel-5", "channel-6"])
}

@MainActor
@Test
func syncServicePropagatesPartialHTTPFailure() async throws {
    let client = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            if request.url?.path == "/api/v4/users/user-1/status" {
                return try MattermostTestSupport.response(
                    statusCode: 503,
                    body: Data(#"{"message":"status unavailable"}"#.utf8),
                    request: request
                )
            }
            return try MattermostSyncServiceRequestTracker().response(for: request)
        }
    )
    let store = try MattermostStore(inMemory: true)

    await #expect(throws: MattermostError.httpStatus(code: 503, message: "status unavailable")) {
        _ = try await client.syncService().sync(to: store)
    }
}

private final class MattermostSyncServiceRequestTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var unreadRequestsInFlight = 0
    private(set) var maxConcurrentUnreadRequests = 0

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        let absoluteString = request.url?.absoluteString ?? ""

        if path.contains("/unread") {
            beginUnreadRequest()
            Thread.sleep(forTimeInterval: 0.02)
            endUnreadRequest()
        }

        let body: String
        switch path {
        case "/api/v4/users/me":
            body = #"{"id":"user-1","username":"alice","email":"alice@example.com"}"#
        case "/api/v4/users/user-1/status":
            body = #"{"user_id":"user-1","status":"online","manual":false}"#
        case "/api/v4/users/user-1/teams":
            body = #"[{"id":"team-1","name":"team","display_name":"Team","type":"O"}]"#
        case "/api/v4/users/me/teams/team-1/channels", "/api/v4/users/me/channels":
            body = channelsJSON
        case "/api/v4/channels/channel-1/members/me":
            body = #"{"channel_id":"channel-1","user_id":"user-1","roles":"channel_user","last_viewed_at":10,"msg_count":3,"mention_count":1}"#
        case "/api/v4/users/user-1/teams/team-1/channels/members":
            body = #"[{"channel_id":"channel-1","user_id":"user-1","roles":"channel_user"},{"channel_id":"channel-2","user_id":"user-1","roles":"channel_user"}]"#
        case "/api/v4/users/me/teams/team-1/channels/categories":
            body = #"{"order":["category-1"],"categories":[{"id":"category-1","user_id":"user-1","team_id":"team-1","display_name":"Favorites","type":"favorites","sort_order":1,"channel_ids":["channel-1"]}]}"#
        default:
            if path == "/api/v4/users", absoluteString.contains("in_channel=channel-1") {
                body = #"[{"id":"user-1","username":"alice"},{"id":"user-2","username":"bob"}]"#
            } else if path == "/api/v4/channels/channel-1/posts", absoluteString.contains("page=0") {
                body = postListJSON(ids: ["post-2", "post-1"])
            } else if path == "/api/v4/channels/channel-1/posts", absoluteString.contains("page=1") {
                body = postListJSON(ids: ["post-3"])
            } else if path.hasPrefix("/api/v4/users/user-1/channels/"), path.hasSuffix("/unread") {
                let channelID = path.split(separator: "/").dropLast().last.map(String.init) ?? "channel-1"
                body = #"{"team_id":"team-1","channel_id":"\#(channelID)","msg_count":4,"mention_count":1}"#
            } else {
                Issue.record("Unhandled request: \(absoluteString)")
                body = #"{"status":"OK"}"#
            }
        }

        return try MattermostTestSupport.response(
            statusCode: 200,
            body: Data(body.utf8),
            request: request
        )
    }

    private var channelsJSON: String {
        let channels = (1...6).map { index in
            #"{"id":"channel-\#(index)","team_id":"team-1","name":"channel-\#(index)","display_name":"Channel \#(index)","type":"O"}"#
        }
        return "[\(channels.joined(separator: ","))]"
    }

    private func postListJSON(ids: [String]) -> String {
        let posts = ids.map { id in
            let timestamp = id == "post-1" ? 10 : id == "post-2" ? 20 : 30
            return #""\#(id)":{"id":"\#(id)","create_at":\#(timestamp),"update_at":\#(timestamp),"edit_at":0,"delete_at":0,"user_id":"user-1","channel_id":"channel-1","root_id":"","message":"\#(id)","type":""}"#
        }
        let order = ids.map { #""\#($0)""# }.joined(separator: ",")
        return #"{"order":[\#(order)],"posts":{\#(posts.joined(separator: ","))}}"#
    }

    private func beginUnreadRequest() {
        lock.withLock {
            unreadRequestsInFlight += 1
            maxConcurrentUnreadRequests = max(maxConcurrentUnreadRequests, unreadRequestsInFlight)
        }
    }

    private func endUnreadRequest() {
        lock.withLock {
            unreadRequestsInFlight -= 1
        }
    }
}
