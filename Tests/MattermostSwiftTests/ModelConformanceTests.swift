import Foundation
import Testing
@testable import MattermostSwift

private func requireHashable<T: Hashable>(_: T.Type) {}

private func expectHashableValueSemantics<T: Hashable>(
    _ first: T,
    equals second: T
) {
    #expect(first == second)
    #expect(Set([first, second]).count == 1)
    var dictionary = [first: "first"]
    dictionary[second] = "second"
    #expect(dictionary.count == 1)
    #expect(dictionary[first] == "second")
}

private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

@Test
func issue72ListedModelsConformToHashable() {
    requireHashable(MattermostChannel.self)
    requireHashable(MattermostPost.self)
    requireHashable(MattermostUser.self)
    requireHashable(MattermostTeam.self)
    requireHashable(MattermostTimelineTarget.self)
    requireHashable(MattermostSidebarCategory.self)
    requireHashable(MattermostThreadResponse.self)
    requireHashable(MattermostFileInfo.self)
    requireHashable(MattermostReaction.self)
    requireHashable(MattermostCustomEmoji.self)
    requireHashable(MattermostCachedUserSnapshot.self)
    requireHashable(MattermostCachedChannelSnapshot.self)
    requireHashable(MattermostCachedPostSnapshot.self)
    requireHashable(MattermostPostMetadata.self)
    requireHashable(MattermostJSONValue.self)
}

@Test
func issue72ListedPublicModelsWorkInHashBasedCollections() throws {
    let values = [
        """
        {"id":"channel-1","name":"town-square","displayName":"Town Square","type":"O"}
        """,
        """
        {
          "id":"post-1","createAt":1,"updateAt":1,"editAt":0,"deleteAt":0,
          "userId":"user-1","channelId":"channel-1","rootId":"",
          "message":"hello","type":"","props":{"priority":"important"}
        }
        """,
        """
        {"id":"user-1","username":"alice","timezone":{"useAutomaticTimezone":"true"}}
        """,
        """
        {"id":"team-1","name":"engineering","displayName":"Engineering"}
        """,
        """
        {
          "id":"category-1","displayName":"Favorites","type":"custom",
          "channelIds":["channel-1"]
        }
        """,
        """
        {"id":"thread-1","replyCount":2,"participants":[]}
        """,
        """
        {"id":"file-1","name":"report.pdf","extension":"pdf"}
        """,
        """
        {"userId":"user-1","postId":"post-1","emojiName":"tada","createAt":1}
        """,
        """
        {"id":"emoji-1","name":"party_parrot"}
        """,
    ]

    let channel = try decode(MattermostChannel.self, from: values[0])
    expectHashableValueSemantics(
        channel,
        equals: try decode(MattermostChannel.self, from: values[0])
    )

    let post = try decode(MattermostPost.self, from: values[1])
    expectHashableValueSemantics(
        post,
        equals: try decode(MattermostPost.self, from: values[1])
    )

    let user = try decode(MattermostUser.self, from: values[2])
    expectHashableValueSemantics(
        user,
        equals: try decode(MattermostUser.self, from: values[2])
    )

    let team = try decode(MattermostTeam.self, from: values[3])
    expectHashableValueSemantics(
        team,
        equals: try decode(MattermostTeam.self, from: values[3])
    )

    let target = MattermostTimelineTarget.channel(id: channel.id)
    expectHashableValueSemantics(
        target,
        equals: MattermostTimelineTarget.channel(id: channel.id)
    )

    let category = try decode(MattermostSidebarCategory.self, from: values[4])
    expectHashableValueSemantics(
        category,
        equals: try decode(MattermostSidebarCategory.self, from: values[4])
    )

    let thread = try decode(MattermostThreadResponse.self, from: values[5])
    expectHashableValueSemantics(
        thread,
        equals: try decode(MattermostThreadResponse.self, from: values[5])
    )

    let file = try decode(MattermostFileInfo.self, from: values[6])
    expectHashableValueSemantics(
        file,
        equals: try decode(MattermostFileInfo.self, from: values[6])
    )

    let reaction = try decode(MattermostReaction.self, from: values[7])
    expectHashableValueSemantics(
        reaction,
        equals: try decode(MattermostReaction.self, from: values[7])
    )

    let emoji = try decode(MattermostCustomEmoji.self, from: values[8])
    expectHashableValueSemantics(
        emoji,
        equals: try decode(MattermostCustomEmoji.self, from: values[8])
    )
}

@MainActor
@Test
func issue72CachedSnapshotsWorkInHashBasedCollections() throws {
    let store = try MattermostStore(inMemory: true)
    let user = try decode(
        MattermostUser.self,
        from: """
        {"id":"user-1","username":"alice"}
        """
    )
    let channel = try decode(
        MattermostChannel.self,
        from: """
        {"id":"channel-1","name":"town-square","displayName":"Town Square","type":"O"}
        """
    )
    let post = MattermostPost(
        id: "post-1",
        createAt: 1,
        updateAt: 1,
        editAt: 0,
        deleteAt: 0,
        userId: user.id,
        channelId: channel.id,
        rootId: "",
        originalId: nil,
        message: "hello",
        type: .standard,
        hashtags: nil,
        pendingPostId: nil,
        fileIds: nil,
        hasReactions: nil,
        props: ["nested": .object(["enabled": .bool(true)])]
    )

    try store.upsert(user: user)
    try store.upsert(channel: channel)
    try store.upsert(post: post)
    try store.save()

    let firstUser = try #require(try store.cachedUserSnapshots().first)
    let secondUser = try #require(try store.cachedUserSnapshots().first)
    expectHashableValueSemantics(firstUser, equals: secondUser)

    let firstChannel = try #require(try store.cachedChannelSnapshots().first)
    let secondChannel = try #require(try store.cachedChannelSnapshots().first)
    expectHashableValueSemantics(firstChannel, equals: secondChannel)

    let firstPost = try #require(
        try store.cachedPostSnapshots(channelID: channel.id).first
    )
    let secondPost = try #require(
        try store.cachedPostSnapshots(channelID: channel.id).first
    )
    expectHashableValueSemantics(firstPost, equals: secondPost)
}

@Test
func issue72LiveSyncEventsHaveEquatableValueSemantics() {
    let connecting = MattermostLiveSyncEvent.connecting(attempt: 2)
    #expect(connecting == .connecting(attempt: 2))
    #expect(connecting != .connecting(attempt: 3))

    let failure = MattermostLiveSyncFailure(
        attempt: 2,
        domain: NSURLErrorDomain,
        code: NSURLErrorNotConnectedToInternet,
        message: "offline"
    )
    #expect(
        MattermostLiveSyncEvent.backfillFailed(failure)
            == .backfillFailed(failure)
    )
    #expect(
        MattermostLiveSyncEvent.backfillFailed(failure)
            != .backfillFailed(.init(
                attempt: 3,
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet,
                message: "offline"
            ))
    )
}
