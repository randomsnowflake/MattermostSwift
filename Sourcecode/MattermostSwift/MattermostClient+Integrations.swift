import Foundation

// MARK: - Interactive messages and dialogs

extension MattermostClient {
    /// Runs a message-attachment button or select menu (`POST /posts/{post_id}/actions/{action_id}`).
    ///
    /// The server forwards the click to the integration. Its answer arrives separately: a
    /// `post_edited` event when it updates the post, an `ephemeral_message` event for a private
    /// reply, and an `open_dialog` event when it opens an interactive dialog.
    ///
    /// - Parameters:
    ///   - selectedOption: The chosen value for select menus (a user or channel id for dynamic menus).
    ///   - cookie: ``MattermostPostAction/cookie`` for actions on ephemeral posts.
    @discardableResult
    public func doPostAction(
        postID: String,
        actionID: String,
        selectedOption: String? = nil,
        cookie: String? = nil
    ) async throws -> MattermostPostActionResponse {
        try await httpClient.post(
            "/posts/\(postID)/actions/\(actionID)",
            body: MattermostPostActionRequest(selectedOption: selectedOption, cookie: cookie)
        )
    }

    /// Submits (or, with `cancelled`, cancels) an interactive dialog (`POST /actions/dialogs/submit`).
    ///
    /// A returned ``MattermostDialogSubmissionResponse`` with errors means the integration rejected
    /// the input; keep the dialog open and show them.
    public func submitDialog(_ submission: MattermostDialogSubmission) async throws -> MattermostDialogSubmissionResponse {
        // Plain coders: element names are integration data and must keep their exact spelling.
        let data = try await httpClient.postPlainJSON("/actions/dialogs/submit", body: submission)
        guard !data.isEmpty else { return MattermostDialogSubmissionResponse() }
        return try mattermostPlainDecoder.decode(MattermostDialogSubmissionResponse.self, from: data)
    }
}
