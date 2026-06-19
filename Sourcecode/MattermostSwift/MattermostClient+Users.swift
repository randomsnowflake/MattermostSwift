import Foundation

// MARK: - Users

extension MattermostClient {
    /// Loads the authenticated user.
    public func currentUser() async throws -> MattermostUser {
        try await httpClient.get("/users/me")
    }

    /// Checks whether a login id requires a TOTP MFA code.
    public static func checkMFARequired(
        serverURL: URL,
        loginID: String,
        urlSession: URLSession = .mattermost
    ) async throws -> Bool {
        let configuration = try MattermostConfiguration(
            serverURL: serverURL,
            authentication: .none
        )
        let httpClient = MattermostHTTPClient(configuration: configuration, urlSession: urlSession)
        let response: MattermostMFARequired = try await httpClient.post(
            "/users/mfa",
            body: MattermostMFARequiredRequest(loginId: loginID)
        )
        return response.mfaRequired
    }

    /// Loads a user by id. Pass `"me"` for the authenticated user.
    public func user(id: String) async throws -> MattermostUser {
        try await httpClient.get("/users/\(id)")
    }

    /// Updates editable profile fields for a user. Pass `"me"` for the authenticated user.
    public func updateUser(id: String, patch: MattermostUserPatch) async throws -> MattermostUser {
        try await httpClient.put("/users/\(id)/patch", body: patch)
    }

    /// Updates a user's password. `currentPassword` is required when changing your own password.
    @discardableResult
    public func changePassword(
        userID: String,
        currentPassword: String? = nil,
        newPassword: String
    ) async throws -> MattermostStatusOK {
        try await httpClient.put(
            "/users/\(userID)/password",
            body: MattermostPasswordUpdateRequest(currentPassword: currentPassword, newPassword: newPassword)
        )
    }

    /// Generates the TOTP MFA secret and QR code payload for a user.
    public func generateMFA(userID: String) async throws -> MattermostMFASecret {
        try await httpClient.post("/users/\(userID)/mfa/generate")
    }

    /// Activates or deactivates TOTP MFA for a user.
    @discardableResult
    public func activateMFA(
        userID: String,
        code: String? = nil,
        activate: Bool
    ) async throws -> MattermostStatusOK {
        try await httpClient.put(
            "/users/\(userID)/mfa",
            body: MattermostMFAUpdateRequest(activate: activate, code: code)
        )
    }

    /// Downloads a user's current profile image. Pass `"me"` for the authenticated user.
    public func userProfileImage(userID: String = "me") async throws -> Data {
        try await httpClient.data("/users/\(userID)/image")
    }

    /// Updates a user's profile image with raw image bytes.
    @discardableResult
    public func updateUserProfileImage(
        userID: String,
        data: Data,
        contentType: String = "application/octet-stream"
    ) async throws -> MattermostStatusOK {
        try await httpClient.multipart(
            "/users/\(userID)/image",
            method: "PUT",
            parts: [
                MattermostMultipartPart(
                    name: "image",
                    filename: "profile-image",
                    contentType: contentType,
                    data: data
                ),
            ]
        )
    }

    /// Downloads the generated default profile image for a user id.
    public func defaultUserProfileImage(userID: String) async throws -> Data {
        try await httpClient.data("/users/\(userID)/image/default")
    }

    /// Loads users by id in one request.
    public func users(ids: [String]) async throws -> [MattermostUser] {
        try await httpClient.post("/users/ids", body: ids)
    }

    /// Loads users by username in one request.
    public func users(usernames: [String]) async throws -> [MattermostUser] {
        try await httpClient.post("/users/usernames", body: usernames)
    }

    /// Lists users who are members of a channel.
    public func users(channelID: String, page: Int = 0, perPage: Int = 60) async throws -> [MattermostUser] {
        try await httpClient.get(
            "/users",
            queryItems: [
                URLQueryItem(name: "in_channel", value: channelID),
            ] + Self.pageQueryItems(page: page, perPage: perPage)
        )
    }

