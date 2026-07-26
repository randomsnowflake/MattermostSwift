import Foundation

// MARK: - Server info, ping, and client configuration models

/// Basic server health and client capability metadata.
public struct MattermostServerInfo: Equatable, Sendable {
    public let ping: MattermostServerPing
    public let clientConfig: MattermostClientConfig
}

/// Mattermost server health response.
public struct MattermostServerPing: Decodable, Equatable, Sendable {
    public let status: String
    public let activeSearchBackend: String?
    public let databaseStatus: String?
    public let filestoreStatus: String?
    public let iosLatestVersion: String?
    public let iosMinVersion: String?
    public let androidLatestVersion: String?
    public let androidMinVersion: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MattermostServerCodingKey.self)
        status = try container.decodeRequiredString(matching: "status")
        activeSearchBackend = try container.decodeStringIfPresent(matching: "ActiveSearchBackend")
        databaseStatus = try container.decodeStringIfPresent(matching: "databaseStatus")
        filestoreStatus = try container.decodeStringIfPresent(matching: "filestoreStatus")
        iosLatestVersion = try container.decodeStringIfPresent(matching: "IosLatestVersion")
        iosMinVersion = try container.decodeStringIfPresent(matching: "IosMinVersion")
        androidLatestVersion = try container.decodeStringIfPresent(matching: "AndroidLatestVersion")
        androidMinVersion = try container.decodeStringIfPresent(matching: "AndroidMinVersion")
    }
}

/// Public client configuration values useful for SDK capability checks.
public struct MattermostClientConfig: Decodable, Equatable, Sendable {
    public let buildNumber: String?
    public let buildHash: String?
    public let buildDate: String?
    public let buildEnterpriseReady: String?
    public let collapsedThreads: String?
    public let enableFile: String?
    public let enableFileAttachments: String?
    public let enableCustomEmoji: String?
    public let enableIncomingWebhooks: String?
    public let enableOutgoingWebhooks: String?
    public let enablePostUsernameOverride: String?
    public let enablePostIconOverride: String?
    public let siteName: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MattermostServerCodingKey.self)
        buildNumber = try container.decodeStringIfPresent(matching: "BuildNumber")
        buildHash = try container.decodeStringIfPresent(matching: "BuildHash")
        buildDate = try container.decodeStringIfPresent(matching: "BuildDate")
        buildEnterpriseReady = try container.decodeStringIfPresent(matching: "BuildEnterpriseReady")
        collapsedThreads = try container.decodeStringIfPresent(matching: "CollapsedThreads")
        enableFile = try container.decodeStringIfPresent(matching: "EnableFile")
        enableFileAttachments = try container.decodeStringIfPresent(matching: "EnableFileAttachments")
        enableCustomEmoji = try container.decodeStringIfPresent(matching: "EnableCustomEmoji")
        enableIncomingWebhooks = try container.decodeStringIfPresent(matching: "EnableIncomingWebhooks")
        enableOutgoingWebhooks = try container.decodeStringIfPresent(matching: "EnableOutgoingWebhooks")
        enablePostUsernameOverride = try container.decodeStringIfPresent(matching: "EnablePostUsernameOverride")
        enablePostIconOverride = try container.decodeStringIfPresent(matching: "EnablePostIconOverride")
        siteName = try container.decodeStringIfPresent(matching: "SiteName")
    }
}

private struct MattermostServerCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private extension KeyedDecodingContainer where Key == MattermostServerCodingKey {
    func decodeRequiredString(matching expectedKey: String) throws -> String {
        guard let key = key(matching: expectedKey) else {
            throw DecodingError.keyNotFound(
                MattermostServerCodingKey(expectedKey),
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "No value associated with key \(expectedKey)."
                )
            )
        }
        return try decode(String.self, forKey: key)
    }

    func decodeStringIfPresent(matching expectedKey: String) throws -> String? {
        guard let key = key(matching: expectedKey) else {
            return nil
        }
        return try decodeIfPresent(String.self, forKey: key)
    }

    /// Mattermost builds these maps with string literals whose case and separators vary by release.
    func key(matching expectedKey: String) -> MattermostServerCodingKey? {
        if let exactKey = allKeys.first(where: { $0.stringValue == expectedKey }) {
            return exactKey
        }
        let expected = Self.normalized(expectedKey)
        return allKeys.first { Self.normalized($0.stringValue) == expected }
    }

    static func normalized(_ key: String) -> String {
        key.filter { $0.isLetter || $0.isNumber }.lowercased()
    }
}
