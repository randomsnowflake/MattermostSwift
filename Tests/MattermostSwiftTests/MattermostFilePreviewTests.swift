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
