import Foundation

// MARK: - User, session, status, and autocomplete models

/// Authenticated Mattermost user profile data.
public struct MattermostUser: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let nickname: String?
    public let position: String?
    public let locale: String?
    public let timezone: [String: String]?
}

/// Source used to extract a session token from a successful Mattermost login response.
public enum MattermostSessionTokenSource: String, Equatable, Sendable {
    case responseHeader
    case authCookie
}

/// User and session token returned by Mattermost username/password login.
public struct MattermostSession: Equatable, Sendable {
    public let user: MattermostUser
    public let token: String
    public let tokenSource: MattermostSessionTokenSource

    public init(
        user: MattermostUser,
        token: String,
        tokenSource: MattermostSessionTokenSource = .responseHeader
    ) {
        self.user = user
        self.token = token
        self.tokenSource = tokenSource
    }

    public func client(serverURL: URL, urlSession: URLSession = .mattermost) throws -> MattermostClient {
        try MattermostClient(serverURL: serverURL, token: token, urlSession: urlSession)
    }
}

@available(*, deprecated, renamed: "MattermostSession")
public typealias MattermostLoginSession = MattermostSession

/// MFA requirement check returned before password login.
public struct MattermostMFARequired: Decodable, Equatable, Sendable {
    public let mfaRequired: Bool
}

/// MFA setup secret returned by Mattermost.
public struct MattermostMFASecret: Decodable, Equatable, Sendable {
    public let secret: String?
    public let qrCode: String?
}

/// Presence status for a Mattermost user.
public struct MattermostUserStatus: Codable, Equatable, Sendable {
    public let userId: String
    public let status: String
    public let manual: Bool?
    public let lastActivityAt: Int64?
    public let activeChannel: String?
    public let dndEndTime: Int64?
}

/// Custom status shown alongside a user's presence.
public struct MattermostCustomStatus: Codable, Equatable, Sendable {
    public let emoji: String
    public let text: String
    public let duration: String?
    public let expiresAt: String?

    public init(emoji: String, text: String, duration: String? = nil, expiresAt: String? = nil) {
        self.emoji = emoji
        self.text = text
        self.duration = duration
        self.expiresAt = expiresAt
    }
}

/// User autocomplete buckets returned by Mattermost for composer/member pickers.
public struct MattermostUserAutocomplete: Decodable, Equatable, Sendable {
    public let users: [MattermostUser]
    public let inChannel: [MattermostUser]
    public let outOfChannel: [MattermostUser]

    public var allUsers: [MattermostUser] {
        var seen = Set<String>()
        return (users + inChannel + outOfChannel).filter { user in
            seen.insert(user.id).inserted
        }
    }

    public init(
        users: [MattermostUser] = [],
        inChannel: [MattermostUser] = [],
        outOfChannel: [MattermostUser] = []
    ) {
        self.users = users
        self.inChannel = inChannel
        self.outOfChannel = outOfChannel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.decodeIfPresent([MattermostUser].self, forKey: .users) ?? []
        inChannel = try container.decodeIfPresent([MattermostUser].self, forKey: .inChannel) ?? []
        outOfChannel = try container.decodeIfPresent([MattermostUser].self, forKey: .outOfChannel) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case users
        case inChannel
        case outOfChannel
    }
}

/// Sanitized active session metadata returned by Mattermost for active user sessions.
public struct MattermostUserSession: Decodable, Equatable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let userId: String?
    public let createAt: Int64?
    public let deviceId: String?
    public let expiresAt: Int64?
    public let isOauth: Bool?
    public let lastActivityAt: Int64?
    public let props: [String: MattermostJSONValue]?
    public let roles: String?
    /// Credential-bearing session token. Do not log or persist outside secure storage.
    public let token: String?

    public var description: String {
        "MattermostUserSession(id: \(id), userId: \(userId ?? "-"), expiresAt: \(expiresAt.map(String.init) ?? "-"))"
    }

    public var debugDescription: String {
        description
    }
}
