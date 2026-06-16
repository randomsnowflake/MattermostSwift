# MattermostSwift

Build Mattermost clients in Swift with REST commands, WebSocket live events, and SwiftData-backed cache sync.

## Overview

`MattermostSwift` is a single-account SDK for a Mattermost server. It keeps credentials outside the package, exposes high-level services for app code, and leaves UI concerns to host apps.

Use `MattermostClient` as the root entry point, then choose focused service facades for user, team, channel, post, timeline, sync, and live-event work.

## Authenticate

Use a personal access token when a host app already owns credential storage:

```swift
import Foundation
import MattermostSwift

let serverURL = URL(string: "https://mattermost.example.com")!
let client = try MattermostClient(
    serverURL: serverURL,
    token: "personal-access-token"
)

let me = try await client.currentUser()
```

Probe server health and client-visible capabilities through the server service:

```swift
let server = try await client.serverService().info()
print(server.ping.status)
print(server.clientConfig.buildNumber ?? "unknown build")

let teams = try await client.teamService().joinedTeams()
print(teams.first?.displayName ?? "no joined teams")
if let team = teams.first {
    let members = try await client.teamService().members(teamID: team.id, perPage: 20)
    print(members.count)
}
```

For username/password deployments, ask Mattermost for a session token and let the host app decide whether to store it:

```swift
let session = try await MattermostClient.login(
    serverURL: serverURL,
    loginID: "user@example.com",
    password: "password"
)

let client = try session.client(serverURL: serverURL)
print(session.tokenSource)
```

`MattermostSession.tokenSource` reports whether Mattermost returned the documented `Token` response header or the browser-compatible `MMAUTHTOKEN` cookie. The login request sends Mattermost's web-client `X-Requested-With: XMLHttpRequest` header so deployments that attach browser session cookies can be handled without storing the password in the SDK.

## Hydrate Local Cache

Create a `MattermostStore` on the main actor and run a bounded sync pass:

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

`MattermostSyncService` stores joined teams, the current user, status, joined channels, memberships, unread counts, sidebar categories, and optional channel timelines. Cursor-based follow-up syncs use Mattermost's `since` timestamp query where possible. Per-channel notification settings are available as `MattermostChannelNotifyProps`, which exposes common Mattermost keys and keeps unknown server keys intact.

## Work With Timelines

Use `MattermostTimelineService` for both channel timelines and thread timelines:

```swift
@MainActor
func loadTimeline(
    client: MattermostClient,
    store: MattermostStore,
    channelID: String,
    rootPostID: String
) async throws {
    let timelines = client.timelineService()

    let channelPage = try await timelines.load(
        .channel(id: channelID),
        request: MattermostTimelineRequest(perPage: 40)
    )

    let threadPage = try await timelines.load(
        .thread(rootPostID: rootPostID),
        request: MattermostTimelineRequest(perPage: 40)
    )

    _ = try await timelines.sync(.channel(id: channelID), to: store)
    let cachedChannelPosts = try timelines.cachedPosts(.channel(id: channelID), in: store)
    let visibleCachedPosts = try timelines.cachedPosts(.channel(id: channelID), in: store, includeDeleted: false)

    print(channelPage.posts.count)
    print(threadPage.posts.count)
    print(cachedChannelPosts.count)
    print(visibleCachedPosts.count)
}
```

The timeline target owns the cache scope, so host apps do not need to invent cursor keys. Cached timelines keep deleted-post tombstones for sync correctness, including deletes recovered later through cursor backfill; pass `includeDeleted: false` for normal visible message lists.

## Maintain Live State

`MattermostLiveSyncService` combines WebSocket events with REST backfill and applies updates into `MattermostStore`:

```swift
@MainActor
func runLiveSync(
    client: MattermostClient,
    store: MattermostStore,
    channelIDs: [String]
) async throws {
    let stream = client.liveSyncService().events(
        to: store,
        options: MattermostLiveSyncOptions(
            channelIDs: channelIDs,
            maxBackfillChannels: channelIDs.count
        )
    )

    for try await event in stream {
        if let state = event.connectionState {
            print("live sync state: \(state)")
        }

        switch event {
        case .eventApplied(_, let typedEvent):
            print("applied \(typedEvent)")
        case .channelUnreadRefreshed(let unread):
            print("unread \(unread.channelId): \(unread.msgCount)")
        case .backfillFailed(let failure):
            print("live sync backfill failed on attempt \(failure.attempt): \(failure.message)")
        default:
            break
        }
    }
}
```

For small workspaces or an explicit catch-up action, set `backfillAllJoinedChannelPosts` to `true` to sweep every joined channel during connect and reconnect backfill:

```swift
let options = MattermostLiveSyncOptions(
    backfillAllJoinedChannelPosts: true
)
```

The CLI includes live reconnect checks for this path: `reconnect-backfill-test` proves cursor-based missed-post recovery directly through REST sync, `live-sync-reconnect-test` drives `MattermostLiveSyncService` through a reconnect lifecycle while verifying the second backfill returns and caches a post created while disconnected, and `all-channel-reconnect-test` repeats that reconnect proof with `backfillAllJoinedChannelPosts` enabled.

## Keep Secrets Outside The SDK

The SDK does not write credentials to Keychain or local storage. Host apps should provide tokens at startup, store credentials according to their own security model, and avoid logging token values.
