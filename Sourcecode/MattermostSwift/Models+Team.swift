import Foundation

// MARK: - Team and team membership models

/// Mattermost team metadata.
public struct MattermostTeam: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String?
    public let type: String?
}

/// Membership and role state for a user on a Mattermost team.
public struct MattermostTeamMember: Decodable, Equatable, Sendable, Identifiable {
    public let teamId: String
    public let userId: String
    public let roles: String?
    public let deleteAt: Int64?
    public let schemeUser: Bool?
    public let schemeAdmin: Bool?
    public let explicitRoles: String?

    public var id: String {
        "\(teamId):\(userId)"
    }
}
