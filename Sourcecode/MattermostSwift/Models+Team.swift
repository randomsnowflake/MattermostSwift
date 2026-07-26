import Foundation

// MARK: - Team and team membership models

/// Mattermost team metadata.
public struct MattermostTeam: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String?
    public let type: String?
}

/// Membership and role state for a user on a Mattermost team.
public struct MattermostTeamMember: Decodable, Equatable, Sendable, Identifiable {
    public let teamID: String
    public let userID: String
    public let roles: String?
    public let deleteAt: Int64?
    public let schemeUser: Bool?
    public let schemeAdmin: Bool?
    public let explicitRoles: String?

    public var id: String {
        "\(teamID):\(userID)"
    }

    @available(*, deprecated, renamed: "teamID")
    public var teamId: String { teamID }
    @available(*, deprecated, renamed: "userID")
    public var userId: String { userID }

    enum CodingKeys: String, CodingKey {
        case teamID = "teamId"
        case userID = "userId"
        case roles
        case deleteAt
        case schemeUser
        case schemeAdmin
        case explicitRoles
    }

    public var deletedAt: Date? {
        guard let deleteAt, deleteAt > 0 else { return nil }
        return Date(mattermostMilliseconds: deleteAt)
    }
}
