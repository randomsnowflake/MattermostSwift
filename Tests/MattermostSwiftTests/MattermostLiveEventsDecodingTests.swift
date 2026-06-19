import Foundation
import Testing
@testable import MattermostSwift

@Test
func liveEventDecodesCoreFieldsAndBroadcast() throws {
    let json = """
    {
      "event": "typing",
      "data": {
        "user_id": "user-1",
        "parent_id": "root-1"
      },
      "broadcast": {
        "omit_users": null,
        "user_id": "user-1",
        "channel_id": "channel-1",
        "team_id": "team-1"
      },
      "seq": 7
    }
    """

    let event = try mattermostSnakeCaseDecoder.decode(
        MattermostLiveEvent.self,
        from: Data(json.utf8)
    )

    #expect(event.event == "typing")
    #expect(event.seq == 7)
    #expect(event.name == .typing)
    // convertFromSnakeCase only rewrites keys backed by CodingKeys, NOT the
    // free-form `data` dictionary, so its keys stay verbatim (snake_case).
    #expect(event.stringData("user_id") == "user-1")
    #expect(event.anyString("user_id", "userId") == "user-1")
    #expect(event.broadcast?.channelId == "channel-1")
    #expect(event.broadcast?.teamId == "team-1")

    // anyString falls back to broadcast metadata when data is absent.
    let typing = try #require(event.decodedTyping())
    #expect(typing.userID == "user-1")
    #expect(typing.channelID == "channel-1")
    #expect(typing.parentID == "root-1")
}

@Test
func liveBroadcastDecodesOmitUsersAndToleratesMissingKeys() throws {
    let json = """
    {
      "omit_users": ["a", "b"],
      "channel_id": "channel-9"
    }
    """

    let broadcast = try mattermostSnakeCaseDecoder.decode(
        MattermostLiveBroadcast.self,
        from: Data(json.utf8)
    )

    #expect(broadcast.omitUsers == ["a", "b"])
    #expect(broadcast.channelId == "channel-9")
    #expect(broadcast.userId == nil)
    #expect(broadcast.teamId == nil)
}

@Test
func liveBroadcastToleratesUnexpectedFieldTypes() throws {
    let json = """
    {
      "omit_users": "a",
      "user_id": true,
      "channel_id": 42,
      "team_id": null
    }
    """

    let broadcast = try mattermostSnakeCaseDecoder.decode(
        MattermostLiveBroadcast.self,
        from: Data(json.utf8)
    )

    #expect(broadcast.omitUsers == ["a"])
    #expect(broadcast.userId == nil)
    #expect(broadcast.channelId == nil)
    #expect(broadcast.teamId == nil)
}

@Test
func liveBroadcastDecodesWithPlainDecoder() throws {
    let json = """
    {
      "omit_users": ["a"],
      "user_id": "user-1",
      "channel_id": "channel-1",
      "team_id": "team-1"
    }
    """

    let broadcast = try JSONDecoder().decode(MattermostLiveBroadcast.self, from: Data(json.utf8))

    #expect(broadcast.omitUsers == ["a"])
    #expect(broadcast.userId == "user-1")
    #expect(broadcast.channelId == "channel-1")
    #expect(broadcast.teamId == "team-1")
}

@Test
func jsonValueDecodesMixedTypes() throws {
    let json = """
    {
      "text": "hello",
      "count": 42,
      "flag": true,
      "missing": null,
      "tags": ["x", 1, false],
      "nested": { "key": "value" }
    }
    """

    let decoded = try mattermostSnakeCaseDecoder.decode(
        [String: MattermostJSONValue].self,
        from: Data(json.utf8)
    )

    #expect(decoded["text"]?.stringValue == "hello")
    #expect(decoded["count"]?.int64Value == 42)
    #expect(decoded["flag"]?.boolValue == true)
    #expect(decoded["missing"] == .null)
    #expect(decoded["tags"] == .array([.string("x"), .number(1), .bool(false)]))
    #expect(decoded["nested"] == .object(["key": .string("value")]))
}

@Test
func typedEventMapsHelloAndCacheInvalidation() throws {
    let helloJSON = """
    { "event": "hello", "data": {}, "seq": 0 }
    """
    let hello = try mattermostSnakeCaseDecoder.decode(
        MattermostLiveEvent.self,
        from: Data(helloJSON.utf8)
    )
    #expect(try hello.typedEvent() == .hello)

    let postUnreadJSON = """
    {
      "event": "post_unread",
      "data": { "channel_id": "channel-1", "post_id": "post-1" },
      "broadcast": { "user_id": "user-1", "team_id": "team-1" },
      "seq": 3
    }
    """
    let postUnread = try mattermostSnakeCaseDecoder.decode(
        MattermostLiveEvent.self,
        from: Data(postUnreadJSON.utf8)
    )
    let expected = MattermostCacheInvalidationEvent(
        event: "post_unread",
        userID: "user-1",
        channelID: "channel-1",
        teamID: "team-1",
        postID: "post-1"
    )
    #expect(try postUnread.typedEvent() == .postUnread(expected))
}

@Test
func typedEventMapsUnknownNamesWithoutThrowing() throws {
    let event = MattermostLiveEvent(
        event: "some_future_event",
        data: ["value": .number(1)],
        broadcast: nil,
        seq: 10
    )

    #expect(try event.typedEvent() == .unknown(event))
}

@Test
func webSocketEnvelopeToleratesWrongTypedFields() throws {
    let json = """
    {
      "event": "typing",
      "data": "not an object",
      "broadcast": {
        "channel_id": 42
      }
    }
    """

    let envelope = try mattermostSnakeCaseDecoder.decode(
        MattermostWebSocketEnvelope.self,
        from: Data(json.utf8)
    )
    let event = try #require(envelope.liveEvent)

    #expect(event.event == "typing")
    #expect(event.data == [:])
    #expect(event.broadcast?.channelId == nil)
}
