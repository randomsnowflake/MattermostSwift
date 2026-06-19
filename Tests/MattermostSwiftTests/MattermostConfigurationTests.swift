import Foundation
import Testing
@testable import MattermostSwift

@Test
func configurationNormalizesServerURL() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com/")),
        authentication: .bearerToken("token")
    )

    #expect(configuration.serverURL.absoluteString == "https://mattermost.example.com")
    #expect(configuration.apiBaseURL.absoluteString == "https://mattermost.example.com/api/v4/")
    #expect(configuration.webSocketURL.absoluteString == "wss://mattermost.example.com/api/v4/websocket")
}

@Test
func configurationAcceptsAPIURLAndUsesServerRoot() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com/api/v4/posts?ignored=true")),
        authentication: .bearerToken("token")
    )

    #expect(configuration.serverURL.absoluteString == "https://mattermost.example.com")
    #expect(configuration.apiBaseURL.absoluteString == "https://mattermost.example.com/api/v4/")
    #expect(configuration.webSocketURL.absoluteString == "wss://mattermost.example.com/api/v4/websocket")
}

@Test
func configurationBuildsInsecureWebSocketURLForHTTPServer() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "http://localhost:8065")),
        authentication: .bearerToken("token")
    )

    #expect(configuration.webSocketURL.absoluteString == "ws://localhost:8065/api/v4/websocket")
}

@Test
func configurationRejectsRemoteInsecureHTTP() throws {
    #expect(throws: MattermostError.insecureServerURL("http://mattermost.example.com")) {
        _ = try MattermostConfiguration(
            serverURL: #require(URL(string: "http://mattermost.example.com")),
            authentication: .bearerToken("token")
        )
    }
}

@Test
func configurationAllowsRemoteInsecureHTTPWhenOptedIn() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "http://mattermost.example.com")),
        authentication: .bearerToken("token"),
        allowInsecureHTTP: true
    )

    #expect(configuration.serverURL.absoluteString == "http://mattermost.example.com")
    #expect(configuration.webSocketURL.absoluteString == "ws://mattermost.example.com/api/v4/websocket")
}

@Test
func configurationRejectsNonHTTPScheme() throws {
    #expect(throws: MattermostError.invalidServerURL("ftp://mattermost.example.com")) {
        _ = try MattermostConfiguration(
            serverURL: #require(URL(string: "ftp://mattermost.example.com")),
            authentication: .none
        )
    }
}

@Test
func environmentClientRequiresURL() throws {
    #expect(throws: MattermostError.missingEnvironmentVariable("MATTERMOST_URL")) {
        _ = try MattermostClient.liveFromEnvironment([:])
    }
}

@Test
func environmentClientAcceptsAuthTokenAlias() throws {
    let client = try MattermostClient.liveFromEnvironment([
        "MATTERMOST_URL": "https://mattermost.example.com",
        "MATTERMOST_AUTH_TOKEN": "token",
    ])

    _ = client
}

@Test
func loginFromEnvironmentRequiresUsername() async {
    await #expect(throws: MattermostError.missingEnvironmentVariable("MATTERMOST_USERNAME")) {
        try await MattermostClient.loginFromEnvironment([
            "MATTERMOST_URL": "https://mattermost.example.com",
        ])
    }
}

@Test
func loginFromEnvironmentRequiresPassword() async {
    await #expect(throws: MattermostError.missingEnvironmentVariable("MATTERMOST_PASSWORD")) {
        try await MattermostClient.loginFromEnvironment([
            "MATTERMOST_URL": "https://mattermost.example.com",
            "MATTERMOST_USERNAME": "user@example.com",
        ])
    }
}

@Test
func httpClientBuildsExpectedCurrentUserRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com/api/v4/posts")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(endpoint: "/users/me", method: "GET")

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
}

@Test
func httpClientBuildsUserProfileImageRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let profileRequest = try httpClient.makeRequest(endpoint: "/users/me/image", method: "GET")
    let defaultProfileRequest = try httpClient.makeRequest(endpoint: "/users/user-id/image/default", method: "GET")

    #expect(profileRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/image")
    #expect(profileRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(profileRequest.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
    #expect(defaultProfileRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/users/user-id/image/default")
    #expect(defaultProfileRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(defaultProfileRequest.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
}

@Test
func httpClientBuildsUserPatchRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let patch = MattermostUserPatch(
        username: "alice",
        email: "alice@example.com",
        firstName: "Alice",
        lastName: "Ng",
        nickname: "",
        position: "Engineer"
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/user-id/patch",
        method: "PUT",
        body: patch
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/user-id/patch")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(body?["username"] as? String == "alice")
    #expect(body?["email"] as? String == "alice@example.com")
    #expect(body?["first_name"] as? String == "Alice")
    #expect(body?["last_name"] as? String == "Ng")
    #expect(body?["nickname"] as? String == "")
    #expect(body?["position"] as? String == "Engineer")
}

@Test
func httpClientBuildsUnauthenticatedLoginRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .none
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let login = MattermostLoginRequest(
        loginId: "user@example.com",
        password: "password",
        token: "123456",
        deviceId: "device-id",
        ldapOnly: false
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/login",
        method: "POST",
        body: login
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/login")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
    #expect(body?["login_id"] as? String == "user@example.com")
    #expect(body?["password"] as? String == "password")
    #expect(body?["token"] as? String == "123456")
    #expect(body?["device_id"] as? String == "device-id")
    #expect(body?["ldap_only"] as? Bool == false)
}

@Test
func liveEventStreamBuildsBrowserUserAgentWebSocketRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let stream = MattermostLiveEventStream(configuration: configuration)

    let request = stream.makeWebSocketRequest()

    #expect(request.url?.absoluteString == "wss://mattermost.example.com/api/v4/websocket")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
}

@Test
func liveEventStreamBuildsUnauthenticatedWebSocketRequestWithBrowserUserAgent() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "http://localhost:8065")),
        authentication: .none
    )
    let stream = MattermostLiveEventStream(configuration: configuration)

    let request = stream.makeWebSocketRequest()

    #expect(request.url?.absoluteString == "ws://localhost:8065/api/v4/websocket")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "User-Agent") == MattermostUserAgent.browser)
}

@Test
func httpClientBuildsQueryRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(
        endpoint: "/system/ping",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "get_server_status", value: "true"),
            URLQueryItem(name: "use_rest_semantics", value: "true"),
        ]
    )

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/system/ping?get_server_status=true&use_rest_semantics=true")
}

@Test
func httpClientBuildsTeamRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let byID = try httpClient.makeRequest(endpoint: "/teams/team-id", method: "GET")
    let byName = try httpClient.makeRequest(endpoint: "/teams/name/town-square", method: "GET")
    let joined = try httpClient.makeRequest(endpoint: "/users/me/teams", method: "GET")

    #expect(byID.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/team-id")
    #expect(byName.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/name/town-square")
    #expect(joined.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/teams")
}

