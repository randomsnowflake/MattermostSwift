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
            try await tracker.response(for: request)
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
    #expect(tracker.maxConcurrentUnreadRequests == 4)
}

@MainActor
@Test
func syncServiceFetchesAndCachesEveryChannelUserPage() async throws {
    let tracker = MattermostSyncServiceRequestTracker(channelUserPageSizes: [60, 2], requiredUnreadOverlap: 1)
    let client = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            try await tracker.response(for: request)
        }
    )
    let store = try MattermostStore(inMemory: true)

    let result = try await client.syncService().sync(
        to: store,
        teamID: "team-1",
        channelID: "channel-1",
        options: MattermostSyncOptions(
            postPageSize: 2,
            maxPostPages: 1,
            includeChannelUsers: true,
            includeSidebarCategories: false,
            refreshUnreadForAllJoinedChannels: false
        )
    )

    #expect(tracker.channelUserRequests.map { $0.page } == [0, 1])
    #expect(tracker.channelUserRequests.map { $0.perPage } == [60, 60])
    #expect(result.syncedUsersCount == 62)
    #expect(result.cachedUsersCount == 62)
    #expect(try store.cachedUser(id: "user-62")?.username == "user-62")
}

@MainActor
@Test
func syncServiceResolvesTeamByNameAndInferredChannels() async throws {
    let namedClient = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            try await MattermostSyncServiceRequestTracker().response(for: request)
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
            try await MattermostSyncServiceRequestTracker().response(for: request)
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
            return try await MattermostSyncServiceRequestTracker().response(for: request)
        }
    )
    let store = try MattermostStore(inMemory: true)

    await #expect(throws: MattermostError.httpStatus(
        code: 503,
        message: "status unavailable",
        apiError: MattermostAPIErrorBody(message: "status unavailable")
    )) {
        _ = try await client.syncService().sync(to: store)
    }
}

@MainActor
@Test
func syncServicePersistsETagsAndReturnsCachedListsForNotModifiedResponses() async throws {
    let tracker = MattermostConditionalSyncRequestTracker()
    let client = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            try await tracker.response(for: request)
        }
    )
    let store = try MattermostStore(inMemory: true)
    let options = MattermostSyncOptions(
        postPageSize: 60,
        maxPostPages: 1,
        includeChannelUsers: false,
        includeSidebarCategories: true,
        refreshUnreadForAllJoinedChannels: false
    )

    let first = try await client.syncService().sync(
        to: store,
        teamID: "team-1",
        channelID: "channel-1",
        options: options
    )
    try store.upsert(channel: MattermostChannel(
        id: "unrelated-channel",
        createAt: nil,
        updateAt: nil,
        teamId: "team-2",
        name: "unrelated",
        displayName: "Unrelated",
        type: .open,
        header: nil,
        purpose: nil,
        deleteAt: nil,
        totalMsgCount: nil,
        totalMsgCountRoot: nil,
        lastPostAt: nil,
        lastRootPostAt: nil
    ))
    try store.save()
    let second = try await client.syncService().sync(
        to: store,
        teamID: "team-1",
        channelID: "channel-1",
        options: options
    )

    #expect(first.teams == second.teams)
    #expect(first.channels == second.channels)
    #expect(second.syncedCategoriesCount == 1)
    #expect(try store.cachedSidebarCategories(teamID: "team-1").map(\.id) == ["category-1"])
    #expect(tracker.notModifiedResponseCount == 3)
    #expect(tracker.receivedValidators == [
        "/api/v4/users/user-1/teams": #""teams-v1""#,
        "/api/v4/users/me/teams/team-1/channels": #"W/"channels-v1""#,
        "/api/v4/users/me/teams/team-1/channels/categories": #""categories-v1""#,
    ])
    #expect(tracker.unexpectedConditionalPaths.isEmpty)
}

private final class MattermostSyncServiceRequestTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let channelUserPageSizes: [Int]?
    private let unreadRequestGate: MattermostUnreadRequestGate
    private var unreadRequestsInFlight = 0
    private var maxConcurrentUnreadRequestsStorage = 0
    private var storedChannelUserRequests: [(page: Int, perPage: Int)] = []

    /// `requiredUnreadOverlap` is the number of unread requests the gate holds before releasing.
    /// Tests that do not refresh unread for every joined channel must lower it or the single
    /// unread request blocks forever.
    init(channelUserPageSizes: [Int]? = nil, requiredUnreadOverlap: Int = 4) {
        self.channelUserPageSizes = channelUserPageSizes
        unreadRequestGate = MattermostUnreadRequestGate(requiredOverlap: requiredUnreadOverlap)
    }

    var channelUserRequests: [(page: Int, perPage: Int)] {
        lock.withLock { storedChannelUserRequests }
    }

    var maxConcurrentUnreadRequests: Int {
        lock.withLock { maxConcurrentUnreadRequestsStorage }
    }

    func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        let absoluteString = request.url?.absoluteString ?? ""

        if path.contains("/unread") {
            beginUnreadRequest()
            await unreadRequestGate.waitUntilRequiredOverlap()
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
                body = channelUsersJSON(for: request)
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

    private func channelUsersJSON(for request: URLRequest) -> String {
        guard let components = request.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            Issue.record("Invalid channel-user request URL")
            return "[]"
        }
        let page = Int(components.queryItems?.first(where: { $0.name == "page" })?.value ?? "") ?? 0
        let perPage = Int(components.queryItems?.first(where: { $0.name == "per_page" })?.value ?? "") ?? 0
        lock.withLock {
            storedChannelUserRequests.append((page: page, perPage: perPage))
        }

        guard let channelUserPageSizes else {
            return #"[{"id":"user-1","username":"alice"},{"id":"user-2","username":"bob"}]"#
        }
        guard channelUserPageSizes.indices.contains(page) else {
            Issue.record("Unexpected channel-user page: \(page)")
            return "[]"
        }

        let firstUserNumber = channelUserPageSizes.prefix(page).reduce(0, +) + 1
        let lastUserNumber = firstUserNumber + channelUserPageSizes[page]
        let users = (firstUserNumber..<lastUserNumber).map { number in
            #"{"id":"user-\#(number)","username":"user-\#(number)"}"#
        }
        return "[\(users.joined(separator: ","))]"
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
            maxConcurrentUnreadRequestsStorage = max(
                maxConcurrentUnreadRequestsStorage,
                unreadRequestsInFlight
            )
        }
    }

    private func endUnreadRequest() {
        lock.withLock {
            unreadRequestsInFlight -= 1
        }
    }
}

private actor MattermostUnreadRequestGate {
    private let requiredOverlap: Int
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(requiredOverlap: Int) {
        self.requiredOverlap = requiredOverlap
    }

    func waitUntilRequiredOverlap() async {
        guard !isReleased else { return }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard waiters.count == requiredOverlap else { return }

            isReleased = true
            let continuations = waiters
            waiters.removeAll()
            for continuation in continuations {
                continuation.resume()
            }
        }
    }
}

private final class MattermostConditionalSyncRequestTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let fallback = MattermostSyncServiceRequestTracker(requiredUnreadOverlap: 1)
    private let validatorsByPath: [String: String] = [
        "/api/v4/users/user-1/teams": #""teams-v1""#,
        "/api/v4/users/me/teams/team-1/channels": #"W/"channels-v1""#,
        "/api/v4/users/me/teams/team-1/channels/categories": #""categories-v1""#,
    ]
    private var receivedValidatorsStorage: [String: String] = [:]
    private var unexpectedConditionalPathsStorage: [String] = []
    private var notModifiedResponseCountStorage = 0

    var receivedValidators: [String: String] {
        lock.withLock { receivedValidatorsStorage }
    }

    var unexpectedConditionalPaths: [String] {
        lock.withLock { unexpectedConditionalPathsStorage }
    }

    var notModifiedResponseCount: Int {
        lock.withLock { notModifiedResponseCountStorage }
    }

    func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        let requestETag = request.value(forHTTPHeaderField: "If-None-Match")

        if let validator = validatorsByPath[path] {
            if let requestETag {
                lock.withLock {
                    receivedValidatorsStorage[path] = requestETag
                }
            }
            if requestETag == validator {
                lock.withLock {
                    notModifiedResponseCountStorage += 1
                }
                return try response(statusCode: 304, body: Data(), request: request)
            }

            let (_, body) = try await fallback.response(for: request)
            return try response(
                statusCode: 200,
                body: body,
                request: request,
                headers: ["ETag": validator]
            )
        }

        if requestETag != nil {
            lock.withLock {
                unexpectedConditionalPathsStorage.append(path)
            }
        }

        if path == "/api/v4/channels/channel-1/posts" {
            return try response(
                statusCode: 200,
                body: Data(#"{"order":[],"posts":{}}"#.utf8),
                request: request
            )
        }
        return try await fallback.response(for: request)
    }

    private func response(
        statusCode: Int,
        body: Data,
        request: URLRequest,
        headers: [String: String] = [:]
    ) throws -> (HTTPURLResponse, Data) {
        var headers = headers
        headers["Content-Type"] = "application/json"
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
        return (response, body)
    }
}
