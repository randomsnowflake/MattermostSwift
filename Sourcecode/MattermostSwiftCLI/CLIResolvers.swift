import Foundation
@_spi(Testing) import MattermostSwift

extension MattermostSwiftCLI {
    static func resolvedChannelID(_ channelID: String?) throws -> String {
        if let channelID, !channelID.isEmpty {
            return channelID
        }

        if let channelID = ProcessInfo.processInfo.environment["MATTERMOST_CHANNEL_ID"], !channelID.isEmpty {
            return channelID
        }

        throw CLIError.usage("Provide a channel id or set MATTERMOST_CHANNEL_ID.")
    }

    static func resolvedUserID(_ userID: String?, client: MattermostClient) async throws -> String {
        if let userID, !userID.isEmpty {
            return userID
        }

        return try await client.currentUser().id
    }

    static func resolvedTeamID(_ teamID: String?, client: MattermostClient) async throws -> String {
        if let teamID, !teamID.isEmpty {
            return teamID
        }

        return try await loadTeamID(client: client)
    }

    static func loadTeamID(client: MattermostClient) async throws -> String {
        if let teamName = ProcessInfo.processInfo.environment["MATTERMOST_TEAM_NAME"], !teamName.isEmpty {
            return try await client.team(named: teamName).id
        }

        let channels = try await client.joinedChannelsAcrossTeams()
        if let teamID = channels.compactMap(\.teamId).first(where: { !$0.isEmpty }) {
            return teamID
        }

        throw MattermostError.missingEnvironmentVariable("MATTERMOST_TEAM_NAME")
    }

    static func loadChannels(client: MattermostClient) async throws -> [MattermostChannel] {
        if let teamName = ProcessInfo.processInfo.environment["MATTERMOST_TEAM_NAME"], !teamName.isEmpty {
            let team = try await client.team(named: teamName)
            return try await client.joinedChannels(teamID: team.id)
        }

        return try await client.joinedChannelsAcrossTeams()
    }

    static func loadCategories(client: MattermostClient) async throws -> [MattermostSidebarCategory] {
        let teamID = try await loadTeamID(client: client)
        return try await client.sidebarCategories(teamID: teamID)
    }

}