@Test
func httpClientBuildsTeamMemberRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(
        endpoint: "/teams/team-id/members",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "page", value: "2"),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "sort", value: "Username"),
            URLQueryItem(name: "exclude_deleted_users", value: "true"),
        ]
    )

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/team-id/members?page=2&per_page=20&sort=Username&exclude_deleted_users=true")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
}

@Test
func httpClientBuildsChannelUsersRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(
        endpoint: "/users",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "in_channel", value: "channel-id"),
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "per_page", value: "20"),
        ]
    )

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users?in_channel=channel-id&page=0&per_page=20")
}

@Test
func httpClientBuildsUsersByIDsAndUsernamesRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let idsRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/ids",
        method: "POST",
        body: ["user-a", "user-b"]
    )
    let idsBody = try JSONSerialization.jsonObject(with: try #require(idsRequest.httpBody)) as? [String]
    let usernamesRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/usernames",
        method: "POST",
        body: ["alice", "bob"]
    )
    let usernamesBody = try JSONSerialization.jsonObject(
        with: try #require(usernamesRequest.httpBody)
    ) as? [String]

    #expect(idsRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/users/ids")
    #expect(idsBody == ["user-a", "user-b"])
    #expect(usernamesRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/users/usernames")
    #expect(usernamesBody == ["alice", "bob"])
}

@Test
func httpClientBuildsUserSearchRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let search = MattermostUserSearchRequest(
        term: "alice",
        teamId: "team-id",
        inChannelId: "channel-id",
        allowInactive: true,
        withoutTeam: false,
        limit: 0
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/search",
        method: "POST",
        body: search
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/search")
    #expect(body?["term"] as? String == "alice")
    #expect(body?["team_id"] as? String == "team-id")
    #expect(body?["in_channel_id"] as? String == "channel-id")
    #expect(body?["allow_inactive"] as? Bool == true)
    #expect(body?["without_team"] as? Bool == false)
    #expect(body?["limit"] as? Int == 1)
}

@Test
func httpClientBuildsUserAutocompleteAndKnownUsersRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let autocomplete = try httpClient.makeRequest(
        endpoint: "/users/autocomplete",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "name", value: "alice"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "team_id", value: "team-id"),
            URLQueryItem(name: "channel_id", value: "channel-id"),
        ]
    )
    let known = try httpClient.makeRequest(endpoint: "/users/known", method: "GET")

    #expect(autocomplete.url?.absoluteString == "https://mattermost.example.com/api/v4/users/autocomplete?name=alice&limit=20&team_id=team-id&channel_id=channel-id")
    #expect(known.url?.absoluteString == "https://mattermost.example.com/api/v4/users/known")
}

@Test
func httpClientBuildsChannelUnreadRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(
        endpoint: "/users/me/channels/channel-id/unread",
        method: "GET"
    )

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/channels/channel-id/unread")
}

@Test
func httpClientBuildsChannelStatsRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let statsRequest = try httpClient.makeRequest(
        endpoint: "/channels/channel-id/stats",
        method: "GET"
    )
    let timezonesRequest = try httpClient.makeRequest(
        endpoint: "/channels/channel-id/timezones",
        method: "GET"
    )
    let memberCountsRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/stats/member_count",
        method: "POST",
        body: ["channel-a", "channel-b"]
    )
    let memberCountsBody = try JSONSerialization.jsonObject(
        with: try #require(memberCountsRequest.httpBody)
    ) as? [String]

    #expect(statsRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/stats")
    #expect(statsRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(timezonesRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/timezones")
    #expect(timezonesRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(memberCountsRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/stats/member_count")
    #expect(memberCountsBody == ["channel-a", "channel-b"])
}

@Test
func httpClientBuildsPublicChannelListRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(
        endpoint: "/teams/team-id/channels",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "page", value: "2"),
            URLQueryItem(name: "per_page", value: "20"),
        ]
    )

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/team-id/channels?page=2&per_page=20")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
}

@Test
func httpClientBuildsChannelByNameRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let byTeamID = try httpClient.makeRequest(
        endpoint: "/teams/team-id/channels/name/town-square",
        method: "GET",
        queryItems: [URLQueryItem(name: "include_deleted", value: "false")]
    )
    let byTeamName = try httpClient.makeRequest(
        endpoint: "/teams/name/team-name/channels/name/town-square",
        method: "GET",
        queryItems: [URLQueryItem(name: "include_deleted", value: "true")]
    )

    #expect(byTeamID.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/team-id/channels/name/town-square?include_deleted=false")
    #expect(byTeamID.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(byTeamName.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/name/team-name/channels/name/town-square?include_deleted=true")
    #expect(byTeamName.value(forHTTPHeaderField: "Authorization") == "Bearer token")
}

@Test
func httpClientBuildsChannelMembershipManagementRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let singleAddRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/channel-id/members",
        method: "POST",
        body: MattermostAddChannelMembersRequest(userId: "user-a")
    )
    let singleAddBody = try JSONSerialization.jsonObject(
        with: try #require(singleAddRequest.httpBody)
    ) as? [String: Any]

    let bulkAddRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/channel-id/members",
        method: "POST",
        body: MattermostAddChannelMembersRequest(userIds: ["user-a", "user-b"], postRootId: "root-post-id")
    )
    let bulkAddBody = try JSONSerialization.jsonObject(
        with: try #require(bulkAddRequest.httpBody)
    ) as? [String: Any]

    let byIDsRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/channel-id/members/ids",
        method: "POST",
        body: ["user-a", "user-b"]
    )
    let byIDsBody = try JSONSerialization.jsonObject(
        with: try #require(byIDsRequest.httpBody)
    ) as? [String]

    let removeRequest = try httpClient.makeRequest(
        endpoint: "/channels/channel-id/members/user-a",
        method: "DELETE"
    )
    let listRequest = try httpClient.makeRequest(
        endpoint: "/channels/channel-id/members",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "page", value: "2"),
            URLQueryItem(name: "per_page", value: "20"),
        ]
    )

    #expect(singleAddRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/members")
    #expect(singleAddRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(singleAddBody?["user_id"] as? String == "user-a")
    #expect(singleAddBody?["user_ids"] == nil)
    #expect(bulkAddBody?["user_ids"] as? [String] == ["user-a", "user-b"])
    #expect(bulkAddBody?["post_root_id"] as? String == "root-post-id")
    #expect(byIDsRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/members/ids")
    #expect(byIDsBody == ["user-a", "user-b"])
    #expect(removeRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/members/user-a")
    #expect(removeRequest.httpMethod == "DELETE")
    #expect(listRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/members?page=2&per_page=20")
    #expect(listRequest.httpMethod == "GET")
}

@Test
func httpClientBuildsCreateChannelRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let channel = MattermostCreateChannelRequest(
        teamId: "team-id",
        name: "mmswift-test",
        displayName: "MattermostSwift Test",
        purpose: nil,
        header: nil,
        type: "O"
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels",
        method: "POST",
        body: channel
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels")
    #expect(body?["team_id"] as? String == "team-id")
    #expect(body?["name"] as? String == "mmswift-test")
    #expect(body?["display_name"] as? String == "MattermostSwift Test")
    #expect(body?["type"] as? String == "O")
}

