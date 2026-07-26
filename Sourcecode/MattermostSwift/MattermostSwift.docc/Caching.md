# Caching

Hydrate, read, reconcile, and maintain Mattermost state with SwiftData.

## Create and Hydrate a Store

``MattermostStore`` and every managed model it returns are main-actor isolated:

```swift
@MainActor
func hydrate(client: MattermostClient, storeURL: URL) async throws {
    let store = try MattermostStore(url: storeURL)

    let result = try await client.syncService().sync(
        to: store,
        teamName: "engineering",
        options: MattermostSyncOptions(
            postPageSize: 60,
            maxPostPages: 2,
            includeChannelUsers: true,
            includeSidebarCategories: true,
            refreshUnreadForAllJoinedChannels: true
        )
    )

    print(result.cachedTeamsCount)
    print(result.cachedChannelsCount)
}
```

The high-level sync service persists before it returns. Direct store mutations only stage changes
in the model context, so save them explicitly:

```swift
@MainActor
func cache(_ users: [MattermostUser], in store: MattermostStore) throws {
    try store.upsert(users: users)
    try store.save()
}
```

Direct ``MattermostClient/syncChannelPosts(channelID:to:perPage:maxPages:)`` also stages its
post and cursor updates without saving. A channel-target
``MattermostClient/syncTimeline(_:to:request:maxPages:)`` delegates to that helper and likewise
requires a following save; its thread-target path saves before returning. The full sync service
and live sync save at their documented boundaries.

## Choose the Right Mutation

Use `upsert` for partial or paginated responses. It inserts or updates the objects present and
never treats omissions as deletions.

Use `replace` and `reconcile` only with complete, authoritative responses:

- ``MattermostStore/replaceJoinedChannels(_:teamID:)`` removes omitted channel rows and their
  local content inside one team.
- ``MattermostStore/replaceChannelMembers(_:userID:teamID:)`` removes omitted memberships for
  one user among cached channels in one team.
- ``MattermostStore/replaceSidebarCategories(_:userID:teamID:)`` removes omitted categories for
  one user and team.
- ``MattermostStore/reconcileChannelUnreads(userID:teamID:channelIDs:)`` removes unread rows whose
  channels aren't in the supplied authoritative set.

An empty collection is meaningful to these scoped APIs and clears the named scope. Never pass a
partial page to them.

## Handle Tombstones

Channel and post deletes are retained as timestamped tombstones so delayed REST pages or live
events can't resurrect stale content. Readers default to hiding tombstones:

```swift
let visible = try store.cachedPosts(
    channelID: channelID,
    includeDeleted: false
)
let reconciliationView = try store.cachedPosts(
    channelID: channelID,
    includeDeleted: true
)
```

The same `includeDeleted` contract applies to cached channel, thread, timeline, and snapshot
readers. Single-post lookup intentionally returns a tombstone; inspect
``MattermostCachedPost/isDeleted``.

``MattermostStore/deleteChannelContent(channelID:)`` and
``MattermostStore/prunePosts(channelID:keepCount:)`` permanently remove cache content. They are
retention helpers, not tombstone operations.

## Cross Actor Boundaries

Don't pass SwiftData-managed cache models to another actor. Read immutable `Sendable` values with
``MattermostStore/cachedUserSnapshots()``,
``MattermostStore/cachedChannelSnapshots(teamID:includeDeleted:)``, or
``MattermostStore/cachedPostSnapshots(channelID:limit:includeDeleted:)``.

## See Also

- <doc:LiveSync>
- <doc:Pagination>
- ``MattermostSyncService``
