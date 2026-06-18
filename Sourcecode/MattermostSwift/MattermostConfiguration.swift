import Foundation

/// Configuration for a single Mattermost server and account.
public struct MattermostConfiguration: Sendable {
    public let serverURL: URL
    public let apiBaseURL: URL
    public let webSocketURL: URL
    public let authentication: MattermostAuthentication

    /// - Parameter allowInsecureHTTP: Permits `http://` (and `ws://`) for non-loopback hosts.
    ///   Loopback hosts (`localhost`, `127.0.0.1`, `::1`) are always allowed for local development.
    ///   Remote `http://` is rejected by default because it transmits the bearer token in cleartext.
    public init(
        serverURL: URL,
        authentication: MattermostAuthentication,
        allowInsecureHTTP: Bool = false
    ) throws {
        let normalizedServerURL = serverURL.normalizedMattermostServerURL
        guard normalizedServerURL.scheme == "https" || normalizedServerURL.scheme == "http" else {
            throw MattermostError.invalidServerURL(serverURL.absoluteString)
        }

        if normalizedServerURL.scheme == "http",
           !allowInsecureHTTP,
           !normalizedServerURL.isLoopbackHost {
            throw MattermostError.insecureServerURL(serverURL.absoluteString)
        }
        if normalizedServerURL.scheme == "http",
           allowInsecureHTTP,
           !normalizedServerURL.isLoopbackHost {
            fputs(
                "MattermostSwift: allowInsecureHTTP=true with non-loopback host \(normalizedServerURL.host() ?? "?") sends bearer tokens in cleartext.\n",
                stderr
            )
        }

        self.serverURL = normalizedServerURL
        apiBaseURL = normalizedServerURL.appending(path: "api/v4", directoryHint: .isDirectory)
        webSocketURL = try normalizedServerURL.mattermostWebSocketURL()
        self.authentication = authentication
    }
}

/// Authentication modes supported by the SDK.
public enum MattermostAuthentication: Sendable, Equatable {
    case none
    case bearerToken(String)
}

private extension URL {
    var isLoopbackHost: Bool {
        guard let host = host()?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
    }

    var normalizedMattermostServerURL: URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.path = path.removingMattermostAPIPath.mattermostTrimmingTrailingSlashes
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? self
    }

    func mattermostWebSocketURL() throws -> URL {
        let webSocketBaseURL = appending(path: "api/v4/websocket")
        guard var components = URLComponents(url: webSocketBaseURL, resolvingAgainstBaseURL: false) else {
            throw MattermostError.invalidEndpoint("/websocket")
        }

        switch scheme {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        default:
            throw MattermostError.invalidServerURL(absoluteString)
        }

        guard let url = components.url else {
            throw MattermostError.invalidEndpoint("/websocket")
        }
        return url
    }
}

private extension String {
    var removingMattermostAPIPath: String {
        let pathComponents = split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        for index in pathComponents.indices where pathComponents[index] == "api" {
            let nextIndex = pathComponents.index(after: index)
            if nextIndex < pathComponents.endIndex, pathComponents[nextIndex] == "v4" {
                return "/" + pathComponents[..<index].joined(separator: "/")
            }
        }

        return self
    }
}
