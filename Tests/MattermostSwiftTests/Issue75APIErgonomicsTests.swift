import Foundation
import Testing
@testable import MattermostSwift

@Suite("Issue 75 API ergonomics", .serialized)
struct Issue75APIErgonomicsTests {
    @Test
    func idPropertiesDecodeThroughMattermostWireKeys() throws {
        let payload = Data(#"""
        {
          "id":"post-id","create_at":1700000000123,"update_at":1700000000456,
          "edit_at":0,"delete_at":0,"user_id":"user-id","channel_id":"channel-id",
          "root_id":"root-id","original_id":"original-id","pending_post_id":"pending-id",
          "file_ids":["file-id"],"message":"hello","type":""
        }
        """#.utf8)

        let post = try mattermostSnakeCaseDecoder.decode(MattermostPost.self, from: payload)

        #expect(post.userID == "user-id")
        #expect(post.channelID == "channel-id")
        #expect(post.rootID == "root-id")
        #expect(post.originalID == "original-id")
        #expect(post.pendingPostID == "pending-id")
        #expect(post.fileIDs == ["file-id"])
        #expect(post.userId == post.userID)
        #expect(post.channelId == post.channelID)
    }

    @Test
    func metadataExposesTypedDefaultAndTolerantRawFallback() throws {
        let valid = Data(#"""
        {
          "id":"post-id","create_at":1,"update_at":1,"edit_at":0,"delete_at":0,
          "user_id":"user-id","channel_id":"channel-id","root_id":"",
          "message":"hello","type":"",
          "metadata":{"files":[{"id":"file-id","name":"a.txt"}],"future":{"x":1}}
        }
        """#.utf8)
        let post = try mattermostSnakeCaseDecoder.decode(MattermostPost.self, from: valid)
        #expect(post.metadata?.files?.first?.id == "file-id")
        #expect(post.rawMetadata?["future"] != nil)
        #expect(post.postMetadata == post.metadata)

        let malformed = Data(#"""
        {
          "id":"post-id","create_at":1,"update_at":1,"edit_at":0,"delete_at":0,
          "user_id":"user-id","channel_id":"channel-id","root_id":"",
          "message":"hello","type":"","metadata":{"files":[{"name":42}]}
        }
        """#.utf8)
        let tolerant = try mattermostSnakeCaseDecoder.decode(MattermostPost.self, from: malformed)
        #expect(tolerant.metadata == nil)
        #expect(tolerant.rawMetadata?["files"] != nil)
    }

    @Test
    func optionStructsNormalizeInputs() {
        let posts = MattermostPostsOptions(page: -1, perPage: 0, since: 42)
        #expect(posts.page == 0)
        #expect(posts.perPage == 1)
        #expect(posts.since == 42)

        let users = MattermostUserSearchOptions(term: "a", limit: 0)
        #expect(users.limit == 1)

        let channels = MattermostChannelSearchOptions(term: "town", page: -2, perPage: 0)
        #expect(channels.page == 0)
        #expect(channels.perPage == 1)

        let thread = MattermostThreadOptions(perPage: -3)
        #expect(thread.perPage == 0)
    }

    @Test
    func postsSinceOptionsDocumentedForkOmitsPaginationAndCursors() async throws {
        let client = try await makeClient { request in
            let components = try #require(URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(query["since"] == "1234")
            #expect(query["page"] == nil)
            #expect(query["per_page"] == nil)
            #expect(query["before"] == nil)
            #expect(query["after"] == nil)
            return try Self.response(body: Self.postListJSON(order: []), request: request)
        }

        _ = try await client.posts(
            channelID: "channel-id",
            options: MattermostPostsOptions(
                page: 9,
                perPage: 99,
                since: 1_234,
                before: "before",
                after: "after"
            )
        )
    }

    @Test
    func searchAndThreadOptionsDriveWireRequests() async throws {
        let paths = MattermostRequestLog()
        let client = try await makeClient { request in
            paths.append(request.url?.path ?? "")
            switch request.url?.path ?? "" {
            case "/api/v4/users/search":
                let body = try JSONSerialization.jsonObject(
                    with: MattermostTestSupport.bodyData(from: request)
                ) as? [String: Any]
                #expect(body?["term"] as? String == "ali")
                #expect(body?["team_id"] as? String == "team-id")
                #expect(body?["limit"] as? Int == 7)
                return try Self.response(body: Data("[]".utf8), request: request)
            case "/api/v4/channels/search":
                let body = try JSONSerialization.jsonObject(
                    with: MattermostTestSupport.bodyData(from: request)
                ) as? [String: Any]
                #expect(body?["term"] as? String == "town")
                #expect(body?["team_ids"] as? [String] == ["team-id"])
                #expect(body?["include_search_by_id"] as? Bool == true)
                return try Self.response(body: Data("[]".utf8), request: request)
            default:
                let components = try #require(URLComponents(
                    url: #require(request.url),
                    resolvingAgainstBaseURL: false
                ))
                let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                })
                #expect(query["perPage"] == "25")
                #expect(query["direction"] == "up")
                #expect(query["collapsedThreads"] == "true")
                return try Self.response(body: Self.postListJSON(order: []), request: request)
            }
        }

        _ = try await client.searchUsers(
            options: MattermostUserSearchOptions(term: "ali", teamID: "team-id", limit: 7)
        )
        _ = try await client.searchChannels(
            options: MattermostChannelSearchOptions(
                term: "town",
                teamIDs: ["team-id"],
                includeSearchByID: true
            )
        )
        _ = try await client.thread(
            postID: "post-id",
            options: MattermostThreadOptions(
                perPage: 25,
                direction: .up,
                collapsedThreads: true
            )
        )

        #expect(paths.values == [
            "/api/v4/users/search",
            "/api/v4/channels/search",
            "/api/v4/posts/post-id/thread",
        ])
    }

    @Test
    func pluralChannelMemberAddDecodesEveryMembership() async throws {
        let client = try await makeClient { request in
            #expect(request.url?.path == "/api/v4/channels/channel-id/members")
            let json = try JSONSerialization.jsonObject(with: MattermostTestSupport.bodyData(from: request)) as? [String: Any]
            #expect(json?["user_ids"] as? [String] == ["user-a", "user-b"])
            let body = Data(#"""
            [
              {"channel_id":"channel-id","user_id":"user-a"},
              {"channel_id":"channel-id","user_id":"user-b"}
            ]
            """#.utf8)
            return try Self.response(body: body, request: request)
        }

        let members = try await client.addChannelMembers(
            channelID: "channel-id",
            userIDs: ["user-a", "user-b"]
        )
        #expect(members.map(\.userID) == ["user-a", "user-b"])
    }

    @Test
    func subjectFirstOverloadsUseExpectedPaths() async throws {
        let paths = MattermostRequestLog()
        let client = try await makeClient { request in
            paths.append(request.url?.path ?? "")
            if request.url?.path.hasSuffix("/posts/unread") == true {
                return try Self.response(body: Self.postListJSON(order: []), request: request)
            }
            if request.url?.path.hasSuffix("/unread") == true {
                return try Self.response(
                    body: Data(#"{"team_id":"team-id","channel_id":"channel-id","msg_count":1,"mention_count":0}"#.utf8),
                    request: request
                )
            }
            return try Self.response(body: Data("[]".utf8), request: request)
        }

        _ = try await client.channelMembers(userID: "user-id", teamID: "team-id")
        _ = try await client.channelUnread(channelID: "channel-id", userID: "user-id")
        _ = try await client.postsAroundLastUnread(channelID: "channel-id", userID: "user-id")

        #expect(paths.values == [
            "/api/v4/users/user-id/teams/team-id/channels/members",
            "/api/v4/users/user-id/channels/channel-id/unread",
            "/api/v4/users/user-id/channels/channel-id/posts/unread",
        ])
    }

    @Test
    func dateBridgeAndThreadReadDateOverloadUseMilliseconds() async throws {
        let milliseconds: Int64 = 1_780_000_000_123
        let date = Date(mattermostMilliseconds: milliseconds)
        #expect(date.mattermostMilliseconds == milliseconds)

        let client = try await makeClient { request in
            #expect(request.url?.path.hasSuffix("/read/1780000000123") == true)
            return try Self.response(
                body: Data(#"{"id":"thread-id","last_viewed_at":1780000000123}"#.utf8),
                request: request
            )
        }
        let thread = try await client.markThreadRead(
            teamID: "team-id",
            threadID: "thread-id",
            upTo: date
        )
        #expect(thread.lastViewedAt == milliseconds)
    }

    @Test
    func allPostsAdvancesCursorDeduplicatesAndStops() async throws {
        let requests = MattermostRequestLog()
        let client = try await makeClient { request in
            let components = try #require(URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false))
            let before = components.queryItems?.first(where: { $0.name == "before" })?.value
            requests.append(before ?? "<initial>")

            if before == nil {
                return try Self.response(
                    body: Self.postListJSON(
                        order: ["p3", "p2"],
                        previousID: "p2",
                        hasNext: true
                    ),
                    request: request
                )
            }
            return try Self.response(
                body: Self.postListJSON(
                    order: ["p2", "p1"],
                    previousID: "p1",
                    hasNext: false
                ),
                request: request
            )
        }

        var ids: [String] = []
        for try await post in client.allPosts(channelID: "channel-id", pageSize: 2) {
            ids.append(post.id)
        }

        #expect(ids == ["p3", "p2", "p1"])
        #expect(requests.values == ["<initial>", "p2"])
    }

    @Test
    func insecureLoginAndMFACheckCanOptInAndSessionRemembersServer() async throws {
        let session = await MattermostTestSupport.urlSession { request in
            if request.url?.path.hasSuffix("/users/mfa") == true {
                return try Self.response(
                    body: Data(#"{"mfa_required":true}"#.utf8),
                    request: request
                )
            }
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json", "Token": "session-token"]
            ))
            return (response, Data(#"{"id":"user-id","username":"alice"}"#.utf8))
        }
        let serverURL = try #require(URL(string: "http://mattermost.example.com"))

        #expect(try await MattermostClient.checkMFARequired(
            serverURL: serverURL,
            loginID: "alice",
            allowInsecureHTTP: true,
            urlSession: session
        ))
        let login = try await MattermostClient.login(
            serverURL: serverURL,
            loginID: "alice",
            password: "password",
            allowInsecureHTTP: true,
            urlSession: session
        )

        #expect(login.serverURL == serverURL)
        #expect(login.allowInsecureHTTP)
        #expect(try login.client().configuration.serverURL == serverURL)
    }

    @Test
    func environmentRenameReconnectDurationAndInspectableInsecureState() throws {
        let client = try MattermostClient.fromEnvironment([
            "MATTERMOST_URL": "https://mattermost.example.com",
            "MATTERMOST_TOKEN": "token",
        ])
        #expect(client.configuration.serverURL.absoluteString == "https://mattermost.example.com")

        let policy = MattermostLiveEventReconnectPolicy(
            initialDelay: .milliseconds(250),
            maximumDelay: .seconds(2),
            multiplier: 2
        )
        #expect(policy.delay(for: 0) == .milliseconds(250))
        #expect(policy.delay(for: 3) == .seconds(2))

        let insecure = try MattermostConfiguration(
            serverURL: #require(URL(string: "http://mattermost.example.com")),
            authentication: .bearerToken("token"),
            allowInsecureHTTP: true
        )
        #expect(insecure.usesInsecureHTTP)
    }

    private static func makeClient(
        handler: @escaping MattermostTestSupport.URLHandler
    ) async throws -> MattermostClient {
        try MattermostClient(
            serverURL: #require(URL(string: "https://mattermost.example.com")),
            token: "token",
            urlSession: await MattermostTestSupport.urlSession(handler: handler)
        )
    }

    private static func response(
        body: Data,
        request: URLRequest
    ) throws -> (HTTPURLResponse, Data) {
        try MattermostTestSupport.response(statusCode: 200, body: body, request: request)
    }

    private static func postListJSON(
        order: [String],
        previousID: String? = nil,
        hasNext: Bool? = nil
    ) -> Data {
        let postValues = order.map { id in
            #""\#(id)":{"id":"\#(id)","create_at":1,"update_at":1,"edit_at":0,"delete_at":0,"user_id":"user","channel_id":"channel-id","root_id":"","message":"\#(id)","type":""}"#
        }.joined(separator: ",")
        let orderJSON = order.map { #""\#($0)""# }.joined(separator: ",")
        let previousJSON = previousID.map { #","prev_post_id":"\#($0)""# } ?? ""
        let hasNextJSON = hasNext.map { #","has_next":\#($0)"# } ?? ""
        return Data(#"{"order":[\#(orderJSON)],"posts":{\#(postValues)}\#(previousJSON)\#(hasNextJSON)}"#.utf8)
    }
}