    /// Searches users by username, full name, nickname, or email where the server permits it.
    public func searchUsers(
        term: String,
        teamID: String? = nil,
        notInTeamID: String? = nil,
        inChannelID: String? = nil,
        notInChannelID: String? = nil,
        allowInactive: Bool = false,
        withoutTeam: Bool = false,
        limit: Int = 20
    ) async throws -> [MattermostUser] {
        try await httpClient.post(
            "/users/search",
            body: MattermostUserSearchRequest(
                term: term,
                teamId: teamID,
                notInTeamId: notInTeamID,
                inChannelId: inChannelID,
                notInChannelId: notInChannelID,
                allowInactive: allowInactive,
                withoutTeam: withoutTeam,
                limit: limit
            )
        )
    }

    /// Autocompletes users for composer/member pickers.
    public func autocompleteUsers(
        name: String,
        teamID: String? = nil,
        channelID: String? = nil,
        limit: Int = 20
    ) async throws -> MattermostUserAutocomplete {
        var queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "limit", value: String(Self.clampedPerPage(limit))),
        ]
        if let teamID, !teamID.isEmpty {
            queryItems.append(URLQueryItem(name: "team_id", value: teamID))
        }
        if let channelID, !channelID.isEmpty {
            queryItems.append(URLQueryItem(name: "channel_id", value: channelID))
        }

        return try await httpClient.get("/users/autocomplete", queryItems: queryItems)
    }

    /// Loads IDs of users with any known relationship to the authenticated user.
    public func knownUserIDs() async throws -> [String] {
        try await httpClient.get("/users/known")
    }

    /// Loads a single user's presence status.
    public func status(userID: String) async throws -> MattermostUserStatus {
        try await httpClient.get("/users/\(userID)/status")
    }

    /// Loads presence statuses for multiple users.
    public func statuses(userIDs: [String]) async throws -> [MattermostUserStatus] {
        try await httpClient.post("/users/status/ids", body: userIDs)
    }

    /// Manually sets a user's presence status.
    public func setStatus(userID: String, status: String, dndEndTime: Int64? = nil) async throws -> MattermostUserStatus {
        try await httpClient.put(
            "/users/\(userID)/status",
            body: MattermostUserStatusUpdateRequest(
                userId: userID,
                status: status,
                dndEndTime: dndEndTime
            )
        )
    }

    /// Sets the authenticated user's custom status text and emoji.
    @discardableResult
    public func setCustomStatus(_ customStatus: MattermostCustomStatus) async throws -> MattermostStatusOK {
        try await httpClient.put("/users/me/status/custom", body: customStatus)
    }

    /// Clears the authenticated user's custom status.
    @discardableResult
    public func clearCustomStatus() async throws -> MattermostStatusOK {
        try await httpClient.delete("/users/me/status/custom")
    }

    /// Lists active sessions for a user. Sensitive fields may be sanitized by the server.
    public func sessions(userID: String) async throws -> [MattermostUserSession] {
        try await httpClient.get("/users/\(userID)/sessions")
    }

    /// Revokes one active session for a user.
    @discardableResult
    public func revokeSession(userID: String, sessionID: String) async throws -> MattermostStatusOK {
        try await httpClient.post(
            "/users/\(userID)/sessions/revoke",
            body: MattermostSessionRevokeRequest(sessionId: sessionID)
        )
    }

    /// Revokes all active sessions for a user.
    @discardableResult
    public func revokeAllSessions(userID: String) async throws -> MattermostStatusOK {
        try await httpClient.post("/users/\(userID)/sessions/revoke/all")
    }

    /// Attaches a mobile device token to the current session for push notifications.
    @discardableResult
    public func attachMobileDevice(deviceID: String) async throws -> MattermostStatusOK {
        try await httpClient.put(
            "/users/sessions/device",
            body: MattermostMobileDeviceRequest(deviceId: deviceID)
        )
    }

    /// Removes a mobile device token from the current session for push notifications.
    @discardableResult
    public func detachMobileDevice(deviceID: String) async throws -> MattermostStatusOK {
        try await httpClient.delete(
            "/users/sessions/device",
            body: MattermostMobileDeviceRequest(deviceId: deviceID)
        )
    }
}
