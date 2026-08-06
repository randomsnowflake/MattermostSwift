import Foundation
import Testing
@testable import MattermostSwift

@Suite("Synced drafts", .serialized)
struct MattermostDraftTests {
    @Test("client config feature-detects synced drafts despite key drift")
    func clientConfigDetectsSyncedDrafts() throws {
        let enabled = try JSONDecoder().decode(
            MattermostClientConfig.self,
            from: Data(#"{"allow_synced_drafts":"TRUE"}"#.utf8)
        )
        let absent = try JSONDecoder().decode(
            MattermostClientConfig.self,
            from: Data(#"{}"#.utf8)
        )

        #expect(enabled.allowSyncedDrafts == "TRUE")
        #expect(enabled.supportsSyncedDrafts)
        #expect(!absent.supportsSyncedDrafts)
    }

    @Test("draft endpoints preserve channel and thread identity")
    func draftRequests() async throws {
        let client = try await Self.makeClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v4/users/me/teams/team-id/drafts"):
                let body = Data(#"[{"create_at":10,"update_at":20,"delete_at":0,"user_id":"user-id","channel_id":"channel-id","root_id":"","message":"restored","type":"","props":{},"file_ids":[]}]"#.utf8)
                return try Self.response(statusCode: 200, body: body, request: request)
            case ("POST", "/api/v4/drafts"):
                let body = try JSONSerialization.jsonObject(with: try MattermostTestSupport.bodyData(from: request)) as? [String: Any]
                #expect(body?["channel_id"] as? String == "channel-id")
                #expect(body?["root_id"] as? String == "root-id")
                #expect(body?["message"] as? String == "typing")
                let response = Data(#"{"create_at":10,"update_at":30,"delete_at":0,"user_id":"user-id","channel_id":"channel-id","root_id":"root-id","message":"typing","type":"","props":{},"file_ids":[]}"#.utf8)
                return try Self.response(statusCode: 201, body: response, request: request)
            case ("DELETE", "/api/v4/users/me/channels/channel-id/drafts/root-id"):
                return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
            default:
                Issue.record("Unexpected draft request \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                return try Self.response(statusCode: 404, body: Data(#"{}"#.utf8), request: request)
            }
        }

        #expect(try await client.drafts(teamID: "team-id").map(\.message) == ["restored"])
        #expect(try await client.upsertDraft(MattermostDraftUpsertRequest(
            channelID: "channel-id",
            rootID: "root-id",
            message: "typing"
        ))?.rootID == "root-id")
        #expect(try await client.deleteDraft(channelID: "channel-id", rootID: "root-id").isOK)
    }

    @Test("empty draft upsert decodes the server deletion response")
    func emptyDraftUpsertReturnsNil() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v4/drafts")
            return try Self.response(statusCode: 201, body: Data("null".utf8), request: request)
        }

        let draft: MattermostDraft? = try await client.upsertDraft(MattermostDraftUpsertRequest(
            channelID: "channel-id",
            message: ""
        ))

        #expect(draft == nil)
    }

    @Test("draft live events decode their embedded payload")
    func draftLiveEventsDecode() throws {
        let draftJSON = #"{"create_at":10,"update_at":20,"delete_at":0,"user_id":"user-id","channel_id":"channel-id","root_id":"root-id","message":"remote","type":"","props":{},"file_ids":[]}"#
        let eventData = try JSONSerialization.data(withJSONObject: [
            "event": "draft_updated",
            "data": ["draft": draftJSON],
        ])
        let event = try JSONDecoder().decode(MattermostLiveEvent.self, from: eventData)

        #expect(try event.typedEvent() == .draftUpdated(try event.decodedDraft()))
        #expect(try event.decodedDraft()?.message == "remote")
        #expect(try event.decodedDraft()?.rootID == "root-id")
    }

    private static func makeClient(
        handler: @escaping MattermostTestSupport.URLHandler
    ) async throws -> MattermostClient {
        let session = await MattermostTestSupport.urlSession(handler: handler)
        return try MattermostClient(
            serverURL: URL(string: "https://mattermost.example.com")!,
            token: "token",
            urlSession: session
        )
    }

    private static func response(
        statusCode: Int,
        body: Data,
        request: URLRequest
    ) throws -> (HTTPURLResponse, Data) {
        try MattermostTestSupport.response(statusCode: statusCode, body: body, request: request)
    }
}
