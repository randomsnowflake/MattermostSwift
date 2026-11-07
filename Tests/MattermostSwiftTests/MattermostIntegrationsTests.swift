import Foundation
import Testing
@testable import MattermostSwift

@Suite(.serialized)
struct MattermostIntegrationsTests {
    @Test
    func messageAttachmentsDecodeEveryFieldTolerantly() throws {
        let post = try mattermostSnakeCaseDecoder.decode(MattermostPost.self, from: Data(#"""
        {"id":"p","create_at":1,"update_at":1,"edit_at":0,"delete_at":0,"user_id":"u","channel_id":"c",
         "root_id":"","message":"","type":"slack_attachment","props":{"attachments":[
          {"fallback":"fb","color":"#2D9CDB","pretext":"pre","author_name":"CI","author_link":"https://a",
           "author_icon":"https://i","title":"T","title_link":"https://t","text":"**hi**",
           "fields":[{"title":"Count","value":42,"short":true},{"title":"Long","value":"v"}],
           "image_url":"https://img","thumb_url":"https://th","footer":"f","footer_icon":"https://fi",
           "actions":[
            {"id":"booked","type":"button","name":"Booked","style":"success"},
            {"id":"pick","type":"select","name":"Pick","default_option":"b","data_source":"",
             "options":[{"text":"A","value":"a"},{"text":"B","value":"b"},{"text":"broken"}]},
            {"id":"who","type":"select","name":"Who","data_source":"users","disabled":true,"cookie":"ck"},
            {"name":"no id is skipped"}]},
          "not an object",
          {"text":"second"}]}}
        """#.utf8))

        let attachments = post.messageAttachments
        #expect(attachments.count == 2)
        let card = try #require(attachments.first)
        #expect(card.color == "#2D9CDB")
        #expect(card.authorName == "CI")
        #expect(card.titleLink == "https://t")
        #expect(card.fields == [
            .init(title: "Count", value: "42", isShort: true),
            .init(title: "Long", value: "v", isShort: false),
        ])
        #expect(card.imageURL == "https://img")
        #expect(card.thumbURL == "https://th")
        #expect(card.footerIcon == "https://fi")
        #expect(card.actions.map(\.id) == ["booked", "pick", "who"])
        #expect(card.actions[0].kind == .button)
        #expect(card.actions[0].style == "success")
        #expect(card.actions[1].kind == .select)
        #expect(card.actions[1].dataSource == nil)
        #expect(card.actions[1].defaultOption == "b")
        #expect(card.actions[1].options == [.init(text: "A", value: "a"), .init(text: "B", value: "b")])
        #expect(card.actions[2].dataSource == "users")
        #expect(card.actions[2].isDisabled)
        #expect(card.actions[2].cookie == "ck")
        #expect(attachments[1].text == "second")
    }

    @Test
    func postWithoutAttachmentsHasNone() {
        let post = MattermostPost(
            id: "p", createAt: 1, updateAt: 1, editAt: 0, deleteAt: 0, userID: "u", channelID: "c",
            rootID: "", originalID: nil, message: "hi", type: .standard, hashtags: nil,
            pendingPostID: nil, fileIDs: nil, hasReactions: nil, props: ["attachments": .string("junk")]
        )
        #expect(post.messageAttachments.isEmpty)
    }

    @Test
    func doPostActionSendsSelectedOptionAndCookie() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/posts/post-id/actions/pick")
            #expect(request.httpMethod == "POST")
            let body = try JSONSerialization.jsonObject(with: try MattermostTestSupport.bodyData(from: request)) as? [String: Any]
            #expect(body?["selected_option"] as? String == "cherry")
            #expect(body?["cookie"] as? String == "ck")
            let reply = #"{"status":"OK","trigger_id":"trig","goto_location":"https://example.com"}"#
            return try MattermostTestSupport.response(statusCode: 200, body: Data(reply.utf8), contentType: "application/json", request: request)
        }

        let response = try await client.doPostAction(postID: "post-id", actionID: "pick", selectedOption: "cherry", cookie: "ck")

        #expect(response == MattermostPostActionResponse(status: "OK", triggerID: "trig", gotoLocation: "https://example.com"))
    }

    @Test
    func submitDialogKeepsElementNamesVerbatim() async throws {
        let client = try await Self.makeClient { request in
            #expect(request.url?.absoluteString == "https://mattermost.example.com/api/v4/actions/dialogs/submit")
            let body = try JSONSerialization.jsonObject(with: try MattermostTestSupport.bodyData(from: request)) as? [String: Any]
            #expect(body?["callback_id"] as? String == "cb")
            #expect(body?["channel_id"] as? String == "c")
            #expect(body?["cancelled"] as? Bool == false)
            let submission = body?["submission"] as? [String: Any]
            #expect(submission?["supplierName"] as? String == "Acme")
            #expect(submission?["is_damaged"] as? Bool == true)
            let reply = #"{"errors":{"supplierName":"Too short"}}"#
            return try MattermostTestSupport.response(statusCode: 200, body: Data(reply.utf8), contentType: "application/json", request: request)
        }

        let response = try await client.submitDialog(MattermostDialogSubmission(
            url: "http://bot/dialog", callbackID: "cb", state: "s", userID: "u", channelID: "c", teamID: "t",
            submission: ["supplierName": .string("Acme"), "is_damaged": .bool(true)]
        ))

        #expect(response.errors == ["supplierName": "Too short"])
        #expect(!response.isAccepted)
    }

    @Test
    func submitDialogAcceptsAnEmptyBody() async throws {
        let client = try await Self.makeClient { request in
            try MattermostTestSupport.response(statusCode: 200, body: Data(), contentType: "application/json", request: request)
        }

        let response = try await client.submitDialog(MattermostDialogSubmission(
            url: "u", callbackID: "cb", state: "", userID: "u", channelID: "c", teamID: "t", submission: [:], cancelled: true
        ))

        #expect(response.isAccepted)
    }

    @Test
    func ephemeralAndOpenDialogEventsAreTyped() throws {
        let post = #"{\"id\":\"e\",\"create_at\":1,\"update_at\":1,\"edit_at\":0,\"delete_at\":0,\"user_id\":\"u\",\"channel_id\":\"c\",\"root_id\":\"r\",\"message\":\"Only you\",\"type\":\"system_ephemeral\"}"#
        let ephemeral = try mattermostSnakeCaseDecoder.decode(MattermostLiveEvent.self, from: Data("""
        {"event":"ephemeral_message","data":{"post":"\(post)"},"broadcast":{"user_id":"u"},"seq":3}
        """.utf8))
        guard case .ephemeralMessage(let decoded) = try ephemeral.typedEvent() else {
            Issue.record("expected ephemeral message")
            return
        }
        #expect(decoded.message == "Only you")
        #expect(decoded.type == .systemEphemeral)
        #expect(decoded.rootID == "r")

        let dialog = #"{\"trigger_id\":\"t\",\"url\":\"http://bot/dialog\",\"dialog\":{\"callback_id\":\"cb\",\"title\":\"Report\",\"introduction_text\":\"Intro\",\"submit_label\":\"Send\",\"notify_on_cancel\":true,\"state\":\"st\",\"elements\":[{\"display_name\":\"Pallets\",\"name\":\"pallet_count\",\"type\":\"text\",\"subtype\":\"number\",\"default\":\"12\",\"min_length\":1,\"max_length\":3,\"optional\":false},{\"display_name\":\"Outcome\",\"name\":\"outcome\",\"type\":\"radio\",\"options\":[{\"text\":\"Booked\",\"value\":\"booked\"}]},{\"display_name\":\"Who\",\"name\":\"who\",\"type\":\"select\",\"data_source\":\"users\",\"optional\":true}]}}"#
        let open = try mattermostSnakeCaseDecoder.decode(MattermostLiveEvent.self, from: Data("""
        {"event":"open_dialog","data":{"dialog":"\(dialog)"},"broadcast":{"user_id":"u"},"seq":4}
        """.utf8))
        guard case .openDialog(let request) = try open.typedEvent() else {
            Issue.record("expected open dialog")
            return
        }
        #expect(request.triggerID == "t")
        #expect(request.url == "http://bot/dialog")
        #expect(request.dialog.callbackID == "cb")
        #expect(request.dialog.notifyOnCancel)
        #expect(request.dialog.state == "st")
        #expect(request.dialog.elements.map(\.name) == ["pallet_count", "outcome", "who"])
        #expect(request.dialog.elements[0].subtype == "number")
        #expect(request.dialog.elements[0].defaultValue == "12")
        #expect(request.dialog.elements[0].maxLength == 3)
        #expect(request.dialog.elements[1].options == [.init(text: "Booked", value: "booked")])
        #expect(request.dialog.elements[2].dataSource == "users")
        #expect(request.dialog.elements[2].isOptional)
    }

    private static func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async throws -> MattermostClient {
        try MattermostClient(
            serverURL: try #require(URL(string: "https://mattermost.example.com")),
            token: "token",
            urlSession: await MattermostTestSupport.urlSession(handler: handler)
        )
    }
}

@MainActor
@Test
func storeNeverCachesEphemeralPostsFromEditsOrDeletes() throws {
    let store = try MattermostStore(inMemory: true)
    let post = #"{\"id\":\"e\",\"create_at\":0,\"update_at\":2,\"edit_at\":0,\"delete_at\":2,\"user_id\":\"u\",\"channel_id\":\"\",\"root_id\":\"\",\"message\":\"\",\"type\":\"system_ephemeral\"}"#
    for name in ["post_edited", "post_deleted"] {
        let event = try mattermostSnakeCaseDecoder.decode(MattermostLiveEvent.self, from: Data("""
        {"event":"\(name)","data":{"post":"\(post)"},"broadcast":{"user_id":"u"},"seq":1}
        """.utf8))
        #expect(try store.applyReportingMutation(liveEvent: event).mutatesStore == false)
    }
    #expect(try store.cachedPost(id: "e") == nil)
}
