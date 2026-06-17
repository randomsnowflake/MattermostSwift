import Foundation

// MARK: - Server

extension MattermostClient {
    /// Loads basic server health and capability metadata.
    public func serverInfo() async throws -> MattermostServerInfo {
        async let ping = serverPing()
        async let clientConfig = clientConfig()

        return try await MattermostServerInfo(
            ping: ping,
            clientConfig: clientConfig
        )
    }

    /// Checks Mattermost server health.
    public func serverPing() async throws -> MattermostServerPing {
        try await httpClient.get(
            "/system/ping",
            queryItems: [
                URLQueryItem(name: "get_server_status", value: "true"),
                URLQueryItem(name: "use_rest_semantics", value: "true"),
            ]
        )
    }

    /// Loads the subset of server configuration exposed to clients.
    public func clientConfig() async throws -> MattermostClientConfig {
        try await httpClient.get("/config/client")
    }
}