@Test
func httpClientBuildsDirectAndGroupChannelRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let directRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/direct",
        method: "POST",
        body: ["user-a", "user-b"]
    )
    let directBody = try JSONSerialization.jsonObject(
        with: try #require(directRequest.httpBody)
    ) as? [String]

    let groupRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/group",
        method: "POST",
        body: ["user-a", "user-b", "user-c"]
    )
    let groupBody = try JSONSerialization.jsonObject(
        with: try #require(groupRequest.httpBody)
    ) as? [String]

    let searchRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/group/search",
        method: "POST",
        body: MattermostTeamChannelSearchRequest(term: "alice")
    )
    let searchBody = try JSONSerialization.jsonObject(
        with: try #require(searchRequest.httpBody)
    ) as? [String: Any]

    #expect(directRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/direct")
    #expect(directBody == ["user-a", "user-b"])
    #expect(groupRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/group")
    #expect(groupBody == ["user-a", "user-b", "user-c"])
    #expect(searchRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/group/search")
    #expect(searchBody?["term"] as? String == "alice")
}

@Test
func httpClientBuildsViewChannelRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let view = MattermostViewChannelRequest(channelId: "channel-id", prevChannelId: "previous-id")

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/members/me/view",
        method: "POST",
        body: view
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/members/me/view")
    #expect(body?["channel_id"] as? String == "channel-id")
    #expect(body?["prev_channel_id"] as? String == "previous-id")
}

@Test
func httpClientBuildsTypingRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let typing = MattermostTypingRequest(channelId: "channel-id", parentId: "root-id")

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/me/typing",
        method: "POST",
        body: typing
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/typing")
    #expect(body?["channel_id"] as? String == "channel-id")
    #expect(body?["parent_id"] as? String == "root-id")
}

@Test
func httpClientBuildsPreferenceRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let all = try httpClient.makeRequest(endpoint: "/users/me/preferences", method: "GET")
    let category = try httpClient.makeRequest(endpoint: "/users/me/preferences/sidebar_settings", method: "GET")
    let named = try httpClient.makeRequest(
        endpoint: "/users/me/preferences/sidebar_settings/name/favorite",
        method: "GET"
    )

    #expect(all.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/preferences")
    #expect(category.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/preferences/sidebar_settings")
    #expect(named.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/preferences/sidebar_settings/name/favorite")
}

@Test
func httpClientBuildsPreferenceSaveAndDeleteRequestsWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let preferences = [
        MattermostPreference(userId: "user-id", category: "mmswift", name: "flag", value: "true"),
    ]

    let saveRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/user-id/preferences",
        method: "PUT",
        body: preferences
    )
    let deleteRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/user-id/preferences/delete",
        method: "POST",
        body: preferences
    )
    let saveBody = try JSONSerialization.jsonObject(with: try #require(saveRequest.httpBody)) as? [[String: Any]]
    let deleteBody = try JSONSerialization.jsonObject(with: try #require(deleteRequest.httpBody)) as? [[String: Any]]

    #expect(saveRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/users/user-id/preferences")
    #expect(saveRequest.httpMethod == "PUT")
    #expect(saveBody?.first?["user_id"] as? String == "user-id")
    #expect(saveBody?.first?["category"] as? String == "mmswift")
    #expect(saveBody?.first?["name"] as? String == "flag")
    #expect(saveBody?.first?["value"] as? String == "true")
    #expect(deleteRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/users/user-id/preferences/delete")
    #expect(deleteRequest.httpMethod == "POST")
    #expect(deleteBody?.first?["user_id"] as? String == "user-id")
    #expect(deleteBody?.first?["category"] as? String == "mmswift")
    #expect(deleteBody?.first?["name"] as? String == "flag")
    #expect(deleteBody?.first?["value"] as? String == "true")
}


@Test
func httpClientBuildsSidebarCategoryCreateRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let category = MattermostSidebarCategoryRequest(
        id: nil,
        userId: "user-id",
        teamId: "team-id",
        displayName: "MattermostSwift Test",
        type: "custom",
        channelIds: ["channel-id"],
        sorting: "manual"
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/me/teams/team-id/channels/categories",
        method: "POST",
        body: category
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/teams/team-id/channels/categories")
    #expect(body?["user_id"] as? String == "user-id")
    #expect(body?["team_id"] as? String == "team-id")
    #expect(body?["display_name"] as? String == "MattermostSwift Test")
    #expect(body?["type"] as? String == "custom")
    #expect(body?["channel_ids"] as? [String] == ["channel-id"])
    #expect(body?["sorting"] as? String == "manual")
}

@Test
func httpClientBuildsSidebarCategoryOrderRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/me/teams/team-id/channels/categories/order",
        method: "PUT",
        body: ["a", "b"]
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/teams/team-id/channels/categories/order")
    #expect(body == ["a", "b"])
}

@Test
func httpClientBuildsPostSinceRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(
        endpoint: "/channels/channel-id/posts",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "since", value: "1780000000000"),
        ]
    )

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/posts?since=1780000000000")
}

@Test
func httpClientBuildsPinnedPostsRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(
        endpoint: "/channels/channel-id/pinned",
        method: "GET"
    )

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/channel-id/pinned")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
}

@Test
func httpClientBuildsPostRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let request = MattermostCreatePostRequest(
        channelId: "channel-id",
        message: "hello",
        rootId: nil,
        fileIds: [],
        props: [:]
    )

    let urlRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/posts",
        method: "POST",
        body: request
    )

    #expect(urlRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/posts")
    #expect(urlRequest.httpMethod == "POST")
    #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let body = try JSONSerialization.jsonObject(with: try #require(urlRequest.httpBody)) as? [String: Any]
    #expect(body?["channel_id"] as? String == "channel-id")
    #expect(body?["message"] as? String == "hello")
    #expect(body?["root_id"] == nil)
    #expect(body?["file_ids"] == nil)
    #expect(body?["props"] == nil)
}

@Test
func httpClientBuildsPostRequestWithPropsJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let request = MattermostCreatePostRequest(
        channelId: "channel-id",
        message: "hello",
        rootId: "root-id",
        fileIds: ["file-id"],
        props: [
            "mmswift": .object([
                "ok": .bool(true),
                "count": .number(2),
                "note": .string("roundtrip"),
            ]),
        ]
    )

    let urlRequest: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/posts",
        method: "POST",
        body: request
    )
    let body = try JSONSerialization.jsonObject(with: try #require(urlRequest.httpBody)) as? [String: Any]
    let props = body?["props"] as? [String: Any]
    let nested = props?["mmswift"] as? [String: Any]

    #expect(body?["root_id"] as? String == "root-id")
    #expect(body?["file_ids"] as? [String] == ["file-id"])
    #expect(nested?["ok"] as? Bool == true)
    #expect(nested?["count"] as? Double == 2)
    #expect(nested?["note"] as? String == "roundtrip")
}

