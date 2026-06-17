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

    enum CodingKeys: String, CodingKey {
        case status
        case activeSearchBackend = "ActiveSearchBackend"
        case databaseStatus
        case filestoreStatus
        case iosLatestVersion = "IosLatestVersion"
        case iosMinVersion = "IosMinVersion"
        case androidLatestVersion = "AndroidLatestVersion"
        case androidMinVersion = "AndroidMinVersion"
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

    enum CodingKeys: String, CodingKey {
        case buildNumber = "BuildNumber"
        case buildHash = "BuildHash"
        case buildDate = "BuildDate"
        case buildEnterpriseReady = "BuildEnterpriseReady"
        case collapsedThreads = "CollapsedThreads"
        case enableFile = "EnableFile"
        case enableFileAttachments = "EnableFileAttachments"
        case enableCustomEmoji = "EnableCustomEmoji"
        case enableIncomingWebhooks = "EnableIncomingWebhooks"
        case enableOutgoingWebhooks = "EnableOutgoingWebhooks"
        case enablePostUsernameOverride = "EnablePostUsernameOverride"
        case enablePostIconOverride = "EnablePostIconOverride"
        case siteName = "SiteName"
    }
}
