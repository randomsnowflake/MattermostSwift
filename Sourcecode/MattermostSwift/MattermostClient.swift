import Foundation

/// High-level entry point for a single Mattermost server/account.
public struct MattermostClient: Sendable {
    let configuration: MattermostConfiguration
    let httpClient: MattermostHTTPClient
    let urlSession: URLSession

    /// Creates a client from an explicit configuration.
    public init(configuration: MattermostConfiguration, urlSession: URLSession = .mattermost) {
        self.configuration = configuration
        self.urlSession = urlSession
        httpClient = MattermostHTTPClient(configuration: configuration, urlSession: urlSession)
    }

    /// Creates a bearer-token authenticated client.
    public init(
        serverURL: URL,
        token: String,
        urlSession: URLSession = .mattermost,
        allowInsecureHTTP: Bool = false
    ) throws {
        let configuration = try MattermostConfiguration(
            serverURL: serverURL,
            authentication: .bearerToken(token),
            allowInsecureHTTP: allowInsecureHTTP
        )
        self.init(configuration: configuration, urlSession: urlSession)
    }

    /// Creates a WebSocket live-event stream for this client.
    public func liveEventStream() -> MattermostLiveEventStream {
        MattermostLiveEventStream(configuration: configuration, urlSession: urlSession)
    }

    static func clampedPage(_ page: Int) -> Int {
        max(0, page)
    }

    static func clampedPerPage(_ perPage: Int) -> Int {
        max(1, perPage)
    }
}

public extension MattermostClient {
    /// Logs in with a username/email and password, returning the user plus session token.
    ///
    /// Mattermost browser clients can authenticate from the `MMAUTHTOKEN` cookie that is set
    /// by a successful login. API clients can authenticate with the same session token as a
    /// bearer token, so the SDK accepts either the documented `Token` response header or the
    /// official `MMAUTHTOKEN` cookie. The SDK does not store the returned token. Host apps are
    /// responsible for secure storage.
    static func login(
        serverURL: URL,
        loginID: String,
        password: String,
        mfaToken: String? = nil,
        deviceID: String? = nil,
        ldapOnly: Bool? = nil,
        urlSession: URLSession = .mattermost
    ) async throws -> MattermostSession {
        let configuration = try MattermostConfiguration(
            serverURL: serverURL,
            authentication: .none
        )
        let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: urlSession)
        var request = try httpClient.makeJSONRequest(
            endpoint: "/users/login",
            method: "POST",
            body: MattermostLoginRequest(
                loginId: loginID,
                password: password,
                token: mfaToken,
                deviceId: deviceID,
                ldapOnly: ldapOnly
            )
        )
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let response: MattermostHTTPResponse<MattermostUser> = try await httpClient.performWithResponse(request: request)
        if let sessionToken = response.httpResponse.mattermostSessionToken(
            cookieStorage: urlSession.configuration.httpCookieStorage
        ) {
            return MattermostSession(
                user: response.value,
                token: sessionToken.token,
                tokenSource: sessionToken.source
            )
        }

        throw MattermostError.missingAuthenticationToken
    }

    /// Logs in from Mattermost development environment variables.
    ///
    /// Required:
    /// - `MATTERMOST_URL`
    /// - `MATTERMOST_USERNAME`
    /// - `MATTERMOST_PASSWORD`
    static func loginFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        urlSession: URLSession = .mattermost
    ) async throws -> MattermostSession {
        guard let rawURL = environment["MATTERMOST_URL"], !rawURL.isEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_URL")
        }
        guard let serverURL = URL(string: rawURL) else {
            throw MattermostError.invalidServerURL(rawURL)
        }
        guard let username = environment["MATTERMOST_USERNAME"].nonEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_USERNAME")
        }
        guard let password = environment["MATTERMOST_PASSWORD"].nonEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_PASSWORD")
        }

        return try await login(
            serverURL: serverURL,
            loginID: username,
            password: password,
            urlSession: urlSession
        )
    }

    /// Builds a client from Mattermost development environment variables.
    ///
    /// Required:
    /// - `MATTERMOST_URL`
    /// - `MATTERMOST_TOKEN`, or `MATTERMOST_AUTH_TOKEN` as a local compatibility alias
    static func liveFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> MattermostClient {
        guard let rawURL = environment["MATTERMOST_URL"], !rawURL.isEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_URL")
        }
        guard let serverURL = URL(string: rawURL) else {
            throw MattermostError.invalidServerURL(rawURL)
        }
        guard let token = environment["MATTERMOST_TOKEN"].nonEmpty ?? environment["MATTERMOST_AUTH_TOKEN"].nonEmpty else {
            throw MattermostError.missingEnvironmentVariable("MATTERMOST_TOKEN")
        }
        return try MattermostClient(serverURL: serverURL, token: token)
    }
}

private extension HTTPURLResponse {
    func mattermostSessionToken(
        cookieStorage: HTTPCookieStorage?
    ) -> (token: String, source: MattermostSessionTokenSource)? {
        if let token = authenticationToken.nonEmpty {
            return (token, .responseHeader)
        }

        if let token = mattermostAuthCookieToken.nonEmpty {
            return (token, .authCookie)
        }

        if let url,
           let token = cookieStorage?
               .cookies(for: url)?
               .first(where: { $0.name == "MMAUTHTOKEN" })?
               .value
               .nonEmpty {
            return (token, .authCookie)
        }

        return nil
    }

    var authenticationToken: String? {
        value(forHTTPHeaderField: "Token")
    }

    var mattermostAuthCookieToken: String? {
        guard let url else {
            return nil
        }

        var headerFields: [String: String] = [:]
        for (key, value) in allHeaderFields {
            headerFields[String(describing: key)] = String(describing: value)
        }

        return HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            .first(where: { $0.name == "MMAUTHTOKEN" })?
            .value
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self, !value.isEmpty else {
            return nil
        }
        return value
    }
}

extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

public extension URLSession {
    /// URLSession preconfigured with finite request/resource timeouts for Mattermost.
    ///
    /// `URLSession.shared` uses a 7-day resource timeout, which lets a stalled server hang a
    /// request indefinitely. This session caps a single request at 30s and a full transfer
    /// (e.g. a file download) at 5 minutes.
    static let mattermost: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()
}