@Test
func httpClientBuildsPatchPostRequestWithOptionalPropsJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let patch = MattermostPatchPostRequest(
        message: "edited",
        props: ["mmswift": .string("edited")]
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/posts/post-id/patch",
        method: "PUT",
        body: patch
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
    let props = body?["props"] as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/posts/post-id/patch")
    #expect(body?["message"] as? String == "edited")
    #expect(props?["mmswift"] as? String == "edited")
}

@Test
func httpClientBuildsThreadRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(
        endpoint: "/posts/post-id/thread",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "perPage", value: "20"),
            URLQueryItem(name: "fromPost", value: "reply-id"),
            URLQueryItem(name: "fromCreateAt", value: "1780000000000"),
            URLQueryItem(name: "direction", value: "down"),
            URLQueryItem(name: "skipFetchThreads", value: "true"),
            URLQueryItem(name: "collapsedThreads", value: "true"),
            URLQueryItem(name: "collapsedThreadsExtended", value: "true"),
        ]
    )

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/posts/post-id/thread?perPage=20&fromPost=reply-id&fromCreateAt=1780000000000&direction=down&skipFetchThreads=true&collapsedThreads=true&collapsedThreadsExtended=true")
}

@Test
func httpClientBuildsUnreadPostsRequest() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request = try httpClient.makeRequest(
        endpoint: "/users/me/channels/channel-id/posts/unread",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "limit_before", value: "5"),
            URLQueryItem(name: "limit_after", value: "7"),
            URLQueryItem(name: "skipFetchThreads", value: "false"),
            URLQueryItem(name: "collapsedThreads", value: "true"),
            URLQueryItem(name: "collapsedThreadsExtended", value: "true"),
        ]
    )

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/channels/channel-id/posts/unread?limit_before=5&limit_after=7&skipFetchThreads=false&collapsedThreads=true&collapsedThreadsExtended=true")
}

@Test
func httpClientBuildsUserThreadRequests() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let listRequest = try httpClient.makeRequest(
        endpoint: "/users/me/teams/team-id/threads",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "since", value: "1780000000000"),
            URLQueryItem(name: "before", value: "before-thread"),
            URLQueryItem(name: "after", value: "after-thread"),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "extended", value: "true"),
            URLQueryItem(name: "deleted", value: "true"),
            URLQueryItem(name: "unread", value: "true"),
            URLQueryItem(name: "threadsOnly", value: "true"),
            URLQueryItem(name: "totalsOnly", value: "true"),
            URLQueryItem(name: "excludeDirect", value: "true"),
        ]
    )
    let stateRequest = try httpClient.makeRequest(
        endpoint: "/users/me/teams/team-id/threads/thread-id",
        method: "GET",
        queryItems: [
            URLQueryItem(name: "extended", value: "true"),
        ]
    )

    #expect(listRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/teams/team-id/threads?since=1780000000000&before=before-thread&after=after-thread&per_page=20&extended=true&deleted=true&unread=true&threadsOnly=true&totalsOnly=true&excludeDirect=true")
    #expect(stateRequest.url?.absoluteString == "https://mattermost.example.com/api/v4/users/me/teams/team-id/threads/thread-id?extended=true")
}

@Test
func httpClientBuildsReactionRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let reaction = MattermostReactionRequest(
        userId: "user-id",
        postId: "post-id",
        emojiName: "smile"
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/reactions",
        method: "POST",
        body: reaction
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/reactions")
    #expect(body?["user_id"] as? String == "user-id")
    #expect(body?["post_id"] as? String == "post-id")
    #expect(body?["emoji_name"] as? String == "smile")
}

@Test
func httpClientBuildsSearchRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let search = MattermostPostSearchRequest(
        terms: "hello",
        isOrSearch: false,
        timeZoneOffset: 0,
        includeDeletedChannels: false,
        page: 0,
        perPage: 20
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/teams/team-id/posts/search",
        method: "POST",
        body: search
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/team-id/posts/search")
    #expect(body?["terms"] as? String == "hello")
    #expect(body?["is_or_search"] as? Bool == false)
    #expect(body?["include_deleted_channels"] as? Bool == false)
    #expect(body?["per_page"] as? Int == 20)
}

@Test
func postSearchRequestClampsInvalidPagination() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let search = MattermostPostSearchRequest(
        terms: "hello",
        isOrSearch: false,
        timeZoneOffset: 0,
        includeDeletedChannels: false,
        page: -2,
        perPage: 0
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/teams/team-id/posts/search",
        method: "POST",
        body: search
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(body?["page"] as? Int == 0)
    #expect(body?["per_page"] as? Int == 1)
}

@Test
func httpClientBuildsBatchStatusRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/status/ids",
        method: "POST",
        body: ["user-a", "user-b"]
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/status/ids")
    #expect(body == ["user-a", "user-b"])
}

@Test
func httpClientBuildsUpdateStatusRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/users/user-a/status",
        method: "PUT",
        body: MattermostUserStatusUpdateRequest(
            userId: "user-a",
            status: "dnd",
            dndEndTime: 1_780_000_000
        )
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/user-a/status")
    #expect(body?["user_id"] as? String == "user-a")
    #expect(body?["status"] as? String == "dnd")
    #expect(body?["dnd_end_time"] as? Int == 1_780_000_000)
}

@Test
func httpClientBuildsMultipartBody() throws {
    let httpClient = MattermostHTTPClient(
        configuration: try MattermostConfiguration(
            serverURL: #require(URL(string: "https://mattermost.example.com")),
            authentication: .bearerToken("token")
        ),
        urlSession: .shared
    )

    let body = httpClient.makeMultipartBody(
        parts: [
            MattermostMultipartPart(
                name: "channel_id",
                filename: nil,
                contentType: nil,
                data: Data("channel-id".utf8)
            ),
            MattermostMultipartPart(
                name: "files",
                filename: "hello.txt",
                contentType: "text/plain",
                data: Data("hello".utf8)
            ),
        ],
        boundary: "Boundary"
    )
    let text = String(decoding: body, as: UTF8.self)

    #expect(text.contains(#"Content-Disposition: form-data; name="channel_id""#))
    #expect(text.contains(#"Content-Disposition: form-data; name="files"; filename="hello.txt""#))
    #expect(text.contains("Content-Type: text/plain"))
    #expect(text.hasSuffix("--Boundary--\r\n"))
}

@Test
func httpClientBuildsMultipartPutBody() throws {
    let httpClient = MattermostHTTPClient(
        configuration: try MattermostConfiguration(
            serverURL: #require(URL(string: "https://mattermost.example.com")),
            authentication: .bearerToken("token")
        ),
        urlSession: .shared
    )

    let request = try httpClient.makeRequest(endpoint: "/users/user-id/image", method: "PUT")
    let body = httpClient.makeMultipartBody(
        parts: [
            MattermostMultipartPart(
                name: "image",
                filename: "avatar.png",
                contentType: "image/png",
                data: Data("png".utf8)
            ),
        ],
        boundary: "Boundary"
    )
    let text = String(decoding: body, as: UTF8.self)

    #expect(request.httpMethod == "PUT")
    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/users/user-id/image")
    #expect(text.contains(#"Content-Disposition: form-data; name="image"; filename="avatar.png""#))
    #expect(text.contains("Content-Type: image/png"))
}

