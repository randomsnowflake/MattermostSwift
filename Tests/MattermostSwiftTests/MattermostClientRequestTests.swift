import Foundation
import Testing
@testable import MattermostSwift

@Suite(.serialized)
struct MattermostClientRequestTests {
    @Test
    func logoutRevokesCurrentSession() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/logout")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        #expect(try await client.logoutCurrentSession().status == "OK")
    }

    @Test
    func currentUserDecodesAuthenticatedUser() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            let body = Data(#"{"id":"user-id","username":"alice","email":"alice@example.com"}"#.utf8)
            return try Self.response(statusCode: 200, body: body, request: request)
        }

        let user = try await client.currentUser()

        #expect(user.id == "user-id")
        #expect(user.username == "alice")
        #expect(user.email == "alice@example.com")
    }

    @Test
    func channelByIDHitsExpectedPath() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id")
            #expect(request.httpMethod == "GET")
            let body = Data(#"{"id":"channel-id","team_id":"team-id","name":"town-square","display_name":"Town Square","type":"O"}"#.utf8)
            return try Self.response(statusCode: 200, body: body, request: request)
        }

        let channel = try await client.channel(id: "channel-id")

        #expect(channel.id == "channel-id")
        #expect(channel.name == "town-square")
        #expect(channel.displayName == "Town Square")
    }

    @Test
    func sendPostEncodesRequestBodyAndDecodesPost() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/posts")
            #expect(request.httpMethod == "POST")
            let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
            #expect(body?["channel_id"] as? String == "channel-id")
            #expect(body?["message"] as? String == "hello world")
            #expect(body?["root_id"] as? String == "root-id")
            let responseBody = Data(#"""
            {"id":"post-id","create_at":1780000000000,"update_at":1780000000000,"edit_at":0,"delete_at":0,"user_id":"user-id","channel_id":"channel-id","root_id":"root-id","message":"hello world","type":""}
            """#.utf8)
            return try Self.response(statusCode: 201, body: responseBody, request: request)
        }

        let post = try await client.sendPost(
            channelID: "channel-id",
            message: "hello world",
            rootID: "root-id"
        )

        #expect(post.id == "post-id")
        #expect(post.message == "hello world")
        #expect(post.rootId == "root-id")
    }

    @Test
    func searchUsersPostsSearchTermAndDecodesResults() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/search")
            #expect(request.httpMethod == "POST")
            let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
            #expect(body?["term"] as? String == "ali")
            #expect(body?["in_channel_id"] as? String == "channel-id")
            let responseBody = Data(#"[{"id":"user-id","username":"alice"}]"#.utf8)
            return try Self.response(statusCode: 200, body: responseBody, request: request)
        }

        let users = try await client.searchUsers(term: "ali", inChannelID: "channel-id")

        #expect(users.map(\.id) == ["user-id"])
        #expect(users.first?.username == "alice")
    }

    @Test
    func updateUserProfileImageUsesMattermostMultipartContract() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/user-id/image")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let text = String(decoding: try Self.bodyData(from: request), as: UTF8.self)
            #expect(text.contains(#"Content-Disposition: form-data; name="image"; filename="profile.png""#))
            #expect(text.contains("Content-Type: image/png"))
            #expect(text.contains("profile-image-bytes"))
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        let status = try await client.updateUserProfileImage(
            userID: "user-id",
            data: Data("profile-image-bytes".utf8),
            contentType: "image/png"
        )

        #expect(status.isOK)
    }

    @Test
    func markThreadReadUsesMillisecondTimestampPath() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/teams/team-id/threads/thread-id/read/1780000000123")
            #expect(request.httpMethod == "PUT")
            #expect(request.httpBody == nil)
            let responseBody = Data(#"{"id":"thread-id","reply_count":4,"last_reply_at":1780000000123,"last_viewed_at":1780000000123,"participants":[],"post":null,"unread_replies":0,"unread_mentions":0,"is_urgent":false,"delete_at":0,"is_following":true}"#.utf8)
            return try Self.response(statusCode: 200, body: responseBody, request: request)
        }

        let thread = try await client.markThreadRead(
            teamID: "team-id",
            threadID: "thread-id",
            timestamp: 1_780_000_000_123
        )

        #expect(thread.id == "thread-id")
        #expect(thread.unreadReplies == 0)
        #expect(thread.lastViewedAt == 1_780_000_000_123)
    }

    @Test
    func viewChannelSendsCollapsedThreadsSupported() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/members/me/view")
            #expect(request.httpMethod == "POST")
            let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
            #expect(body?["channel_id"] as? String == "channel-id")
            #expect(body?["collapsed_threads_supported"] as? Bool == true)
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        let response = try await client.viewChannel(
            channelID: "channel-id",
            collapsedThreadsSupported: true
        )

        #expect(response.isOK)
    }

    // MARK: - Helpers

    private static func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async throws -> MattermostClient {
        try MattermostClient(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            token: "token",
            urlSession: await urlSession(handler: handler)
        )
    }

    private static func urlSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async -> URLSession {
        await MattermostTestSupport.urlSession(handler: handler)
    }

    private static func response(
        statusCode: Int,
        body: Data,
        contentType: String = "application/json",
        request: URLRequest
    ) throws -> (HTTPURLResponse, Data) {
        try MattermostTestSupport.response(
            statusCode: statusCode,
            body: body,
            contentType: contentType,
            request: request
        )
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        try MattermostTestSupport.bodyData(from: request)
    }
}
