import Foundation
import Testing
@testable import MattermostSwift

@Suite(.serialized)
struct MattermostHTTPClientErrorTests {
    @Test
    func clientMapsMattermostErrorResponseMessage() async throws {
        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me")
            let body = Data(#"{"id":"api.context.permissions.app_error","message":"No permission"}"#.utf8)
            return try Self.response(statusCode: 403, body: body, request: request)
        }

        await #expect(throws: MattermostError.httpStatus(code: 403, message: "No permission")) {
            _ = try await client.currentUser()
        }
    }

    @Test
    func clientMapsHTTPStatusWithoutMattermostErrorMessage() async throws {
        let client = try Self.makeClient { request in
            try Self.response(statusCode: 502, body: Data("Bad gateway".utf8), request: request)
        }

        await #expect(throws: MattermostError.httpStatus(code: 502, message: nil)) {
            _ = try await client.currentUser()
        }
    }

    @Test
    func clientRejectsEmptySuccessfulJSONResponse() async throws {
        let client = try Self.makeClient { request in
            try Self.response(statusCode: 200, body: Data(), request: request)
        }

        await #expect(throws: MattermostError.emptyResponse) {
            _ = try await client.currentUser()
        }
    }

    @Test
    func dataRequestMapsHTTPStatusMessage() async throws {
        let configuration = try MattermostConfiguration(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            authentication: .bearerToken("token")
        )
        let httpClient = MattermostHTTPClient(
            configuration: configuration,
            urlSession: Self.urlSession { request in
                let body = Data(#"{"message":"File not found"}"#.utf8)
                return try Self.response(statusCode: 404, body: body, request: request)
            }
        )

        await #expect(throws: MattermostError.httpStatus(code: 404, message: "File not found")) {
            _ = try await httpClient.data("/files/file-id")
        }
    }

    @Test
    func clientDownloadsProfileImageBytes() async throws {
        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/image")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
            let body = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
            return try Self.response(statusCode: 200, body: body, contentType: "image/png", request: request)
        }

        let data = try await client.userProfileImage()

        #expect(data == Data([0x89, 0x50, 0x4E, 0x47, 0x00]))
    }

    @Test
    func clientDownloadsDefaultProfileImageBytes() async throws {
        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/user-id/image/default")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
            let body = Data([0xFF, 0xD8, 0xFF, 0x00])
            return try Self.response(statusCode: 200, body: body, contentType: "image/jpeg", request: request)
        }

        let data = try await client.defaultUserProfileImage(userID: "user-id")

        #expect(data == Data([0xFF, 0xD8, 0xFF, 0x00]))
    }

    @Test
    func clientClampsChannelUsersPagination() async throws {
        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users?in_channel=channel-id&page=0&per_page=1")
            return try Self.response(statusCode: 200, body: Data("[]".utf8), request: request)
        }

        let users = try await client.users(channelID: "channel-id", page: -2, perPage: 0)

        #expect(users.isEmpty)
    }

    @Test
    func clientClampsChannelMembersPagination() async throws {
        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/members?page=0&per_page=1")
            return try Self.response(statusCode: 200, body: Data("[]".utf8), request: request)
        }

        let members = try await client.channelMembers(channelID: "channel-id", page: -2, perPage: 0)

        #expect(members.isEmpty)
    }

    @Test
    func clientClampsPublicChannelPagination() async throws {
        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/team-id/channels?page=0&per_page=1")
            return try Self.response(statusCode: 200, body: Data("[]".utf8), request: request)
        }

        let channels = try await client.publicChannels(teamID: "team-id", page: -2, perPage: 0)

        #expect(channels.isEmpty)
    }

    @Test
    func clientClampsTeamMemberPagination() async throws {
        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/team-id/members?page=0&per_page=1&exclude_deleted_users=true")
            return try Self.response(statusCode: 200, body: Data("[]".utf8), request: request)
        }

        let members = try await client.teamMembers(
            teamID: "team-id",
            page: -2,
            perPage: 0,
            excludeDeletedUsers: true
        )

        #expect(members.isEmpty)
    }

    @Test
    func clientClampsChannelPostsPagination() async throws {
        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/posts?page=0&per_page=1")
            return try Self.response(statusCode: 200, body: Data(#"{"order":[],"posts":{}}"#.utf8), request: request)
        }

        let posts = try await client.posts(channelID: "channel-id", page: -1, perPage: -20)

        #expect(posts.order.isEmpty)
        #expect(posts.posts.isEmpty)
    }

    @Test
    func clientClampsCustomEmojiPagination() async throws {
        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/emoji?page=0&per_page=1&sort=name")
            return try Self.response(statusCode: 200, body: Data("[]".utf8), request: request)
        }

        let emoji = try await client.customEmoji(page: -1, perPage: 0)

        #expect(emoji.isEmpty)
    }

    @MainActor
    @Test
    func syncChannelPostsUsesStoredCursorForMissedEventBackfill() async throws {
        let store = try MattermostStore(inMemory: true)
        try store.setSyncCursor(
            scope: "channel-posts:channel-id",
            lastSyncAt: 1_780_000_000_000,
            lastItemID: "old-post"
        )

        let client = try Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/posts?since=1780000000000")
            let body = Data("""
            {
              "order": ["missed-post"],
              "posts": {
                "missed-post": {
                  "id": "missed-post",
                  "create_at": 1780000000100,
                  "update_at": 1780000000200,
                  "edit_at": 0,
                  "delete_at": 0,
                  "user_id": "user-id",
                  "channel_id": "channel-id",
                  "root_id": "",
                  "message": "missed while socket was down",
                  "type": ""
                }
              }
            }
            """.utf8)
            return try Self.response(statusCode: 200, body: body, request: request)
        }

        let result = try await client.syncChannelPosts(
            channelID: "channel-id",
            to: store
        )

        let cachedPost = try #require(try store.cachedPost(id: "missed-post"))
        let cursor = try #require(try store.cachedSyncCursor(scope: "channel-posts:channel-id"))

        #expect(result.posts.map(\.id) == ["missed-post"])
        #expect(result.pageCount == 1)
        #expect(result.cursorLastSyncAt == 1_780_000_000_200)
        #expect(result.cursorLastItemID == "missed-post")
        #expect(cachedPost.message == "missed while socket was down")
        #expect(cursor.lastSyncAt == 1_780_000_000_200)
        #expect(cursor.lastItemID == "missed-post")
    }

    @Test
    func sessionBuildsBearerTokenClient() async throws {
        let session = MattermostSession(
            user: MattermostUser(
                id: "user-id",
                username: "alice",
                email: nil,
                firstName: nil,
                lastName: nil,
                nickname: nil,
                position: nil,
                locale: nil,
                timezone: nil
            ),
            token: "session-token"
        )
        let client = try session.client(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            urlSession: Self.urlSession { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
                let body = Data(#"{"id":"user-id","username":"alice"}"#.utf8)
                return try Self.response(statusCode: 200, body: body, request: request)
            }
        )

        let user = try await client.currentUser()

        #expect(user.id == "user-id")
        #expect(user.username == "alice")
    }

    @Test
    func loginUsesTokenResponseHeaderWhenPresent() async throws {
        let session = try await MattermostClient.login(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            loginID: "user@example.com",
            password: "password",
            urlSession: Self.urlSession { request in
                #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/login")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
                #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
                let body = Data(#"{"id":"user-id","username":"alice"}"#.utf8)
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "application/json",
                        "Token": "header-session-token",
                        "Set-Cookie": "MMAUTHTOKEN=cookie-session-token; Path=/; HttpOnly",
                    ]
                ))
                return (response, body)
            }
        )

        #expect(session.user.id == "user-id")
        #expect(session.token == "header-session-token")
        #expect(session.tokenSource == .responseHeader)
    }

    @Test
    func loginFallsBackToMattermostAuthCookieWhenTokenHeaderIsMissing() async throws {
        let session = try await MattermostClient.login(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            loginID: "user@example.com",
            password: "password",
            urlSession: Self.urlSession { request in
                #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
                #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
                let body = Data(#"{"id":"user-id","username":"alice"}"#.utf8)
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "application/json",
                        "Set-Cookie": "MMAUTHTOKEN=cookie-session-token; Path=/; HttpOnly",
                    ]
                ))
                return (response, body)
            }
        )

        #expect(session.user.username == "alice")
        #expect(session.token == "cookie-session-token")
        #expect(session.tokenSource == .authCookie)
    }

    @Test
    func loginFindsMattermostAuthCookieAmongBrowserSessionCookies() async throws {
        let session = try await MattermostClient.login(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            loginID: "user@example.com",
            password: "password",
            urlSession: Self.urlSession { request in
                let body = Data(#"{"id":"user-id","username":"alice"}"#.utf8)
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "application/json",
                        "Set-Cookie": [
                            "MMUSERID=user-id; Path=/; Expires=Tue, 16 Jun 2037 13:00:00 GMT",
                            "MMAUTHTOKEN=cookie-session-token; Path=/; Expires=Tue, 16 Jun 2037 13:00:00 GMT; HttpOnly",
                            "MMCSRF=csrf-token; Path=/; Expires=Tue, 16 Jun 2037 13:00:00 GMT",
                        ].joined(separator: ", "),
                    ]
                ))
                return (response, body)
            }
        )

        #expect(session.token == "cookie-session-token")
        #expect(session.tokenSource == .authCookie)
    }

    private static func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) throws -> MattermostClient {
        try MattermostClient(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            token: "token",
            urlSession: urlSession(handler: handler)
        )
    }

    private static func urlSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MattermostMockURLProtocol.setHandler(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MattermostMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        statusCode: Int,
        body: Data,
        contentType: String = "application/json",
        request: URLRequest
    ) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        ))
        return (response, body)
    }
}

private final class MattermostMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.withLock {
            Self.handler = handler
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let handler = lock.withLock {
            Self.handler
        }
        guard let handler else {
            throw MattermostError.invalidHTTPResponse
        }
        return try handler(request)
    }
}
