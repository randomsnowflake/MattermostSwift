import Foundation

// MARK: - Single sign-on

/// A single sign-on service a Mattermost server can offer for mobile login.
public enum MattermostSSOProvider: String, CaseIterable, Sendable {
    case gitlab
    case openid
    case google
    case office365
    case saml

    /// The callback URL the server redirects to with the session. The server only accepts
    /// schemes from `NativeAppSettings.AppCustomURLSchemes` (default `mmauth://`, `mmauthbeta://`).
    public static let callbackScheme = "mmauth"
    public static let callbackURL = "mmauth://callback"

    /// Starts the server's mobile login flow. Open it in a web authentication session that
    /// listens for ``callbackScheme``, then pass the callback URL to ``MattermostSSOCallback``.
    public func mobileLoginURL(serverURL: URL) -> URL {
        let redirect = URLQueryItem(name: "redirect_to", value: Self.callbackURL)
        switch self {
        case .saml:
            return serverURL.appending(path: "login/sso/saml")
                .appending(queryItems: [URLQueryItem(name: "action", value: "mobile"), redirect])
        default:
            return serverURL.appending(path: "oauth/\(rawValue)/mobile_login").appending(queryItems: [redirect])
        }
    }
}

/// The session a server hands back at the end of a mobile SSO login:
/// `mmauth://callback?MMAUTHTOKEN=…&MMCSRF=…&srv=…`.
///
/// shortcut: servers with `FeatureFlagMobileSSOCodeExchange` on and a PKCE challenge return
/// `login_code` instead; the SDK sends no challenge, so servers answer with the token (11.11 has
/// no code exchange at all). Add the code exchange when servers require PKCE.
public struct MattermostSSOCallback: Equatable, Sendable {
    /// Query names of the callback URL; the token one matches the session cookie name.
    public static let tokenParameter = "MMAUTHTOKEN"
    public static let csrfParameter = "MMCSRF"
    public static let serverParameter = "srv"

    /// Session token; use it as a bearer token like a password-login session.
    public let token: String
    public let csrf: String?
    /// The server's Site URL as it reported itself. Compare it with the server the login was
    /// started on, so a hostile redirect can't hand the app another server's session.
    public let serverURL: String?

    public init(url: URL) throws {
        guard url.scheme?.lowercased() == MattermostSSOProvider.callbackScheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let token = items.first(where: { $0.name == Self.tokenParameter })?.value, !token.isEmpty else {
            throw MattermostError.missingAuthenticationToken
        }
        self.token = token
        csrf = items.first { $0.name == Self.csrfParameter }?.value
        serverURL = items.first { $0.name == Self.serverParameter }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public extension MattermostClientConfig {
    /// SSO services the server advertises, in the order Mattermost's own login page lists them.
    ///
    /// Since v11 the server sends the GitLab keys only with an OpenID-licensed build, so an
    /// unlicensed server with GitLab on omits them. A missing `EnableSignUpWithGitLab` therefore
    /// counts as "maybe": GitLab is offered, and a server without it shows its error page.
    var ssoProviders: [MattermostSSOProvider] {
        func isOn(_ value: String?) -> Bool { value?.lowercased() == "true" }
        var providers: [MattermostSSOProvider] = []
        if enableSignUpWithGitLab == nil || isOn(enableSignUpWithGitLab) { providers.append(.gitlab) }
        if isOn(enableSignUpWithGoogle) { providers.append(.google) }
        if isOn(enableSignUpWithOffice365) { providers.append(.office365) }
        if isOn(enableSignUpWithOpenId) { providers.append(.openid) }
        if isOn(enableSaml) { providers.append(.saml) }
        return providers
    }
}

public extension MattermostClient {
    /// Loads the public client configuration before sign-in (login options, SSO buttons).
    static func clientConfig(
        serverURL: URL,
        allowInsecureHTTP: Bool = false,
        urlSession: URLSession = .mattermost
    ) async throws -> MattermostClientConfig {
        let configuration = try MattermostConfiguration(
            serverURL: serverURL,
            authentication: .none,
            allowInsecureHTTP: allowInsecureHTTP
        )
        return try await MattermostHTTPClient(configuration: configuration, urlSession: urlSession).get("/config/client")
    }
}
