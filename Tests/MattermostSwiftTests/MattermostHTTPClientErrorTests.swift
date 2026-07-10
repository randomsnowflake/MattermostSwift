import Foundation
import Testing
@testable import MattermostSwift

@Suite(.serialized)
struct MattermostHTTPClientErrorTests {
    @Test
    func clientMapsMattermostErrorResponseMessage() async throws {
        let client = try await Self.makeClient { request in
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
        let client = try await Self.makeClient { request in
            try Self.response(statusCode: 502, body: Data("Bad gateway".utf8), request: request)
        }

        await #expect(throws: MattermostError.httpStatus(code: 502, message: nil)) {
            _ = try await client.currentUser()
        }
    }

    @Test
    func clientRejectsEmptySuccessfulJSONResponse() async throws {
        let client = try await Self.makeClient { request in
            try Self.response(statusCode: 200, body: Data(), request: request)
        }

        await #expect(throws: MattermostError.emptyResponse) {
            _ = try await client.currentUser()
        }
    }

    @Test
    func clientWrapsURLSessionErrorsAsTransportFailure() async throws {
        let client = try await Self.makeClient { _ in
            throw URLError(.networkConnectionLost)
        }

        do {
            _ = try await client.currentUser()
            Issue.record("Expected a transport failure.")
        } catch MattermostError.transportFailure(let message) {
            #expect(message.isEmpty == false)
        }
    }

    @Test
    func clientRetriesTransientGETButNeverReplaysPOST() async throws {
        let getAttempts = MattermostRequestLog()
        let getClient = try await Self.makeClient { request in
            getAttempts.append(request.httpMethod ?? "")
            if getAttempts.values.count == 1 {
                throw URLError(.networkConnectionLost)
            }
            return try Self.response(
                statusCode: 200,
                body: Data(#"{"id":"user-id","username":"alice"}"#.utf8),
                request: request
            )
        }

        _ = try await getClient.currentUser()
        #expect(getAttempts.values == ["GET", "GET"])

        let postAttempts = MattermostRequestLog()
        let postClient = try await Self.makeClient { request in
            postAttempts.append(request.httpMethod ?? "")
            throw URLError(.networkConnectionLost)
        }

        await #expect(throws: MattermostError.self) {
            _ = try await postClient.sendPost(channelID: "channel-id", message: "must not replay")
        }
        #expect(postAttempts.values == ["POST"])
    }

    @Test
    func clientPreservesCancellationErrors() async throws {
        let client = try await Self.makeClient { _ in
            throw URLError(.cancelled)
        }

        do {
            _ = try await client.currentUser()
            Issue.record("Expected cancellation to be preserved.")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        } catch {
            Issue.record("Expected URLError.cancelled, got \(error).")
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
            urlSession: await Self.urlSession { request in
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
        let client = try await Self.makeClient { request in
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
        let client = try await Self.makeClient { request in
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
    func clientAttachesMobileDeviceToSession() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/sessions/device")
            #expect(request.httpMethod == "PUT")
            let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
            #expect(body?["device_id"] as? String == "apple:apns-token")
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        let status = try await client.attachMobileDevice(deviceID: "apple:apns-token")

        #expect(status.isOK)
    }

    @Test
    func clientDetachesMobileDeviceFromSession() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/sessions/device")
            #expect(request.httpMethod == "DELETE")
            let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
            #expect(body?["device_id"] as? String == "apple:apns-token")
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        let status = try await client.detachMobileDevice(deviceID: "apple:apns-token")

        #expect(status.isOK)
    }

    @Test
    func clientChecksMFARequirementBeforeLogin() async throws {
        let session = await Self.urlSession { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/mfa")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
            #expect(body?["login_id"] as? String == "person@example.com")
            return try Self.response(statusCode: 200, body: Data(#"{"mfa_required":true}"#.utf8), request: request)
        }

        let isRequired = try await MattermostClient.checkMFARequired(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            loginID: "person@example.com",
            urlSession: session
        )

        #expect(isRequired)
    }

    @Test
    func clientManagesMFAAndPasswordSecurityEndpoints() async throws {
        let requested = MattermostRequestLog()
        let client = try await Self.makeClient { request in
            requested.append("\(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
            if request.url?.path.contains("/password") == true {
                let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
                #expect(body?["current_password"] as? String == "old")
                #expect(body?["new_password"] as? String == "new")
            }
            if request.url?.path.contains("/mfa") == true, request.httpMethod == "PUT" {
                let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
                #expect(body?["activate"] as? Bool == true)
                #expect(body?["code"] as? String == "123456")
            }
            if request.url?.path.contains("/mfa/generate") == true {
                return try Self.response(
                    statusCode: 200,
                    body: Data(#"{"secret":"SECRET","qr_code":"base64-qr"}"#.utf8),
                    request: request
                )
            }
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        let secret = try await client.generateMFA(userID: "user-id")
        let mfaStatus = try await client.activateMFA(userID: "user-id", code: "123456", activate: true)
        let passwordStatus = try await client.changePassword(userID: "user-id", currentPassword: "old", newPassword: "new")

        #expect(secret.secret == "SECRET")
        #expect(secret.qrCode == "base64-qr")
        #expect(mfaStatus.isOK)
        #expect(passwordStatus.isOK)
        #expect(requested.values == [
            "POST https://mattermost.example.com/api/v4/users/user-id/mfa/generate",
            "PUT https://mattermost.example.com/api/v4/users/user-id/mfa",
            "PUT https://mattermost.example.com/api/v4/users/user-id/password",
        ])
    }

    @Test
    func clientManagesUserSessions() async throws {
        let requested = MattermostRequestLog()
        let client = try await Self.makeClient { request in
            requested.append("\(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
            if request.url?.path.hasSuffix("/sessions") == true {
                return try Self.response(
                    statusCode: 200,
                    body: Data(#"[{"id":"session-id","user_id":"user-id","device_id":"ios","create_at":1000,"last_activity_at":2000,"props":{"platform":"ios"},"token":"session-token"}]"#.utf8),
                    request: request
                )
            }
            if request.url?.path.hasSuffix("/sessions/revoke") == true {
                let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
                #expect(body?["session_id"] as? String == "session-id")
            } else {
                #expect(request.httpBody == nil)
            }
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        let sessions = try await client.sessions(userID: "user-id")
        let single = try await client.revokeSession(userID: "user-id", sessionID: "session-id")
        let all = try await client.revokeAllSessions(userID: "user-id")

        #expect(sessions.map(\.id) == ["session-id"])
        #expect(sessions.first?.props?["platform"] == .string("ios"))
        #expect(single.isOK)
        #expect(all.isOK)
        #expect(requested.values == [
            "GET https://mattermost.example.com/api/v4/users/user-id/sessions",
            "POST https://mattermost.example.com/api/v4/users/user-id/sessions/revoke",
            "POST https://mattermost.example.com/api/v4/users/user-id/sessions/revoke/all",
        ])
    }

    @Test
    func clientManagesChannelLifecycleEndpoints() async throws {
        let requested = MattermostRequestLog()
        let channelJSON = Data(#"{"id":"channel-id","team_id":"team-id","name":"town","display_name":"Town","type":"P","delete_at":0}"#.utf8)
        let client = try await Self.makeClient { request in
            requested.append("\(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
            if request.url?.path.hasSuffix("/privacy") == true {
                let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
                #expect(body?["privacy"] as? String == "P")
            }
            if request.url?.path.hasSuffix("/convert_to_channel") == true {
                let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
                #expect(body?["channel_id"] as? String == "gm-id")
                #expect(body?["team_id"] as? String == "team-id")
                #expect(body?["name"] as? String == "project-room")
                #expect(body?["display_name"] as? String == "Project Room")
            }
            return try Self.response(statusCode: 200, body: channelJSON, request: request)
        }

        let restored = try await client.restoreChannel(id: "channel-id")
        let privateChannel = try await client.setChannelPrivacy(id: "channel-id", type: "P")
        let converted = try await client.convertGroupToChannel(
            id: "gm-id",
            teamID: "team-id",
            name: "project-room",
            displayName: "Project Room"
        )

        #expect(restored.id == "channel-id")
        #expect(privateChannel.type == "P")
        #expect(converted.id == "channel-id")
        #expect(requested.values == [
            "POST https://mattermost.example.com/api/v4/channels/channel-id/restore",
            "PUT https://mattermost.example.com/api/v4/channels/channel-id/privacy",
            "POST https://mattermost.example.com/api/v4/channels/gm-id/convert_to_channel",
        ])
    }

    @Test
    func clientPinsAndUnpinsPostWithoutBody() async throws {
        let requested = MattermostRequestLog()
        let client = try await Self.makeClient { request in
            requested.append("\(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
            #expect(request.httpBody == nil)
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        _ = try await client.pinPost(id: "post-id")
        _ = try await client.unpinPost(id: "post-id")

        #expect(requested.values == [
            "POST https://mattermost.example.com/api/v4/posts/post-id/pin",
            "POST https://mattermost.example.com/api/v4/posts/post-id/unpin",
        ])
    }

    @Test
    func clientSetsThreadFollowingWithExpectedMethod() async throws {
        let requested = MattermostRequestLog()
        let client = try await Self.makeClient { request in
            requested.append("\(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
            #expect(request.httpBody == nil)
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        _ = try await client.setThreadFollowing(teamID: "team-id", threadID: "thread-id", following: true)
        _ = try await client.setThreadFollowing(teamID: "team-id", threadID: "thread-id", following: false)

        #expect(requested.values == [
            "PUT https://mattermost.example.com/api/v4/users/me/teams/team-id/threads/thread-id/following",
            "DELETE https://mattermost.example.com/api/v4/users/me/teams/team-id/threads/thread-id/following",
        ])
    }

    @Test
    func clientSetsAndClearsCustomStatus() async throws {
        let requested = MattermostRequestLog()
        let client = try await Self.makeClient { request in
            requested.append("\(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
            if request.httpMethod == "PUT" {
                let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
                #expect(body?["emoji"] as? String == "coffee")
                #expect(body?["text"] as? String == "Deep work")
                #expect(body?["duration"] as? String == "one_hour")
            } else {
                #expect(request.httpBody == nil)
            }
            return try Self.response(statusCode: 200, body: Data(#"{"status":"OK"}"#.utf8), request: request)
        }

        _ = try await client.setCustomStatus(MattermostCustomStatus(emoji: "coffee", text: "Deep work", duration: "one_hour"))
        _ = try await client.clearCustomStatus()

        #expect(requested.values == [
            "PUT https://mattermost.example.com/api/v4/users/me/status/custom",
            "DELETE https://mattermost.example.com/api/v4/users/me/status/custom",
        ])
    }

    @Test
    func clientClampsChannelUsersPagination() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users?in_channel=channel-id&page=0&per_page=1")
            return try Self.response(statusCode: 200, body: Data("[]".utf8), request: request)
        }

        let users = try await client.users(channelID: "channel-id", page: -2, perPage: 0)

        #expect(users.isEmpty)
    }

    @Test
    func clientClampsChannelMembersPagination() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/members?page=0&per_page=1")
            return try Self.response(statusCode: 200, body: Data("[]".utf8), request: request)
        }

        let members = try await client.channelMembers(channelID: "channel-id", page: -2, perPage: 0)

        #expect(members.isEmpty)
    }

    @Test
    func clientClampsPublicChannelPagination() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/team-id/channels?page=0&per_page=1&include_deleted=false")
            return try Self.response(statusCode: 200, body: Data("[]".utf8), request: request)
        }

        let channels = try await client.publicChannels(teamID: "team-id", page: -2, perPage: 0)

        #expect(channels.isEmpty)
    }

    @Test
    func clientClampsTeamMemberPagination() async throws {
        let client = try await Self.makeClient { request in
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
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/posts?page=0&per_page=1")
            return try Self.response(statusCode: 200, body: Data(#"{"order":[],"posts":{}}"#.utf8), request: request)
        }

        let posts = try await client.posts(channelID: "channel-id", page: -1, perPage: -20)

        #expect(posts.order.isEmpty)
        #expect(posts.posts.isEmpty)
    }

    @Test
    func clientClampsCustomEmojiPagination() async throws {
        let client = try await Self.makeClient { request in
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

        let client = try await Self.makeClient { request in
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
            urlSession: await Self.urlSession { request in
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
            urlSession: await Self.urlSession { request in
                #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/login")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
                #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
                #expect(!request.httpShouldHandleCookies)
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
            urlSession: await Self.urlSession { request in
                #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
                #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
                #expect(!request.httpShouldHandleCookies)
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
    func loginThrowsMissingAuthenticationTokenWhenHeaderAndCookieAreAbsent() async throws {
        await #expect(throws: MattermostError.missingAuthenticationToken) {
            _ = try await MattermostClient.login(
                serverURL: try #require(URL(string: "https://mattermost.example.com")),
                loginID: "user@example.com",
                password: "password",
                urlSession: await Self.urlSession { request in
                    let body = Data(#"{"id":"user-id","username":"alice"}"#.utf8)
                    return try Self.response(statusCode: 200, body: body, request: request)
                }
            )
        }
    }

    @Test
    func loginFindsMattermostAuthCookieAmongBrowserSessionCookies() async throws {
        let session = try await MattermostClient.login(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            loginID: "user@example.com",
            password: "password",
            urlSession: await Self.urlSession { request in
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
