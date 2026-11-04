import Foundation
import Testing
@testable import MattermostSwift

@Suite(.serialized)
struct MattermostFilePreviewTests {
    @Test
    func fileInfoDecodesBase64MiniPreview() throws {
        let json = #"{"id":"f1","name":"shot.png","extension":"png","size":42,"mime_type":"image/png","width":1400,"height":900,"has_preview_image":true,"mini_preview":"/9j/AAEC"}"#
        let info = try mattermostSnakeCaseDecoder.decode(MattermostFileInfo.self, from: Data(json.utf8))

        #expect(info.miniPreview == Data([0xFF, 0xD8, 0xFF, 0x00, 0x01, 0x02]))
        #expect(info.width == 1400)
        #expect(info.hasPreviewImage == true)
    }

    @Test
    func fileInfoWithoutMiniPreviewDecodesNil() throws {
        let json = #"{"id":"f1","name":"doc.pdf","mini_preview":null}"#
        let info = try mattermostSnakeCaseDecoder.decode(MattermostFileInfo.self, from: Data(json.utf8))

        #expect(info.miniPreview == nil)
    }

    @Test
    func previewAndThumbnailHitTheirEndpoints() async throws {
        let log = MattermostRequestLog()
        let client = try await Self.makeClient { request in
            log.append(request.url?.path() ?? "")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            return try MattermostTestSupport.response(
                statusCode: 200,
                body: Data([1, 2, 3]),
                contentType: "image/jpeg",
                request: request
            )
        }

        #expect(try await client.filePreview(id: "file-id") == Data([1, 2, 3]))
        #expect(try await client.fileThumbnail(id: "file-id") == Data([1, 2, 3]))
        #expect(log.values == ["/api/v4/files/file-id/preview", "/api/v4/files/file-id/thumbnail"])
    }

    @Test
    func downloadReportsReceivedBytes() async throws {
        let body = Data(repeating: 7, count: 64 * 1024)
        let client = try await Self.makeClient { request in
            try MattermostTestSupport.response(
                statusCode: 200,
                body: body,
                contentType: "application/octet-stream",
                headerFields: ["Content-Length": "\(body.count)"],
                request: request
            )
        }
        let reports = ProgressLog()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MattermostFilePreviewTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }

        let url = try await client.downloadFile(id: "file-id", to: destination) { received, expected in
            reports.append(received, expected)
        }

        #expect(try Data(contentsOf: url) == body)
        let last = try #require(reports.values.last)
        #expect(last.received == Int64(body.count))
    }

    private static func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async throws -> MattermostClient {
        try MattermostClient(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            token: "token",
            urlSession: await MattermostTestSupport.urlSession(handler: handler)
        )
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(received: Int64, expected: Int64)] = []

    var values: [(received: Int64, expected: Int64)] { lock.withLock { storage } }

    func append(_ received: Int64, _ expected: Int64) {
        lock.withLock { storage.append((received, expected)) }
    }
}

@Suite(.serialized)
struct MattermostFileSearchTests {
    @Test
    func searchFilesPostsChannelTermsAndDecodesOrderedFiles() async throws {
        let client = try MattermostClient(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            token: "token",
            urlSession: await MattermostTestSupport.urlSession { request in
                #expect(request.url?.path() == "/api/v4/teams/team-id/files/search")
                #expect(request.httpMethod == "POST")
                let body = try JSONSerialization.jsonObject(with: MattermostTestSupport.bodyData(from: request)) as? [String: Any]
                #expect(body?["terms"] as? String == "channel:channel-id")
                #expect(body?["include_deleted_channels"] as? Bool == true)
                let json = #"{"order":["b","a"],"file_infos":{"a":{"id":"a","name":"a.png","channel_id":"channel-id","post_id":"p1"},"b":{"id":"b","name":"b.pdf"}},"next_file_info_id":"","prev_file_info_id":""}"#
                return try MattermostTestSupport.response(statusCode: 200, body: Data(json.utf8), request: request)
            }
        )

        let results = try await client.searchFiles(teamID: "team-id", terms: "channel:channel-id")

        #expect(results.orderedFiles.map(\.id) == ["b", "a"])
        #expect(results.fileInfos["a"]?.channelID == "channel-id")
        #expect(results.fileInfos["a"]?.postID == "p1")
    }

    @Test
    func emptySearchResultsDecodeFromNulls() throws {
        let json = #"{"order":null,"file_infos":null}"#
        let results = try mattermostSnakeCaseDecoder.decode(MattermostFileSearchResults.self, from: Data(json.utf8))
        #expect(results.orderedFiles.isEmpty)
    }
}

@Suite(.serialized)
struct MattermostFileClientTests {
    private static func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async throws -> MattermostClient {
        try MattermostClient(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            token: "token",
            urlSession: await MattermostTestSupport.urlSession(handler: handler)
        )
    }

