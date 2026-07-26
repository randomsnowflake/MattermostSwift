# Pagination

Load bounded collections and post history without skipping or duplicating results.

## Iterate Page-Based Collections

Most list endpoints use zero-based `page` and a `perPage` count. Increment the page until the
server returns fewer items than requested:

```swift
func loadAllPublicChannels(
    client: MattermostClient,
    teamID: String
) async throws -> [MattermostChannel] {
    let pageSize = 100
    var page = 0
    var channels: [MattermostChannel] = []

    while true {
        let batch = try await client.publicChannels(
            teamID: teamID,
            page: page,
            perPage: pageSize
        )
        channels.append(contentsOf: batch)

        guard batch.count == pageSize else {
            return channels
        }
        page += 1
    }
}
```

The SDK clamps negative page values to zero and `perPage` to at least one. Mattermost currently
caps paged API responses at 200 items, so callers should still stop based on the returned count
rather than assuming the requested size was honored.

## Page Through Channel Posts

``MattermostPostList/orderedPosts`` follows the server's `order` array. Use it instead of
iterating the `posts` dictionary:

```swift
let pageSize = 60
var page = 0

while true {
    let list = try await client.posts(
        channelID: channelID,
        page: page,
        perPage: pageSize
    )

    for post in list.orderedPosts {
        print(post.message)
    }

    guard list.orderedPosts.count == pageSize else {
        break
    }
    page += 1
}
```

For a history window anchored on a post, `before` loads older posts and `after` loads newer posts.
When Mattermost supplies cursor IDs, `prevPostId` is the anchor toward older history and
`nextPostId` is the anchor toward newer history:

```swift
let current = try await client.posts(
    channelID: channelID,
    before: anchorPostID
)

if let olderAnchor = current.prevPostId, !olderAnchor.isEmpty {
    let older = try await client.posts(
        channelID: channelID,
        before: olderAnchor
    )
    print(older.orderedPosts.count)
}
```

`hasNext`, `nextPostId`, and `prevPostId` are optional response metadata. Mattermost doesn't emit
`hasNext` consistently for every post-list endpoint or server version. When present, it indicates
that the response has more results in its own pagination mode; it doesn't choose the older or
newer direction. `nextPostId` describes the newer direction rather than “the next older page.”
Use returned cursor IDs for anchored navigation and returned item counts for ordinary numbered
pagination.

## Fetch Incremental Post Changes

The `since` path isn't another numbered page. It asks Mattermost for posts created or modified at
or after a server timestamp in milliseconds:

```swift
let changes = try await client.postsSince(
    channelID: channelID,
    since: lastSuccessfulSyncAt
)
```

Passing `since` to `posts(channelID:page:perPage:since:...)` takes the same fork and ignores
`page`, `perPage`, `before`, and `after`. Don't combine those modes.

Mattermost caps a `since` response at 1,000 posts. For cache synchronization, prefer
``MattermostClient/syncChannelPosts(channelID:to:perPage:maxPages:)``: it detects saturation,
falls back to bounded history, and refuses to advance the cursor when the configured history bound
can't prove completeness. This direct helper stages data and its cursor but doesn't call
``MattermostStore/save()``; save after it succeeds.

## See Also

- ``MattermostPostList``
- ``MattermostTimelineRequest``
- <doc:Caching>