@Test
func httpClientEscapesMultipartDispositionValues() throws {
    let httpClient = MattermostHTTPClient(
        configuration: try MattermostConfiguration(
            serverURL: #require(URL(string: "https://mattermost.example.com")),
            authentication: .bearerToken("token")
        ),
        urlSession: .shared
    )

    let body = httpClient.makeMultipartBody(
        parts: [
            MattermostMultipartPart(
                name: "files\"x\r\nX-Injected: yes",
                filename: "report\"draft\n.txt",
                contentType: "text/plain",
                data: Data("hello".utf8)
            ),
        ],
        boundary: "Boundary"
    )
    let text = String(decoding: body, as: UTF8.self)

    #expect(text.contains(#"Content-Disposition: form-data; name="files\"x  X-Injected: yes"; filename="report\"draft .txt""#))
    #expect(!text.contains("\r\nX-Injected: yes"))
}

@Test
func decodesServerPing() throws {
    let json = """
    {
      "status": "OK",
      "ActiveSearchBackend": "database",
      "database_status": "OK",
      "filestore_status": "OK"
    }
    """.data(using: .utf8)!

    let ping = try mattermostDecoder.decode(MattermostServerPing.self, from: json)

    #expect(ping.status == "OK")
    #expect(ping.activeSearchBackend == "database")
    #expect(ping.databaseStatus == "OK")
    #expect(ping.filestoreStatus == "OK")
}

@Test
func decodesUserAutocompleteBuckets() throws {
    let json = """
    {
      "users": [
        {"id": "user-a", "username": "alice"}
      ],
      "in_channel": [
        {"id": "user-b", "username": "bob"}
      ],
      "out_of_channel": [
        {"id": "user-a", "username": "alice"}
      ]
    }
    """.data(using: .utf8)!

    let autocomplete = try mattermostDecoder.decode(MattermostUserAutocomplete.self, from: json)

    #expect(autocomplete.users.map(\.id) == ["user-a"])
    #expect(autocomplete.inChannel.map(\.id) == ["user-b"])
    #expect(autocomplete.outOfChannel.map(\.id) == ["user-a"])
    #expect(autocomplete.allUsers.map(\.id) == ["user-a", "user-b"])
}

@Test
func decodesSidebarCategory() throws {
    let json = """
    {
      "id": "category-id",
      "user_id": "user-id",
      "team_id": "team-id",
      "display_name": "Favorites",
      "type": "favorites",
      "sort_order": 10,
      "channel_ids": ["channel-a", "channel-b"],
      "sorting": "manual",
      "muted": false,
      "collapsed": true
    }
    """.data(using: .utf8)!

    let category = try mattermostDecoder.decode(MattermostSidebarCategory.self, from: json)

    #expect(category.id == "category-id")
    #expect(category.displayName == "Favorites")
    #expect(category.sortOrder == 10)
    #expect(category.channelIds == ["channel-a", "channel-b"])
    #expect(category.collapsed == true)
}

@Test
func decodesPreference() throws {
    let json = """
    {
      "user_id": "user-id",
      "category": "sidebar_settings",
      "name": "favorite",
      "value": "true"
    }
    """.data(using: .utf8)!

    let preference = try mattermostDecoder.decode(MattermostPreference.self, from: json)

    #expect(preference.userId == "user-id")
    #expect(preference.category == "sidebar_settings")
    #expect(preference.name == "favorite")
    #expect(preference.value == "true")
    #expect(preference.id == "user-id:sidebar_settings:favorite")
}

@Test
func decodesSidebarCategoryListAndPreservesServerOrder() throws {
    let json = """
    {
      "categories": [
        {
          "id": "b",
          "display_name": "Second",
          "type": "custom",
          "channel_ids": []
        },
        {
          "id": "a",
          "display_name": "First",
          "type": "custom",
          "channel_ids": []
        }
      ],
      "order": ["a", "b"]
    }
    """.data(using: .utf8)!

    let list = try mattermostDecoder.decode(MattermostSidebarCategoryList.self, from: json)

    #expect(list.orderedCategories.map(\.id) == ["a", "b"])
}

@Test
func decodesTeamMember() throws {
    let json = Data("""
    {
      "team_id": "team-id",
      "user_id": "user-id",
      "roles": "team_user team_admin",
      "delete_at": 0,
      "scheme_user": true,
      "scheme_admin": false,
      "explicit_roles": "team_admin"
    }
    """.utf8)

    let member = try mattermostDecoder.decode(MattermostTeamMember.self, from: json)

    #expect(member.id == "team-id:user-id")
    #expect(member.teamId == "team-id")
    #expect(member.userId == "user-id")
    #expect(member.roles == "team_user team_admin")
    #expect(member.deleteAt == 0)
    #expect(member.schemeUser == true)
    #expect(member.schemeAdmin == false)
    #expect(member.explicitRoles == "team_admin")
}

@Test
func sidebarChannelIDsMoveAndClampPosition() {
    #expect(MattermostClient.sidebarChannelIDs(
        ["a", "b", "c"],
        moving: "b",
        to: 0
    ) == ["b", "a", "c"])
    #expect(MattermostClient.sidebarChannelIDs(
        ["a", "b", "c"],
        moving: "d",
        to: 99
    ) == ["a", "b", "c", "d"])
    #expect(MattermostClient.sidebarChannelIDs(
        ["a", "b", "c"],
        moving: "c",
        to: -3
    ) == ["c", "a", "b"])
}

@Test
func decodesChannelMemberAndUnreadState() throws {
    let statsJSON = """
    {
      "channel_id": "channel-id",
      "member_count": 42,
      "guest_count": 3,
      "pinnedpost_count": 2,
      "total_msg_count": 99
    }
    """.data(using: .utf8)!
    let memberJSON = """
    {
      "channel_id": "channel-id",
      "user_id": "user-id",
      "roles": "channel_user",
      "last_viewed_at": 100,
      "msg_count": 20,
      "mention_count": 2,
      "notify_props": {
        "desktop": "mention",
        "mark_unread": "all"
      },
      "last_update_at": 120
    }
    """.data(using: .utf8)!
    let unreadJSON = """
    {
      "team_id": "team-id",
      "channel_id": "channel-id",
      "msg_count": 3,
      "mention_count": 1
    }
    """.data(using: .utf8)!

    let stats = try mattermostDecoder.decode(MattermostChannelStats.self, from: statsJSON)
    let member = try mattermostDecoder.decode(MattermostChannelMember.self, from: memberJSON)
    let unread = try mattermostDecoder.decode(MattermostChannelUnread.self, from: unreadJSON)

    #expect(stats.channelId == "channel-id")
    #expect(stats.memberCount == 42)
    #expect(stats.guestCount == 3)
    #expect(stats.pinnedPostCount == 2)
    #expect(stats.totalMessageCount == 99)
    #expect(member.channelId == "channel-id")
    #expect(member.notifyProps?["desktop"] == "mention")
    #expect(member.channelNotifyProps.desktop == "mention")
    #expect(member.channelNotifyProps.markUnread == "all")
    #expect(member.msgCount == 20)
    #expect(unread.teamId == "team-id")
    #expect(unread.msgCount == 3)
    #expect(unread.mentionCount == 1)
}

