import Foundation
import Testing
@testable import MattermostSwift

// Decoding coverage for the domain-split model files.

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
        "timezone": {"useAutomaticTimezone": "true"}
    }
    """
    let user = try JSONDecoder().decode(MattermostUser.self, from: Data(payload.utf8))
    #expect(user.id == "user123")
    #expect(user.username == "jdoe")
    #expect(user.email == "jdoe@example.com")
    #expect(user.firstName == "Jane")
    #expect(user.timezone?["useAutomaticTimezone"] == "true")
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
    #expect(channel.type == "O")
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
        "type": ""
    }
    """
    let post = try JSONDecoder().decode(MattermostPost.self, from: Data(payload.utf8))
    #expect(post.id == "post123")
    #expect(post.message == "hello world")
    #expect(post.isRootPost == true)
    #expect(post.isEdited == true)
    #expect(post.isDeleted == false)
    #expect(post.cacheTimestamp == 300)
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
    #expect(category.type == "custom")
    #expect(category.isCustom == true)
    #expect(category.channelIds == ["chan1", "chan2"])
}

@Test
func decodesMattermostChannelStatsWithServerKeys() throws {
    let payload = """
    {
        "channelId": "chan123",
        "memberCount": 42,
        "guestCount": 3,
        "pinnedpostCount": 5,
        "totalMsgCount": 1000
    }
    """
    let stats = try JSONDecoder().decode(MattermostChannelStats.self, from: Data(payload.utf8))
    #expect(stats.channelId == "chan123")
    #expect(stats.memberCount == 42)
    #expect(stats.guestCount == 3)
    #expect(stats.pinnedPostCount == 5)
    #expect(stats.totalMessageCount == 1000)
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
