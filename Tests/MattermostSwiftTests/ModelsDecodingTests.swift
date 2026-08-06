import Foundation
import Testing
@testable import MattermostSwift

// Decoding coverage for the domain-split model files.

@Test
func domainValueWrappersExposeKnownMattermostValues() {
    #expect(MattermostChannelType.open.rawValue == "O")
    #expect(MattermostChannelType.private.rawValue == "P")
    #expect(MattermostChannelType.direct.rawValue == "D")
    #expect(MattermostChannelType.group.rawValue == "G")
    #expect(MattermostUserStatusValue.online.rawValue == "online")
    #expect(MattermostUserStatusValue.away.rawValue == "away")
    #expect(MattermostUserStatusValue.dnd.rawValue == "dnd")
    #expect(MattermostUserStatusValue.offline.rawValue == "offline")
    #expect(MattermostPostType.standard.rawValue.isEmpty)
    #expect(MattermostSidebarCategoryType.custom.rawValue == "custom")
    #expect(MattermostSidebarCategorySorting.manual.rawValue == "manual")
}

@Test
func domainValueWrappersPreserveUnknownValuesThroughCodableRoundTrips() throws {
    try expectStringCodableRoundTrip(
        MattermostChannelType.self,
        rawValue: "future_channel_type"
    )
    try expectStringCodableRoundTrip(
        MattermostUserStatusValue.self,
        rawValue: "future_user_status"
    )
    try expectStringCodableRoundTrip(
        MattermostPostType.self,
        rawValue: "future_post_type"
    )
    try expectStringCodableRoundTrip(
        MattermostSidebarCategoryType.self,
        rawValue: "future_category_type"
    )
    try expectStringCodableRoundTrip(
        MattermostSidebarCategorySorting.self,
        rawValue: "future_category_sorting"
    )
}

private func expectStringCodableRoundTrip<Value>(
    _ type: Value.Type,
    rawValue: String
) throws where Value: Codable & Equatable & RawRepresentable, Value.RawValue == String {
    let source = Data("\"\(rawValue)\"".utf8)
    let decoded = try JSONDecoder().decode(type, from: source)
    #expect(decoded.rawValue == rawValue)
    #expect(try JSONEncoder().encode(decoded) == source)
}

@Test
func decodesMattermostUser() throws {
    // MattermostUser has no custom CodingKeys, so the payload uses its exact
    // property names (camelCase) rather than the server's snake_case form.
    let payload = """
    {
        "id": "user123",
        "username": "jdoe",
        "email": "jdoe@example.com",
        "firstName": "Jane",
        "timezone": {"useAutomaticTimezone": "true"},
        "lastPictureUpdate": 1700000000000,
        "notifyProps": {
            "mentionKeys": "jdoe, @jdoe, release train",
            "channel": "true",
            "firstName": "false"
        }
    }
    """
    let user = try JSONDecoder().decode(MattermostUser.self, from: Data(payload.utf8))
    #expect(user.id == "user123")
    #expect(user.username == "jdoe")
    #expect(user.email == "jdoe@example.com")
    #expect(user.firstName == "Jane")
    #expect(user.timezone?["useAutomaticTimezone"] == "true")
    #expect(user.lastPictureUpdate == 1_700_000_000_000)
    #expect(user.notifyProps?.parsedMentionKeys == ["jdoe", "@jdoe", "release train"])
    #expect(user.notifyProps?.includesChannelMentions == true)
    #expect(user.notifyProps?.includesFirstName == false)
}

@Test
func decodesMattermostUserNotifyPropsFromSnakeCase() throws {
    let payload = """
    {
        "id": "user123",
        "username": "jdoe",
        "notify_props": {
            "mention_keys": "jdoe,@jdoe, incident ",
            "channel": "false",
            "first_name": "true"
        }
    }
    """

    let user = try mattermostSnakeCaseDecoder.decode(MattermostUser.self, from: Data(payload.utf8))

    #expect(user.notifyProps?.parsedMentionKeys == ["jdoe", "@jdoe", "incident"])
    #expect(user.notifyProps?.includesChannelMentions == false)
    #expect(user.notifyProps?.includesFirstName == true)
}

@Test
func decodesMattermostUserLastPictureUpdateFromSnakeCase() throws {
    // The production decoder converts the server's `last_picture_update`
    // snake_case key to `lastPictureUpdate` via `.convertFromSnakeCase`.
    let payload = """
    {
        "id": "user123",
        "username": "jdoe",
        "last_picture_update": 1700000000000
    }
    """
    let user = try mattermostSnakeCaseDecoder.decode(MattermostUser.self, from: Data(payload.utf8))
    #expect(user.id == "user123")
    #expect(user.lastPictureUpdate == 1_700_000_000_000)
}

@Test
func decodesMattermostUserWithoutLastPictureUpdateAsNil() throws {
    // Servers that omit the field (or older versions) decode as nil because
    // the optional property uses `decodeIfPresent`.
    let payload = """
    {
        "id": "user123",
        "username": "jdoe"
    }
    """
    let user = try mattermostSnakeCaseDecoder.decode(MattermostUser.self, from: Data(payload.utf8))
    #expect(user.lastPictureUpdate == nil)
}

