import Foundation

// MARK: - Slash commands

extension MattermostClient {
    /// Runs a slash command (`POST /commands/execute`): built-in, custom and plugin commands alike.
    ///
    /// Commands are not idempotent; never retry or queue one. The visible result arrives
    /// separately: a `posted` event for in-channel replies, an `ephemeral_message` event for
    /// private ones and an `open_dialog` event when the command opens an interactive dialog.
    ///
    /// - Parameters:
    ///   - command: The full text, including the leading `/`.
    ///   - rootID: The thread the command runs in, if any.
    @discardableResult
    public func executeCommand(
        _ command: String,
        channelID: String,
        teamID: String,
        rootID: String? = nil
    ) async throws -> MattermostCommandResponse {
        try await httpClient.post(
            "/commands/execute",
            body: MattermostCommandExecuteRequest(command: command, channelID: channelID, teamID: teamID, rootID: rootID)
        )
    }

    /// Command and argument suggestions for the composer text
    /// (`GET /teams/{team_id}/commands/autocomplete_suggestions`).
    ///
    /// - Parameter userInput: The composer text, including the leading `/`.
    public func commandAutocompleteSuggestions(
        userInput: String,
        teamID: String,
        channelID: String,
        rootID: String? = nil
    ) async throws -> [MattermostCommandSuggestion] {
        var query = [
            URLQueryItem(name: "user_input", value: userInput),
            URLQueryItem(name: "channel_id", value: channelID),
        ]
        if let rootID { query.append(URLQueryItem(name: "root_id", value: rootID)) }
        return try await httpClient.get("/teams/\(teamID)/commands/autocomplete_suggestions", queryItems: query)
    }
}

/// Response of `POST /commands/execute`.
public struct MattermostCommandResponse: Codable, Equatable, Sendable {
    /// `ephemeral` or `in_channel`.
    public let responseType: String?
    public let text: String?
    /// A URL the client should open (a permalink or an external page).
    public let gotoLocation: String?
    /// Set when the command may open an interactive dialog.
    public let triggerID: String?

    public init(responseType: String? = nil, text: String? = nil, gotoLocation: String? = nil, triggerID: String? = nil) {
        self.responseType = responseType
        self.text = text
        self.gotoLocation = gotoLocation
        self.triggerID = triggerID
    }

    enum CodingKeys: String, CodingKey {
        case responseType
        case text
        case gotoLocation
        case triggerID = "triggerId"
    }
}

/// One entry of `GET /teams/{team_id}/commands/autocomplete_suggestions`.
public struct MattermostCommandSuggestion: Codable, Equatable, Sendable {
    /// The command text up to and including this suggestion, without the leading `/`.
    public let complete: String
    /// The word this suggestion completes.
    public let suggestion: String
    public let hint: String
    public let description: String

    public init(complete: String, suggestion: String, hint: String = "", description: String = "") {
        self.complete = complete
        self.suggestion = suggestion
        self.hint = hint
        self.description = description
    }

    // The server sends Go field names verbatim.
    enum CodingKeys: String, CodingKey {
        case complete = "Complete"
        case suggestion = "Suggestion"
        case hint = "Hint"
        case description = "Description"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        complete = try container.decode(String.self, forKey: .complete)
        suggestion = try container.decodeIfPresent(String.self, forKey: .suggestion) ?? ""
        hint = try container.decodeIfPresent(String.self, forKey: .hint) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

struct MattermostCommandExecuteRequest: Encodable, Sendable {
    let command: String
    let channelID: String
    let teamID: String
    let rootID: String?

    enum CodingKeys: String, CodingKey {
        case command
        case channelID = "channelId"
        case teamID = "teamId"
        case rootID = "rootId"
    }
}