    private static let uploadResponse = Data(#"{"file_infos":[{"id":"f1","name":"a.txt","size":3}],"client_ids":["c1"]}"#.utf8)

    @Test
    func uploadDataSendsChannelFileAndClientIDParts() async throws {
        let bodies = MattermostRequestLog()
        let client = try await Self.makeClient { request in
            #expect(request.url?.path() == "/api/v4/files")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            bodies.append(String(decoding: try MattermostTestSupport.bodyData(from: request), as: UTF8.self))
            return try MattermostTestSupport.response(statusCode: 201, body: Self.uploadResponse, request: request)
        }

        let response = try await client.uploadFile(
            channelID: "channel-id", filename: "a.txt", data: Data("abc".utf8),
            contentType: "text/plain", clientID: "c1"
        )

        #expect(response.fileInfos.map(\.id) == ["f1"])
        #expect(response.clientIDs == ["c1"])
        let body = try #require(bodies.values.first)
        #expect(body.contains(#"name="channel_id""#) && body.contains("channel-id"))
        #expect(body.contains(#"name="files"; filename="a.txt""#) && body.contains("abc"))
        #expect(body.contains(#"name="client_ids""#))
    }

    @Test
    func uploadDataOmitsEmptyClientID() async throws {
        let bodies = MattermostRequestLog()
        let client = try await Self.makeClient { request in
            bodies.append(String(decoding: try MattermostTestSupport.bodyData(from: request), as: UTF8.self))
            return try MattermostTestSupport.response(statusCode: 201, body: Self.uploadResponse, request: request)
        }

        _ = try await client.uploadFile(channelID: "c", filename: "a.txt", data: Data("x".utf8), clientID: "")

        #expect(bodies.values.first?.contains("client_ids") == false)
    }

    @Test
    func uploadStagedFilePostsToFilesEndpoint() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).txt")
        try Data("abc".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let client = try await Self.makeClient { request in
            #expect(request.url?.path() == "/api/v4/files")
            #expect(request.httpMethod == "POST")
            return try MattermostTestSupport.response(statusCode: 201, body: Self.uploadResponse, request: request)
        }

        let response = try await client.uploadFile(channelID: "c", filename: "a.txt", fileURL: source, clientID: "c1")

        #expect(response.fileInfos.first?.size == 3)
    }

    @Test
    func fileInfoEndpointsAndInMemoryDownload() async throws {
        let log = MattermostRequestLog()
        let client = try await Self.makeClient { request in
            let path = request.url?.path() ?? ""
            log.append(path)
            switch path {
            case "/api/v4/files/f1/info":
                return try MattermostTestSupport.response(statusCode: 200, body: Data(#"{"id":"f1","name":"a.png","create_at":1000,"delete_at":0}"#.utf8), request: request)
            case "/api/v4/posts/p1/files/info":
                return try MattermostTestSupport.response(statusCode: 200, body: Data(#"[{"id":"f1","name":"a.png"},{"id":"f2","name":"b.pdf"}]"#.utf8), request: request)
            default:
                return try MattermostTestSupport.response(statusCode: 200, body: Data([9, 8]), contentType: "application/octet-stream", request: request)
            }
        }

        let info = try await client.fileInfo(id: "f1")
        let infos = try await client.fileInfos(postID: "p1")
        let bytes = try await client.downloadFile(id: "f1")

        #expect(info.createdAt == Date(timeIntervalSince1970: 1))
        #expect(info.deletedAt == nil)
        #expect(infos.map(\.id) == ["f1", "f2"])
        #expect(bytes == Data([9, 8]))
        #expect(log.values == ["/api/v4/files/f1/info", "/api/v4/posts/p1/files/info", "/api/v4/files/f1"])
    }

    @Test
    func downloadFailsWithServerErrorAndLeavesNoFile() async throws {
        let client = try await Self.makeClient { request in
            try MattermostTestSupport.response(statusCode: 404, body: Data(#"{"message":"not found"}"#.utf8), request: request)
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")

        await #expect(throws: (any Error).self) {
            try await client.downloadFile(id: "gone", to: destination, progress: { _, _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func downloadRejectsResponsesAboveTheSizeLimit() async throws {
        let client = try await Self.makeClient { request in
            try MattermostTestSupport.response(statusCode: 200, body: Data(repeating: 1, count: 64), contentType: "application/octet-stream", request: request)
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID().uuidString)")

        await #expect(throws: MattermostError.fileTooLarge(limit: 16)) {
            try await client.downloadFile(id: "big", to: destination, maximumSize: 16, progress: { _, _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

@Suite
struct MattermostDownloadProgressDelegateTests {
    private func redirect(from source: String, to target: String) async throws -> URLRequest? {
        let delegate = MattermostDownloadProgressDelegate { _, _ in }
        let sourceURL = try #require(URL(string: source))
        var request = URLRequest(url: try #require(URL(string: target)))
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        request.setValue("MMAUTHTOKEN=x", forHTTPHeaderField: "Cookie")
        let response = try #require(HTTPURLResponse(url: sourceURL, statusCode: 302, httpVersion: nil, headerFields: nil))
        let task = URLSession.shared.dataTask(with: sourceURL)
        return await delegate.urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: request)
    }

    @Test
    func sameOriginRedirectKeepsCredentials() async throws {
        let request = try #require(try await redirect(from: "https://chat.example.com/api/v4/files/1", to: "https://chat.example.com/files/1"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test
    func crossOriginRedirectStripsCredentials() async throws {
        let request = try #require(try await redirect(from: "https://chat.example.com/api/v4/files/1", to: "https://s3.example.net/bucket/1"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test
    func httpsToHTTPRedirectIsRefused() async throws {
        #expect(try await redirect(from: "https://chat.example.com/api/v4/files/1", to: "http://chat.example.com/files/1") == nil)
    }
}