@Test
func decodesMattermostChannelAndComputedProps() throws {
    let payload = """
    {
        "id": "chan123",
        "createAt": 1000,
        "updateAt": 2000,
        "teamId": "team1",
        "name": "town-square",
        "displayName": "Town Square",
        "type": "O",
        "deleteAt": 0
    }
    """
    let channel = try JSONDecoder().decode(MattermostChannel.self, from: Data(payload.utf8))
    #expect(channel.id == "chan123")
    #expect(channel.name == "town-square")
    #expect(channel.displayName == "Town Square")
    #expect(channel.type == .open)
    #expect(channel.isDeleted == false)
    #expect(channel.cacheTimestamp == 2000)
}

@Test
func decodesMattermostPostAndComputedProps() throws {
    let payload = """
    {
        "id": "post123",
        "createAt": 100,
        "updateAt": 200,
        "editAt": 300,
        "deleteAt": 0,
        "userId": "user123",
        "channelId": "chan123",
        "rootId": "",
        "message": "hello world",
        "type": "",
        "replyCount": 4,
        "lastReplyAt": 500,
        "isFollowing": true
    }
    """
    let post = try JSONDecoder().decode(MattermostPost.self, from: Data(payload.utf8))
    #expect(post.id == "post123")
    #expect(post.message == "hello world")
    #expect(post.type == .standard)
    #expect(post.isRootPost == true)
    #expect(post.isEdited == true)
    #expect(post.isDeleted == false)
    #expect(post.cacheTimestamp == 300)
    #expect(post.replyCount == 4)
    #expect(post.lastReplyAt == 500)
    #expect(post.isFollowing == true)
    #expect(post.metadata == nil)
}

@Test
func decodesMattermostPostEmbeddedMetadata() throws {
    let payload = """
    {
        "id": "post123",
        "createAt": 100,
        "updateAt": 200,
        "editAt": 0,
        "deleteAt": 0,
        "userId": "user123",
        "channelId": "chan123",
        "rootId": "",
        "message": "with files",
        "type": "",
        "metadata": {
            "files": [
                {"id": "file1", "name": "report.pdf", "extension": "pdf", "size": 1024, "mimeType": "application/pdf"}
            ],
            "reactions": [
                {"userId": "user123", "postId": "post123", "emojiName": "thumbsup", "createAt": 100}
            ]
        }
    }
    """
    let post = try JSONDecoder().decode(MattermostPost.self, from: Data(payload.utf8))
    #expect(post.metadata?.files?.count == 1)
    #expect(post.metadata?.files?.first?.name == "report.pdf")
    #expect(post.metadata?.files?.first?.extensionName == "pdf")
    #expect(post.metadata?.reactions?.count == 1)
    #expect(post.metadata?.reactions?.first?.emojiName == "thumbsup")
    // The raw metadata dictionary stays available alongside the typed view.
    #expect(post.rawMetadata?["files"] != nil)
}

@Test
func decodesMattermostPostWithMalformedMetadataAsNil() throws {
    // Malformed embedded metadata must never fail post decoding.
    let payload = """
    {
        "id": "post123",
        "createAt": 100,
        "updateAt": 200,
        "editAt": 0,
        "deleteAt": 0,
        "userId": "user123",
        "channelId": "chan123",
        "rootId": "",
        "message": "bad metadata",
        "type": "",
        "metadata": {
            "files": [{"name": 42}]
        }
    }
    """
    let post = try JSONDecoder().decode(MattermostPost.self, from: Data(payload.utf8))
    #expect(post.id == "post123")
    #expect(post.metadata == nil)
}

@Test
func decodesMattermostSidebarCategory() throws {
    let payload = """
    {
        "id": "cat123",
        "userId": "user123",
        "teamId": "team1",
        "displayName": "Favorites",
        "type": "custom",
        "channelIds": ["chan1", "chan2"]
    }
    """
    let category = try JSONDecoder().decode(MattermostSidebarCategory.self, from: Data(payload.utf8))
    #expect(category.id == "cat123")
    #expect(category.displayName == "Favorites")
    #expect(category.type == .custom)
    #expect(category.isCustom == true)
    #expect(category.channelIDs == ["chan1", "chan2"])
}

@Test
func decodesMattermostChannelStatsWithServerKeys() throws {
    let payload = """
    {
        "channel_id": "chan123",
        "member_count": 42,
        "guest_count": 3,
        "pinnedpost_count": 5,
        "total_msg_count": 1000
    }
    """
    let stats = try mattermostSnakeCaseDecoder.decode(MattermostChannelStats.self, from: Data(payload.utf8))
    #expect(stats.channelID == "chan123")
    #expect(stats.memberCount == 42)
    #expect(stats.guestCount == 3)
    #expect(stats.pinnedPostCount == 5)
    #expect(stats.totalMessageCount == 1000)
}

