import Foundation

// MARK: - User, session, status, and autocomplete models

/// Notification preferences embedded on the authenticated Mattermost user.
///
/// Mattermost stores boolean-like values as strings and supplies the configured
/// mention terms as one comma-separated value. Keeping the wire representation
/// here lets hosts apply the same user-specific mention rules without guessing
/// from the username alone.
public struct MattermostUserNotifyProps: Codable, Equatable, Hashable, Sendable {
    public let mentionKeys: String?
    public let channel: String?
    public let firstName: String?

    public init(
        mentionKeys: String? = nil,
        channel: String? = nil,
        firstName: String? = nil
    ) {
        self.mentionKeys = mentionKeys
        self.channel = channel
        self.firstName = firstName
    }

    /// Configured mention terms with whitespace and empty entries removed.
    public var parsedMentionKeys: [String] {
        mentionKeys?
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    public var includesChannelMentions: Bool {
        channel?.lowercased() != "false"
    }

    public var includesFirstName: Bool? {
        guard let firstName else { return nil }
        return firstName.lowercased() == "true"
    }
}

/// Authenticated Mattermost user profile data.
public struct MattermostUser: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let nickname: String?
    public let position: String?
    public let locale: String?
    public let timezone: [String: String]?
    /// Epoch **milliseconds** of the user's last profile-picture upload.
    /// `0` (or `nil`) means no custom picture — clients should render a
    /// generated fallback. Changes act as a cache-busting token for the
    /// `/users/{id}/image` bytes.
    public let lastPictureUpdate: Int64?
    /// Present for the authenticated user (or callers with permission to view it).
    public let notifyProps: MattermostUserNotifyProps?

    public init(
        id: String,
        username: String,
        email: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        nickname: String? = nil,
        position: String? = nil,
        locale: String? = nil,
        timezone: [String: String]? = nil,
        lastPictureUpdate: Int64? = nil,
        notifyProps: MattermostUserNotifyProps? = nil
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.nickname = nickname
        self.position = position
        self.locale = locale
        self.timezone = timezone
        self.lastPictureUpdate = lastPictureUpdate
        self.notifyProps = notifyProps
    }

    public var lastPictureUpdatedAt: Date? {
        lastPictureUpdate.map(Date.init(mattermostMilliseconds:))
    }
}

/// Source used to extract a session token from a successful Mattermost login response.
public enum MattermostSessionTokenSource: String, Equatable, Sendable {
    case responseHeader
    case authCookie
}

/// User and session token returned by Mattermost username/password login.
///
/// Its textual descriptions redact the token.
public struct MattermostSession: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let user: MattermostUser
    public let token: String
    public let tokenSource: MattermostSessionTokenSource
    public let serverURL: URL?
    public let allowInsecureHTTP: Bool

    public init(
        user: MattermostUser,
        token: String,
        tokenSource: MattermostSessionTokenSource = .responseHeader,
        serverURL: URL? = nil,
        allowInsecureHTTP: Bool = false
    ) {
        self.user = user
        self.token = token
        self.tokenSource = tokenSource
        self.serverURL = serverURL
        self.allowInsecureHTTP = allowInsecureHTTP
    }

    public var description: String {
        "MattermostSession(user: \(user.username), tokenSource: \(tokenSource), token: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public func client(
        serverURL: URL? = nil,
        urlSession: URLSession = .mattermost
    ) throws -> MattermostClient {
        guard let resolvedServerURL = serverURL ?? self.serverURL else {
            throw MattermostError.invalidServerURL(
                "This session predates stored server URLs; pass serverURL explicitly."
            )
        }
        return try MattermostClient(
            serverURL: resolvedServerURL,
            token: token,
            urlSession: urlSession,
            allowInsecureHTTP: allowInsecureHTTP
        )
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
    public let userID: String
    public let status: MattermostUserStatusValue
    public let manual: Bool?
    public let lastActivityAt: Int64?
    public let activeChannel: String?
    public let dndEndTime: Int64?

    public init(
        userID: String,
        status: MattermostUserStatusValue,
        manual: Bool? = nil,
        lastActivityAt: Int64? = nil,
        activeChannel: String? = nil,
        dndEndTime: Int64? = nil
    ) {
        self.userID = userID
        self.status = status
        self.manual = manual
        self.lastActivityAt = lastActivityAt
        self.activeChannel = activeChannel
        self.dndEndTime = dndEndTime
    }

    @available(*, deprecated, message: "Use init(userID:status:manual:lastActivityAt:activeChannel:dndEndTime:)")
    public init(
        userId: String,
        status: String,
        manual: Bool? = nil,
        lastActivityAt: Int64? = nil,
        activeChannel: String? = nil,
        dndEndTime: Int64? = nil
    ) {
        self.init(
            userID: userId,
            status: MattermostUserStatusValue(rawValue: status),
            manual: manual,
            lastActivityAt: lastActivityAt,
            activeChannel: activeChannel,
            dndEndTime: dndEndTime
        )
    }

    @available(*, deprecated, renamed: "userID")
    public var userId: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case status
        case manual
        case lastActivityAt
        case activeChannel
        case dndEndTime
    }

    public var lastActivityDate: Date? {
        lastActivityAt.map(Date.init(mattermostMilliseconds:))
    }
    public var dndEndDate: Date? {
        dndEndTime.map(Date.init(mattermostMilliseconds:))
    }
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
public struct MattermostUserAutocomplete: Codable, Equatable, Sendable {
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
    public let userID: String?
    public let createAt: Int64?
    public let deviceID: String?
    public let expiresAt: Int64?
    public let isOauth: Bool?
    public let lastActivityAt: Int64?
    public let props: [String: MattermostJSONValue]?
    public let roles: String?
    /// Credential-bearing session token. Do not log or persist outside secure storage.
    public let token: String?

    public var description: String {
        "MattermostUserSession(id: \(id), userID: \(userID ?? "-"), expiresAt: \(expiresAt.map(String.init) ?? "-"))"
    }

    public var debugDescription: String {
        description
    }

    @available(*, deprecated, renamed: "userID")
    public var userId: String? { userID }
    @available(*, deprecated, renamed: "deviceID")
    public var deviceId: String? { deviceID }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "userId"
        case createAt
        case deviceID = "deviceId"
        case expiresAt
        case isOauth
        case lastActivityAt
        case props
        case roles
        case token
    }

    public var createdAt: Date? { createAt.map(Date.init(mattermostMilliseconds:)) }
    public var expirationDate: Date? { expiresAt.map(Date.init(mattermostMilliseconds:)) }
    public var lastActivityDate: Date? {
        lastActivityAt.map(Date.init(mattermostMilliseconds:))
    }
}