@Test
func channelNotifyPropsPreservesKnownAndUnknownValues() {
    let props = MattermostChannelNotifyProps(
        desktop: "mention",
        email: "false",
        markUnread: "all",
        push: "mention",
        ignoreChannelMentions: "off",
        rawValues: ["custom": "kept"]
    )

    #expect(props.desktop == "mention")
    #expect(props.email == "false")
    #expect(props.markUnread == "all")
    #expect(props.push == "mention")
    #expect(props.ignoreChannelMentions == "off")
    #expect(props["custom"] == "kept")
    #expect(props.rawValues["desktop"] == "mention")
    #expect(props.rawValues["custom"] == "kept")
}

@Test
func decodesChannelViewResponse() throws {
    let json = """
    {
      "status": "OK",
      "last_viewed_at_times": {
        "channel-id": 123
      }
    }
    """.data(using: .utf8)!

    let response = try mattermostDecoder.decode(MattermostChannelViewResponse.self, from: json)

    #expect(response.isOK)
    #expect(response.lastViewedAtTimes?["channel-id"] == 123)
}

@Test
func decodesPostListAndPostState() throws {
    let json = """
    {
      "order": ["post-a"],
      "posts": {
        "post-a": {
          "id": "post-a",
          "create_at": 10,
          "update_at": 20,
          "edit_at": 30,
          "delete_at": 0,
          "user_id": "user-a",
          "channel_id": "channel-a",
          "root_id": "",
          "original_id": "",
          "message": "hello",
          "type": "",
          "hashtags": "",
          "pending_post_id": "",
          "file_ids": [],
          "has_reactions": false,
          "reply_count": 3,
          "last_reply_at": 40,
          "is_following": true,
          "props": {
            "mmswift": {
              "ok": true,
              "count": 2
            }
          },
          "metadata": {
            "priority": {
              "requested_ack": false
            }
          }
        }
      },
      "next_post_id": "next",
      "prev_post_id": "prev",
      "has_next": false
    }
    """.data(using: .utf8)!

    let postList = try mattermostDecoder.decode(MattermostPostList.self, from: json)
    let post = try #require(postList.orderedPosts.first)

    #expect(postList.order == ["post-a"])
    #expect(post.id == "post-a")
    #expect(post.message == "hello")
    #expect(post.isRootPost)
    #expect(post.isEdited)
    #expect(!post.isDeleted)
    #expect(post.replyCount == 3)
    #expect(post.lastReplyAt == 40)
    #expect(post.isFollowing == true)
    #expect(post.props?["mmswift"] == .object([
        "ok": .bool(true),
        "count": .number(2),
    ]))
    #expect(post.metadata?["priority"] == .object([
        "requested_ack": .bool(false),
    ]))
}

@Test
func decodesThreadListAndThreadState() throws {
    let json = """
    {
      "total": 2,
      "total_unread_threads": 1,
      "total_unread_mentions": 1,
      "total_unread_urgent_mentions": 1,
      "threads": [
        {
          "id": "root-post",
          "reply_count": 3,
          "last_reply_at": 40,
          "last_viewed_at": 20,
          "unread_replies": 2,
          "unread_mentions": 1,
          "is_urgent": true,
          "delete_at": 0,
          "participants": [
            {
              "id": "user-a",
              "username": "alice"
            }
          ],
          "post": {
            "id": "root-post",
            "create_at": 10,
            "update_at": 40,
            "edit_at": 0,
            "delete_at": 0,
            "user_id": "user-a",
            "channel_id": "channel-a",
            "root_id": "",
            "original_id": "",
            "message": "root",
            "type": "",
            "hashtags": "",
            "pending_post_id": "",
            "file_ids": [],
            "has_reactions": false
          }
        }
      ]
    }
    """.data(using: .utf8)!

    let list = try mattermostDecoder.decode(MattermostThreadList.self, from: json)
    let thread = try #require(list.threads.first)

    #expect(list.total == 2)
    #expect(list.totalUnreadThreads == 1)
    #expect(list.totalUnreadMentions == 1)
    #expect(list.totalUnreadUrgentMentions == 1)
    #expect(thread.id == "root-post")
    #expect(thread.replyCount == 3)
    #expect(thread.isUnread)
    #expect(thread.isUrgent)
    #expect(thread.participants.map(\.username) == ["alice"])
    #expect(thread.post?.message == "root")
}

@Test
func decodesReaction() throws {
    let json = """
    {
      "user_id": "user-id",
      "post_id": "post-id",
      "emoji_name": "smile",
      "create_at": 123
    }
    """.data(using: .utf8)!

    let reaction = try mattermostDecoder.decode(MattermostReaction.self, from: json)

    #expect(reaction.userId == "user-id")
    #expect(reaction.postId == "post-id")
    #expect(reaction.emojiName == "smile")
    #expect(reaction.createAt == 123)
}

@Test
func decodesUserStatus() throws {
    let json = """
    {
      "user_id": "user-id",
      "status": "online",
      "manual": false,
      "last_activity_at": 123,
      "active_channel": "channel-id",
      "dnd_end_time": 0
    }
    """.data(using: .utf8)!

    let status = try mattermostDecoder.decode(MattermostUserStatus.self, from: json)

    #expect(status.userId == "user-id")
    #expect(status.status == "online")
    #expect(status.manual == false)
    #expect(status.lastActivityAt == 123)
    #expect(status.activeChannel == "channel-id")
}

@Test
func decodesFileUploadResponse() throws {
    let json = """
    {
      "file_infos": [
        {
          "id": "file-id",
          "user_id": "user-id",
          "post_id": "",
          "create_at": 10,
          "update_at": 20,
          "delete_at": 0,
          "name": "hello.txt",
          "extension": "txt",
          "size": 5,
          "mime_type": "text/plain",
          "width": 0,
          "height": 0,
          "has_preview_image": false
        }
      ],
      "client_ids": ["client-id"]
    }
    """.data(using: .utf8)!

    let upload = try mattermostDecoder.decode(MattermostFileUploadResponse.self, from: json)
    let fileInfo = try #require(upload.fileInfos.first)

    #expect(fileInfo.id == "file-id")
    #expect(fileInfo.name == "hello.txt")
    #expect(fileInfo.extensionName == "txt")
    #expect(fileInfo.size == 5)
    #expect(upload.clientIds == ["client-id"])
}

