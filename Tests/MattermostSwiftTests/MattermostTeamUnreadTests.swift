import Foundation
import Testing
import MattermostSwift
@testable import MattermostSwiftCLI

@Suite(.serialized)
struct MattermostTeamUnreadTests {
    @Test
    func teamsUnreadBuildsQueryAndDecodesWirePayload() async throws {
        let client = try await Self.makeClient(serverURL: "https://mattermost.example.com") { request in
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.path == "/api/v4/users/me/teams/unread")
            #expect(request.httpMethod == "GET")
            #expect(components.queryItems?.contains(URLQueryItem(name: "exclude_team", value: "team-a")) == true)
            #expect(components.queryItems?.contains(URLQueryItem(name: "include_collapsed_threads", value: "true")) == true)
            let body = Data(#"""
            [
              {"team_id":"team-b","msg_count":3,"mention_count":1,"msg_count_root":2,"mention_count_root":1,
               "thread_count":4,"thread_mention_count":2,"thread_urgent_mention_count":0},
              {"team_id":"","msg_count":5,"mention_count":5}
            ]
            """#.utf8)
            return try MattermostTestSupport.response(statusCode: 200, body: body, request: request)
        }

        let unreads = try await client.teamsUnread(excludeTeamID: "team-a")

        #expect(unreads == [
            MattermostTeamUnread(
                teamID: "team-b", msgCount: 3, mentionCount: 1, msgCountRoot: 2, mentionCountRoot: 1,
                threadCount: 4, threadMentionCount: 2, threadUrgentMentionCount: 0
            ),
            // The empty-team DM aggregate stays in the raw result.
            MattermostTeamUnread(teamID: "", msgCount: 5, mentionCount: 5),
        ])
        #expect(unreads.first?.id == "team-b")
    }

    @Test
    func teamsUnreadOmitsExcludeAndHonorsFalseCRTOnSubpathServer() async throws {
        let client = try await Self.makeClient(serverURL: "https://example.com/mattermost") { request in
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.path == "/mattermost/api/v4/users/user-1/teams/unread")
            #expect(components.queryItems == [URLQueryItem(name: "include_collapsed_threads", value: "false")])
            return try MattermostTestSupport.response(statusCode: 200, body: Data("[]".utf8), request: request)
        }

        let unreads = try await client.teamsUnread(userID: "user-1", includeCollapsedThreads: false)

        #expect(unreads.isEmpty)
    }

    @Test
    func teamsUnreadDecodesNullOptionalsAndRejectsMissingRequiredFields() async throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let nulls = Data(#"[{"team_id":"t","msg_count":0,"mention_count":0,"msg_count_root":null,"thread_count":null}]"#.utf8)
        let decoded = try decoder.decode([MattermostTeamUnread].self, from: nulls)
        #expect(decoded == [MattermostTeamUnread(teamID: "t", msgCount: 0, mentionCount: 0)])

        let malformed = Data(#"[{"team_id":"t","mention_count":0}]"#.utf8)
        #expect(throws: DecodingError.self) {
            try decoder.decode([MattermostTeamUnread].self, from: malformed)
        }
    }

    @Test
    func teamsUnreadPropagatesHTTPErrors() async throws {
        let client = try await Self.makeClient(serverURL: "https://mattermost.example.com") { request in
            let body = Data(#"{"id":"api.context.permissions.app_error","message":"denied","status_code":403}"#.utf8)
            return try MattermostTestSupport.response(statusCode: 403, body: body, request: request)
        }

        await #expect {
            _ = try await client.teamsUnread()
        } throws: { error in
            guard case .httpStatus(let code, _, _) = error as? MattermostError else { return false }
            return code == 403
        }
    }

    @Test
    func clientConfigDecodesDiagnosticIDWhenPresentAndAbsent() throws {
        let present = try JSONDecoder().decode(
            MattermostClientConfig.self,
            from: Data(#"{"DiagnosticId":"86wmtxrwp3dg3rceddq7uhfghy","SiteName":"A"}"#.utf8)
        )
        let absent = try JSONDecoder().decode(MattermostClientConfig.self, from: Data(#"{"SiteName":"A"}"#.utf8))

        #expect(present.diagnosticID == "86wmtxrwp3dg3rceddq7uhfghy")
        #expect(absent.diagnosticID == nil)
    }

    @Test
    func cliParsesAndEncodesTeamUnreads() throws {
        #expect(try MattermostSwiftCLI.parseInvocation(["list-teams-unread"]).command == .listTeamsUnread(excludeTeamID: nil))
        #expect(
            try MattermostSwiftCLI.parseInvocation(["--json", "list-teams-unread", "--exclude", "team-a"])
                == ParsedCLIInvocation(command: .listTeamsUnread(excludeTeamID: "team-a"), json: true)
        )

        let data = try MattermostSwiftCLI.encodedJSON([
            MattermostTeamUnread(teamID: "team-b", msgCount: 3, mentionCount: 1, msgCountRoot: 2, threadCount: 4),
        ])
        let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let object = try #require(rows?.first)
        #expect(object["teamId"] as? String == "team-b")
        #expect(object["msgCount"] as? Int == 3)
        #expect(object["mentionCount"] as? Int == 1)
        #expect(object["msgCountRoot"] as? Int == 2)
        #expect(object["threadCount"] as? Int == 4)
    }

    @Test
    func serverInfoJSONExposesDiagnosticID() throws {
        let config = try JSONDecoder().decode(MattermostClientConfig.self, from: Data(#"{"DiagnosticId":"diag"}"#.utf8))
        let encoded = try MattermostSwiftCLI.encodedJSON(config)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["diagnosticID"] as? String == "diag")
    }

    private static func makeClient(
        serverURL: String,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async throws -> MattermostClient {
        try MattermostClient(
            serverURL: try #require(URL(string: serverURL)),
            token: "token",
            urlSession: await MattermostTestSupport.urlSession(handler: handler)
        )
    }
}
