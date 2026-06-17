import Foundation
import Testing
@testable import MattermostSwift

@Suite(.serialized)
struct MattermostClientRequestTests {
    @Test
    func currentUserDecodesAuthenticatedUser() async throws {
        let client = try Self.makeClient { request in
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
        let client = try Self.makeClient { request in
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
        let client = try Self.makeClient { request in
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
        let client = try Self.makeClient { request in
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

    // MARK: - Helpers

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
        MattermostClientRequestMockURLProtocol.setHandler(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MattermostClientRequestMockURLProtocol.self]
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

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? MattermostClientRequestTestError.unreadableBodyStream
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private enum MattermostClientRequestTestError: Error {
    case unreadableBodyStream
}

private final class MattermostClientRequestMockURLProtocol: URLProtocol, @unchecked Sendable {
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