@Test
func decodesPostSearchResults() throws {
    let json = """
    {
      "order": ["post-a"],
      "posts": {
        "post-a": {
          "id": "post-a",
          "create_at": 10,
          "update_at": 20,
          "edit_at": 0,
          "delete_at": 0,
          "user_id": "user-a",
          "channel_id": "channel-a",
          "root_id": "",
          "original_id": "",
          "message": "hello search",
          "type": "",
          "hashtags": "",
          "pending_post_id": "",
          "file_ids": [],
          "has_reactions": false
        }
      },
      "matches": {
        "post-a": ["hello"]
      },
      "next_post_id": "",
      "prev_post_id": "",
      "first_inaccessible_post_time": 0
    }
    """.data(using: .utf8)!

    let results = try mattermostDecoder.decode(MattermostPostSearchResults.self, from: json)

    #expect(results.orderedPosts.map(\.id) == ["post-a"])
    #expect(results.matches?["post-a"] == ["hello"])
    #expect(results.firstInaccessiblePostTime == 0)
}

@Test
func decodesWebSocketLiveEventAndEmbeddedPost() throws {
    let post = """
    {"id":"post-a","create_at":10,"update_at":20,"edit_at":0,"delete_at":0,"user_id":"user-a","channel_id":"channel-a","root_id":"","original_id":"","message":"hello","type":"","hashtags":"","pending_post_id":"","file_ids":[],"has_reactions":false}
    """
    let escapedPost = post.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
    let json = """
    {
      "event": "posted",
      "data": {
        "post": "\(escapedPost)",
        "set_online": true
      },
      "broadcast": {
        "channel_id": "channel-a",
        "team_id": "team-a"
      },
      "seq": 3
    }
    """.data(using: .utf8)!

    let event = try mattermostDecoder.decode(MattermostLiveEvent.self, from: json)
    let decodedPost = try #require(try event.decodedPost())

    #expect(event.event == "posted")
    #expect(event.name == .posted)
    #expect(event.broadcast?.channelId == "channel-a")
    #expect(decodedPost.id == "post-a")
    #expect(decodedPost.message == "hello")
    #expect(event.data["set_online"] == .bool(true))
    #expect(try event.typedEvent() == .posted(decodedPost))
}

@Test
func decodingWebSocketLiveEventToleratesUnexpectedBroadcastFieldTypes() throws {
    let json = """
    {
      "event": "custom_plugin_event",
      "data": {
        "value": 1
      },
      "broadcast": {
        "channel_id": 42,
        "team_id": "team-a",
        "omit_users": "unexpected"
      },
      "seq": 3
    }
    """.data(using: .utf8)!

    let event = try mattermostDecoder.decode(MattermostLiveEvent.self, from: json)

    #expect(event.event == "custom_plugin_event")
    #expect(event.data["value"] == .number(1))
    #expect(event.broadcast?.channelId == nil)
    #expect(event.broadcast?.teamId == "team-a")
    #expect(event.broadcast?.omitUsers == ["unexpected"])
    #expect(try event.typedEvent() == .unknown(event))
}

@Test
func decodesTypedWebSocketPostMutationEvents() throws {
    let post = """
    {"id":"post-a","create_at":10,"update_at":30,"edit_at":30,"delete_at":0,"user_id":"user-a","channel_id":"channel-a","root_id":"","original_id":"","message":"edited","type":"","hashtags":"","pending_post_id":"","file_ids":[],"has_reactions":false}
    """
    let deletedPost = """
    {"id":"post-a","create_at":10,"update_at":40,"edit_at":30,"delete_at":40,"user_id":"user-a","channel_id":"channel-a","root_id":"","original_id":"","message":"edited","type":"","hashtags":"","pending_post_id":"","file_ids":[],"has_reactions":false}
    """
    let editedEvent = try mattermostDecoder.decode(
        MattermostLiveEvent.self,
        from: postMutationEventJSON(event: "post_edited", post: post)
    )
    let deletedEvent = try mattermostDecoder.decode(
        MattermostLiveEvent.self,
        from: postMutationEventJSON(event: "post_deleted", post: deletedPost)
    )

    let editedPost = try #require(try editedEvent.decodedPost())
    let deletedPostValue = try #require(try deletedEvent.decodedPost())

    #expect(editedEvent.name == .postEdited)
    #expect(deletedEvent.name == .postDeleted)
    #expect(editedPost.isEdited)
    #expect(deletedPostValue.isDeleted)
    #expect(try editedEvent.typedEvent() == .postEdited(editedPost))
    #expect(try deletedEvent.typedEvent() == .postDeleted(deletedPostValue))
}

@Test
func decodesTypedWebSocketTypingEvent() throws {
    let json = """
    {
      "event": "typing",
      "data": {
        "user_id": "user-a",
        "channel_id": "channel-a",
        "parent_id": "root-a"
      },
      "broadcast": {
        "channel_id": "channel-a"
      },
      "seq": 4
    }
    """.data(using: .utf8)!

    let event = try mattermostDecoder.decode(MattermostLiveEvent.self, from: json)
    let typing = try #require(event.decodedTyping())

    #expect(event.name == .typing)
    #expect(typing.userID == "user-a")
    #expect(typing.channelID == "channel-a")
    #expect(typing.parentID == "root-a")
    #expect(try event.typedEvent() == .typing(typing))
}

private func postMutationEventJSON(event: String, post: String) -> Data {
    let escapedPost = post.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
    return """
    {
      "event": "\(event)",
      "data": {
        "post": "\(escapedPost)"
      },
      "broadcast": {
        "channel_id": "channel-a"
      },
      "seq": 4
    }
    """.data(using: .utf8)!
}

@Test
func decodesTypedWebSocketStatusChangeEvent() throws {
    let json = """
    {
      "event": "status_change",
      "data": {
        "user_id": "user-a",
        "status": "away",
        "manual": true
      },
      "seq": 5
    }
    """.data(using: .utf8)!

    let event = try mattermostDecoder.decode(MattermostLiveEvent.self, from: json)
    let statusChange = try #require(event.decodedStatusChange())

    #expect(event.name == .statusChange)
    #expect(statusChange.userID == "user-a")
    #expect(statusChange.status == "away")
    #expect(statusChange.manual == true)
    #expect(try event.typedEvent() == .statusChange(statusChange))
}

@Test
func decodesTypedWebSocketChannelViewedEvent() throws {
    let json = """
    {
      "event": "channel_viewed",
      "data": {
        "user_id": "user-a",
        "channel_id": "channel-a",
        "prev_channel_id": "channel-b"
      },
      "seq": 6
    }
    """.data(using: .utf8)!

    let event = try mattermostDecoder.decode(MattermostLiveEvent.self, from: json)
    let channelViewed = try #require(event.decodedChannelViewed())

    #expect(event.name == .channelViewed)
    #expect(channelViewed.userID == "user-a")
    #expect(channelViewed.channelID == "channel-a")
    #expect(channelViewed.previousChannelID == "channel-b")
    #expect(try event.typedEvent() == .channelViewed(channelViewed))
}