@Test
func decodesChannelRootUnreadCounters() throws {
    // Decode via the production snake_case decoder so the test reflects real
    // wire data from CRT-enabled servers.
    let payload = """
    {
        "id": "chan123",
        "team_id": "team1",
        "name": "town-square",
        "display_name": "Town Square",
        "type": "O",
        "total_msg_count": 1000,
        "total_msg_count_root": 400,
        "last_post_at": 5000,
        "last_root_post_at": 4800
    }
    """
    let channel = try mattermostSnakeCaseDecoder.decode(MattermostChannel.self, from: Data(payload.utf8))
    #expect(channel.id == "chan123")
    #expect(channel.totalMsgCount == 1000)
    #expect(channel.totalMsgCountRoot == 400)
    #expect(channel.lastPostAt == 5000)
    #expect(channel.lastRootPostAt == 4800)
}

@Test
func decodesChannelMemberRootCounters() throws {
    let payload = """
    {
        "channel_id": "chan123",
        "user_id": "user123",
        "msg_count": 100,
        "mention_count": 3,
        "msg_count_root": 40,
        "mention_count_root": 1
    }
    """
    let member = try mattermostSnakeCaseDecoder.decode(MattermostChannelMember.self, from: Data(payload.utf8))
    #expect(member.channelID == "chan123")
    #expect(member.userID == "user123")
    #expect(member.msgCount == 100)
    #expect(member.mentionCount == 3)
    #expect(member.msgCountRoot == 40)
    #expect(member.mentionCountRoot == 1)
}

@Test
func mattermostUserSessionDescriptionRedactsToken() throws {
    let payload = """
    {
      "id": "session-1",
      "user_id": "user-1",
      "expires_at": 12345,
      "token": "super-secret-token"
    }
    """
    let session = try mattermostSnakeCaseDecoder.decode(MattermostUserSession.self, from: Data(payload.utf8))

    #expect(session.token == "super-secret-token")
    #expect(String(describing: session).contains("super-secret-token") == false)
    #expect(String(reflecting: session).contains("super-secret-token") == false)
}

@Test
func decodesMattermostServerPingWithCustomKeys() throws {
    let payload = """
    {
        "status": "OK",
        "ActiveSearchBackend": "database",
        "AndroidLatestVersion": "2.0.0"
    }
    """
    let ping = try JSONDecoder().decode(MattermostServerPing.self, from: Data(payload.utf8))
    #expect(ping.status == "OK")
    #expect(ping.activeSearchBackend == "database")
    #expect(ping.androidLatestVersion == "2.0.0")
}

@Test
func decodesMattermostServerPingWithDriftedKeyCasingAndSeparators() throws {
    let payload = """
    {
        "STATUS": "OK",
        "active_search_backend": "database",
        "DATABASESTATUS": "OK",
        "file_store_status": "OK",
        "IOSLatestVersion": "2.0.0",
        "ios_min_version": "1.0.0",
        "ANDROIDLATESTVERSION": "3.0.0",
        "android_min_version": "2.0.0"
    }
    """
    let ping = try JSONDecoder().decode(MattermostServerPing.self, from: Data(payload.utf8))

    #expect(ping.status == "OK")
    #expect(ping.activeSearchBackend == "database")
    #expect(ping.databaseStatus == "OK")
    #expect(ping.filestoreStatus == "OK")
    #expect(ping.iosLatestVersion == "2.0.0")
    #expect(ping.iosMinVersion == "1.0.0")
    #expect(ping.androidLatestVersion == "3.0.0")
    #expect(ping.androidMinVersion == "2.0.0")
}

@Test
func decodesMattermostClientConfigWithDriftedKeyCasingAndSeparators() throws {
    let payload = """
    {
        "build_number": "100",
        "BUILDHASH": "abc123",
        "build_date": "2026-07-25",
        "BUILD_ENTERPRISE_READY": "true",
        "collapsed_threads": "true",
        "ENABLEFILE": "true",
        "enable_file_attachments": "true",
        "ENABLECUSTOMEMOJI": "true",
        "enable_incoming_webhooks": "true",
        "ENABLEOUTGOINGWEBHOOKS": "true",
        "enable_post_username_override": "true",
        "ENABLEPOSTICONOVERRIDE": "true",
        "site_name": "Mattermost"
    }
    """
    let config = try JSONDecoder().decode(MattermostClientConfig.self, from: Data(payload.utf8))

    #expect(config.buildNumber == "100")
    #expect(config.buildHash == "abc123")
    #expect(config.buildDate == "2026-07-25")
    #expect(config.buildEnterpriseReady == "true")
    #expect(config.collapsedThreads == "true")
    #expect(config.enableFile == "true")
    #expect(config.enableFileAttachments == "true")
    #expect(config.enableCustomEmoji == "true")
    #expect(config.enableIncomingWebhooks == "true")
    #expect(config.enableOutgoingWebhooks == "true")
    #expect(config.enablePostUsernameOverride == "true")
    #expect(config.enablePostIconOverride == "true")
    #expect(config.siteName == "Mattermost")
}
