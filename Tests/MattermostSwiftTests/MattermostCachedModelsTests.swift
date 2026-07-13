import Foundation
import Testing
@testable import MattermostSwift

@MainActor
@Test
func cachedUserRoundTripsThroughStore() throws {
    let store = try MattermostStore(inMemory: true)
    let user = MattermostUser(
        id: "user-1",
        username: "alice",
        email: "alice@example.com",
        firstName: "Alice",
        lastName: "Anderson",
        nickname: "al",
        position: "Engineer",
        locale: "en",
        timezone: nil,
        lastPictureUpdate: 1_700_000_000_000
    )

    let cached = try store.upsert(user: user)
    try store.save()

    let fetched = try #require(try store.cachedUser(id: "user-1"))
    #expect(cached.id == fetched.id)
    #expect(fetched.username == "alice")
    #expect(fetched.email == "alice@example.com")
    #expect(fetched.firstName == "Alice")
    #expect(fetched.lastName == "Anderson")
    #expect(fetched.nickname == "al")
    #expect(fetched.position == "Engineer")
    #expect(fetched.locale == "en")
    #expect(fetched.lastPictureUpdate == 1_700_000_000_000)
}

@MainActor
@Test
func cachedReactionAndFileRoundTripThroughStore() throws {
    let store = try MattermostStore(inMemory: true)
    let reaction = MattermostReaction(
        userId: "user-1",
        postId: "post-1",
        emojiName: "tada",
        createAt: 999
    )
    let file = MattermostFileInfo(
        id: "file-1",
        userId: "user-1",
        postId: "post-1",
        createAt: 100,
        updateAt: 101,
        deleteAt: 0,
        name: "report.pdf",
        extensionName: "pdf",
        size: 2048,
        mimeType: "application/pdf",
        width: nil,
        height: nil,
        hasPreviewImage: false
    )

    try store.upsert(reaction: reaction)
    try store.upsert(file: file)
    try store.save()

    let reactionID = MattermostCachedReaction.cacheID(
        userID: "user-1",
        postID: "post-1",
        emojiName: "tada"
    )
    #expect(reactionID == "post-1:user-1:tada")

    let cachedReaction = try #require(try store.cachedReaction(id: reactionID))
    #expect(cachedReaction.emojiName == "tada")
    #expect(cachedReaction.createAt == 999)

    let cachedFile = try #require(try store.cachedFile(id: "file-1"))
    #expect(cachedFile.name == "report.pdf")
    #expect(cachedFile.extensionName == "pdf")
    #expect(cachedFile.size == 2048)
    #expect(cachedFile.mimeType == "application/pdf")
    #expect(try store.cachedFiles(postID: "post-1").map(\.id) == ["file-1"])
}

@MainActor
@Test
func cachedSyncCursorUpdatesInPlace() throws {
    let store = try MattermostStore(inMemory: true)

    let inserted = try store.setSyncCursor(scope: "team:t1", lastSyncAt: 10, lastItemID: "a")
    #expect(inserted.scope == "team:t1")

    try store.setSyncCursor(scope: "team:t1", lastSyncAt: 42, lastItemID: "b")
    try store.save()

    let cursor = try #require(try store.cachedSyncCursor(scope: "team:t1"))
    #expect(cursor.lastSyncAt == 42)
    #expect(cursor.lastItemID == "b")
}

@MainActor
@Test
func cachedSidebarCategoryRoundTripsThroughStore() throws {
    let store = try MattermostStore(inMemory: true)
    let categoryJSON = """
    {
      "id": "category-1",
      "user_id": "user-1",
      "team_id": "team-1",
      "display_name": "Favorites",
      "type": "favorites",
      "sort_order": 5,
      "channel_ids": ["channel-1", "channel-2"],
      "sorting": "recent",
      "muted": false,
      "collapsed": true
    }
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let category = try decoder.decode(MattermostSidebarCategory.self, from: Data(categoryJSON.utf8))

    try store.upsert(sidebarCategory: category)
    try store.save()

    let cached = try #require(try store.cachedSidebarCategory(id: "category-1"))
    #expect(cached.displayName == "Favorites")
    #expect(cached.type == "favorites")
    #expect(cached.sortOrder == 5)
    #expect(cached.channelIds == ["channel-1", "channel-2"])
    #expect(cached.collapsed == true)
    #expect(try store.cachedSidebarCategories(teamID: "team-1").map(\.id) == ["category-1"])
}