@Test
func decodesTypedWebSocketPostUnreadEvent() throws {
    let json = """
    {
      "event": "post_unread",
      "data": {
        "channel_id": "channel-a",
        "post_id": "post-a"
      },
      "broadcast": {
        "user_id": "user-a",
        "channel_id": "channel-a",
        "team_id": "team-a"
      },
      "seq": 7
    }
    """.data(using: .utf8)!

    let event = try mattermostDecoder.decode(MattermostLiveEvent.self, from: json)
    let invalidation = MattermostCacheInvalidationEvent(
        event: "post_unread",
        userID: "user-a",
        channelID: "channel-a",
        teamID: "team-a",
        postID: "post-a"
    )

    #expect(event.name == .postUnread)
    #expect(event.decodedCacheInvalidation() == invalidation)
    #expect(try event.typedEvent() == .postUnread(invalidation))
}

@Test
func decodesTypedWebSocketThreadUpdatedEventWithEmbeddedPost() throws {
    let post = """
    {"id":"reply-a","create_at":10,"update_at":10,"edit_at":0,"delete_at":0,"user_id":"user-a","channel_id":"channel-a","root_id":"root-a","message":"reply","type":""}
    """
    let event = try mattermostDecoder.decode(
        MattermostLiveEvent.self,
        from: postMutationEventJSON(event: "thread_updated", post: post)
    )
    let thread = try event.decodedThreadEvent()

    #expect(event.name == .threadUpdated)
    #expect(thread.event == "thread_updated")
    #expect(thread.userID == "user-a")
    #expect(thread.channelID == "channel-a")
    #expect(thread.postID == "reply-a")
    #expect(thread.rootID == "root-a")
    #expect(thread.threadID == "root-a")
    #expect(try event.typedEvent() == .threadUpdated(thread))
}

@Test
func decodesTypedWebSocketThreadReadChangedEventWithIDsOnly() throws {
    let json = """
    {
      "event": "thread_read_changed",
      "data": {
        "thread_id": "root-a",
        "post_id": "reply-a",
        "channel_id": "channel-a"
      },
      "broadcast": {
        "user_id": "user-a",
        "team_id": "team-a"
      },
      "seq": 8
    }
    """.data(using: .utf8)!

    let event = try mattermostDecoder.decode(MattermostLiveEvent.self, from: json)
    let thread = try event.decodedThreadEvent()

    #expect(event.name == .threadReadChanged)
    #expect(thread.event == "thread_read_changed")
    #expect(thread.userID == "user-a")
    #expect(thread.channelID == "channel-a")
    #expect(thread.teamID == "team-a")
    #expect(thread.postID == "reply-a")
    #expect(thread.threadID == "root-a")
    #expect(try event.typedEvent() == .threadReadChanged(thread))
}

@Test
func decodesNestedJSONValue() throws {
    let json = """
    {
      "outer": {
        "name": "value",
        "count": 2,
        "items": [true, null]
      }
    }
    """.data(using: .utf8)!

    let value = try mattermostDecoder.decode([String: MattermostJSONValue].self, from: json)

    #expect(value["outer"] == .object([
        "name": .string("value"),
        "count": .number(2),
        "items": .array([.bool(true), .null]),
    ]))
}

@Test
func httpClientBuildsChannelSearchRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let search = MattermostChannelSearchRequest(
        term: "town",
        teamIds: ["team-id"],
        excludeDefaultChannels: true,
        deleted: false,
        page: 1,
        perPage: 20,
        includeSearchById: true
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/search",
        method: "POST",
        body: search
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/channels/search")
    #expect(body?["term"] as? String == "town")
    #expect(body?["team_ids"] as? [String] == ["team-id"])
    #expect(body?["exclude_default_channels"] as? Bool == true)
    #expect(body?["deleted"] as? Bool == false)
    #expect(body?["page"] as? Int == 1)
    #expect(body?["per_page"] as? Int == 20)
    #expect(body?["include_search_by_id"] as? Bool == true)
}

@Test
func channelSearchRequestClampsInvalidPagination() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let search = MattermostChannelSearchRequest(
        term: "town",
        teamIds: ["team-id"],
        excludeDefaultChannels: true,
        deleted: false,
        page: -1,
        perPage: -20,
        includeSearchById: true
    )

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/channels/search",
        method: "POST",
        body: search
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(body?["page"] as? Int == 0)
    #expect(body?["per_page"] as? Int == 1)
}

@Test
func httpClientBuildsTeamChannelSearchRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let search = MattermostTeamChannelSearchRequest(term: "town")

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/teams/team-id/channels/search",
        method: "POST",
        body: search
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/teams/team-id/channels/search")
    #expect(body?["term"] as? String == "town")
}

@Test
func httpClientBuildsEmojiSearchRequestWithJSONBody() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken("token")
    )
    let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: .shared)
    let search = MattermostEmojiSearchRequest(term: "party", prefixOnly: true)

    let request: URLRequest = try httpClient.makeJSONRequest(
        endpoint: "/emoji/search",
        method: "POST",
        body: search
    )
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]

    #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/emoji/search")
    #expect(body?["term"] as? String == "party")
    #expect(body?["prefix_only"] as? Bool == true)
}

@Test
func decodesChannelSearchResultsObjectAndArray() throws {
    let objectJSON = """
    {
      "channels": [
        {
          "id": "channel-a",
          "team_id": "team-a",
          "name": "town-square",
          "display_name": "Town Square",
          "type": "O"
        }
      ],
      "total_count": 1
    }
    """.data(using: .utf8)!
    let arrayJSON = """
    [
      {
        "id": "channel-b",
        "team_id": "team-a",
        "name": "off-topic",
        "display_name": "Off-Topic",
        "type": "O"
      }
    ]
    """.data(using: .utf8)!

    let objectResults = try mattermostDecoder.decode(MattermostChannelSearchResults.self, from: objectJSON)
    let arrayResults = try mattermostDecoder.decode(MattermostChannelSearchResults.self, from: arrayJSON)

    #expect(objectResults.channels.map(\.id) == ["channel-a"])
    #expect(objectResults.totalCount == 1)
    #expect(arrayResults.channels.map(\.id) == ["channel-b"])
    #expect(arrayResults.totalCount == nil)
}

@Test
func decodesCustomEmoji() throws {
    let json = """
    {
      "id": "emoji-a",
      "creator_id": "user-a",
      "name": "party_parrot",
      "create_at": 1,
      "update_at": 2,
      "delete_at": 0
    }
    """.data(using: .utf8)!

    let emoji = try mattermostDecoder.decode(MattermostCustomEmoji.self, from: json)

    #expect(emoji.id == "emoji-a")
    #expect(emoji.creatorId == "user-a")
    #expect(emoji.name == "party_parrot")
    #expect(emoji.createAt == 1)
}

private let mattermostDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()
