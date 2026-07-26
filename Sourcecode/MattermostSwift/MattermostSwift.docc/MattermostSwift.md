# MattermostSwift

Build Mattermost clients in Swift with REST commands, WebSocket live events, and a
SwiftData-backed cache.

## Overview

``MattermostClient`` is the root entry point for a single Mattermost server and account. Start
with token or password-session authentication, call its user, team, channel, post, and timeline
operations, then add ``MattermostSyncService`` and ``MattermostLiveSyncService`` when an app needs
offline state.

The SDK doesn't store credentials or provide UI. Host apps own secure token storage, presentation,
and cache retention.

The library supports iOS 18, macOS 15, tvOS 18, watchOS 11, and visionOS 2. Linux is not currently
supported because the cache uses SwiftData and live events use the Apple Foundation WebSocket
transport.

Public response models used by the command-line and persistence workflows conform to
`Codable`. Use `JSONEncoder` to persist complete values—including post newlines, props,
metadata, and preference values—and the package's normal decoder configuration when
reading server-shaped snake-case payloads.

## Authenticate

### Essentials

- ``MattermostClient``
- <doc:Pagination>
- <doc:ErrorHandling>
- ``MattermostTimelineTarget``
- ``MattermostTimelineRequest``
- ``MattermostTimelinePage``

### Authentication

- <doc:Authentication>
- ``MattermostConfiguration``
- ``MattermostAuthentication``
- ``MattermostSession``
- ``MattermostSessionTokenSource``

### Models

- ``MattermostUser``
- ``MattermostTeam``
- ``MattermostChannel``
- ``MattermostPost``
- ``MattermostPostList``
- ``MattermostThreadResponse``
- ``MattermostFileInfo``
- ``MattermostReaction``

### Caching

- <doc:Caching>
- ``MattermostStore``
- ``MattermostSyncService``
- ``MattermostSyncOptions``
- ``MattermostCachedUserSnapshot``
- ``MattermostCachedChannelSnapshot``
- ``MattermostCachedPostSnapshot``

### Live Events

let client = try session.client()
print(session.tokenSource)

// Attempt remote server-session cleanup before discarding the local token.
try await client.logoutCurrentSession()
```

`MattermostSession.tokenSource` reports whether Mattermost returned the documented `Token` response header or the browser-compatible `MMAUTHTOKEN` cookie. The login request sends Mattermost's web-client `X-Requested-With: XMLHttpRequest` header so deployments that attach browser session cookies can be handled without storing the password in the SDK.

The textual and debug descriptions of `MattermostSession`, `MattermostAuthentication`, and `MattermostConfiguration` redact bearer tokens. Hosts must still store returned tokens securely and avoid logging the `token` property directly.
`logoutCurrentSession()` is best-effort remote cleanup for password-login sessions; discard the
local token even if it fails, and do not expect a personal access token to be accepted.
For a trusted HTTP-only development server, pass `allowInsecureHTTP: true` to login and MFA
checks. Hosts can inspect `MattermostConfiguration.usesInsecureHTTP` to present their own warning;
the library does not print to standard error.

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

`MattermostSyncService` stores joined teams, the current user, status, joined channels, memberships, unread counts, sidebar categories, and optional channel timelines. It persists scoped ETags for joined-team, joined-channel, and sidebar-category lists, sends `If-None-Match` on later syncs, and returns the ordered cached list when the server replies `304 Not Modified`. Post timelines and unread counts remain unconditional. When `includeChannelUsers` is enabled for a selected timeline channel, every channel-user profile page is fetched and cached. Cursor-based follow-up post syncs use Mattermost's `since` timestamp query where possible. Per-channel notification settings are available as `MattermostChannelNotifyProps`, which exposes common Mattermost keys and keeps unknown server keys intact.

All `MattermostStore` operations use `ModelContainer.mainContext` and are main-actor isolated.
That contract also covers sync and live-sync cache writes, cached fetches, `prunePosts`, and
`deleteChannelContent`; the package has no background model context. Network requests suspend
normally, but SwiftData work resumes on the main actor, so large caches can produce a visible UI
hitch. Schedule large sync and retention passes only during an app-controlled idle window where
that tradeoff is acceptable.

Host apps own retention policy. A reasonable starting cadence is to prune retained channels after
initial hydration and then about once per day during an idle window. Delete a channel's cached
content when it leaves the app's retention scope. To use cached values from another actor, create
immutable `Sendable` values with `cachedUserSnapshots()`, `cachedChannelSnapshots()`, or
`cachedPostSnapshots(...)`; snapshots do not move store access itself off the main actor.
`cachedPostSnapshots(...)` copies props and metadata as `propsJSON` and `metadataJSON` without
decoding every post. Consumers that need those payloads can call the snapshot's throwing
`decodedProps()` and `decodedMetadata()` helpers on demand.

## Work With Timelines

Use the client's timeline methods for both channel timelines and thread timelines:

```swift
@MainActor
func loadTimeline(
    client: MattermostClient,
    store: MattermostStore,
    channelID: String,
    rootPostID: String
) async throws {
    let channelPage = try await client.timeline(
        .channel(id: channelID),
        request: MattermostTimelineRequest(perPage: 40)
    )

    let threadPage = try await client.timeline(
        .thread(rootPostID: rootPostID),
        request: MattermostTimelineRequest(perPage: 40)
    )

    if let lastReply = threadPage.posts.max(by: { $0.createAt < $1.createAt }) {
        try await client.markThreadRead(
            teamID: "team-id",
            threadID: rootPostID,
            upTo: lastReply.createdAt
        )
    }

    _ = try await client.syncTimeline(.channel(id: channelID), to: store)
    let cachedChannelPosts = try store.cachedTimeline(.channel(id: channelID))
    let visibleCachedPosts = try store.cachedTimeline(.channel(id: channelID), includeDeleted: false)

    print(channelPage.posts.count)
    print(threadPage.posts.count)
    print(cachedChannelPosts.count)
    print(visibleCachedPosts.count)
}
```

The timeline target owns the cache scope, so host apps do not need to invent cursor keys. Cached timelines keep deleted-post tombstones for sync correctness, including deletes recovered later through cursor backfill; pass `includeDeleted: false` for normal visible message lists.

Use `markThreadRead(teamID:threadID:upTo:)` with a `Date`, or the raw `timestamp:` overload with
Mattermost milliseconds, to clear a followed thread's unread state. Convert other server values
with `Date(mattermostMilliseconds:)` and `Date.mattermostMilliseconds`.

For direct endpoint loading, use `MattermostPostsOptions`, `MattermostUserSearchOptions`,
`MattermostChannelSearchOptions`, and `MattermostThreadOptions`. Setting
`MattermostPostsOptions.since` intentionally ignores page, per-page, before, and after options.
To walk channel history lazily without hand-written cursor loops:

```swift
for try await post in client.allPosts(channelID: channelID, pageSize: 100) {
    print(post.message)
}
```

Collapsed-Reply-Threads (CRT) clients compute channel unread from root counts: `MattermostChannel.totalMsgCountRoot` and `MattermostChannelMember.msgCountRoot`/`mentionCountRoot` (also on `MattermostChannelUnread`) surface the server's `_root` counters, so channel unread is `totalMsgCountRoot − msgCountRoot` with `mentionCountRoot` for the channel mention badge. Call `viewChannel(channelID:collapsedThreadsSupported: true)` so marking a channel viewed does not auto-read its threads.

## Maintain Live State

Default live-event streams use a dedicated long-lived `URLSession` so the bounded HTTP
resource timeout does not recycle healthy WebSockets. If you inject a custom REST session,
provide `webSocketURLSession` to `MattermostClient` when live events need a different policy.

Use `lifecycleEvents()` when the host needs transport diagnostics as well as raw events.
Undecodable event frames yield `MattermostLiveEventStreamLifecycleEvent.eventDecodeFailed`
with structured failure details, then the stream continues reading from the same connection.

Deployments that require custom server-trust evaluation can pass a `URLSessionDelegate` to the
client. The SDK installs it on both default sessions, so the same pinning policy protects REST
bearer headers and the WebSocket authentication challenge:

```swift
let trustDelegate = EnterpriseMattermostTrustDelegate()
let client = try MattermostClient(
    serverURL: serverURL,
    token: token,
    urlSessionDelegate: trustDelegate
)
```

Implement the delegate's URL authentication-challenge method to evaluate `serverTrust` according
to your deployment's policy. Do not disable normal trust validation. If you provide
`urlSession` or `webSocketURLSession` explicitly, configure that session with its delegate before
passing it to the client. `URLSession.mattermost(delegate:)` and
`URLSession.mattermostLiveEvents(delegate:)` expose the same hook for callers that construct
sessions directly.

Mattermost API failures preserve the server's structured error body:

```swift
do {
    _ = try await client.currentUser()
} catch let error as MattermostError where error.isUnauthorized {
    // Present authentication UI.
} catch MattermostError.httpStatus(_, _, let apiError) {
    print("Mattermost error: \(apiError?.id ?? "unknown")")
    print("Request ID: \(apiError?.requestId ?? "unknown")")
}
```

Use `isForbidden` and `isNotFound` for the other common status branches. The attached
``MattermostAPIErrorBody`` also exposes `detailedError` and the status code reported in the
response body.

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
        case .eventApplyFailed(let rawEvent, let message):
            print("skipped \(rawEvent.event): \(message)")
        case .channelUnreadRefreshed(let unread):
            print("unread \(unread.channelID): \(unread.msgCount)")
        case .channelUnreadRefreshFailed(let failure),
             .sidebarCategoriesRefreshFailed(let failure),
             .threadStateRefreshFailed(let failure):
            print("live sync refresh failed on attempt \(failure.attempt): \(failure.message)")
        case .backfillFailed(let failure):
            print("live sync backfill failed on attempt \(failure.attempt): \(failure.message)")
            print("error identity: \(failure.domain) \(failure.code)")
            if failure.mattermostError?.isUnauthorized == true {
                // Present authentication UI.
            }
        default:
            break
        }
    }
}
```

The first connection always runs the REST backfill. By default, a reconnect only runs it when the
socket was disconnected for at least 10 seconds, so a brief radio or network flap does not trigger
the full request fan-out. Hosts can tune the threshold or disable reconnect filtering:

```swift
let tuned = MattermostLiveSyncOptions(
    minimumBackfillGap: .seconds(30)
)

let alwaysBackfill = MattermostLiveSyncOptions(
    minimumBackfillGap: nil
)
```

When a reconnect skips backfill, live sync emits `.connected` after the socket confirms the
connection so `connectionState` still leaves its recovering phase.

Live sync refreshes every affected channel after `channel_viewed`,
`multiple_channels_viewed`, and `post_unread` invalidations when the corresponding unread-refresh
options are enabled. This keeps cached channel badges aligned with reads from other sessions and
devices, including servers with collapsed reply threads enabled.

Malformed embedded event payloads yield `eventApplyFailed` and are skipped so later WebSocket
events continue to update the cache. Unread, sidebar-category, and thread-state refresh errors yield
their dedicated failure events. These non-cancellation failures degrade only the affected update;
cancellation continues to stop live sync.

Reconnects use full-jitter exponential backoff. For each attempt, the stream chooses a uniform
delay from zero through the policy's capped exponential base, spreading clients across the retry
window after a shared server or network outage.

For small workspaces or an explicit catch-up action, set `backfillAllJoinedChannelPosts` to `true` to sweep every joined channel during connect and reconnect backfill:

```swift
let options = MattermostLiveSyncOptions(
    backfillAllJoinedChannelPosts: true
)
```

The CLI includes live reconnect checks for this path under `diag`:
`diag reconnect-backfill-test` proves cursor-based missed-post recovery directly through
REST sync, `diag live-sync-reconnect-test` drives `MattermostLiveSyncService` through a
reconnect lifecycle while verifying the second backfill returns and caches a post
created while disconnected, and `diag all-channel-reconnect-test` repeats that reconnect
proof with `backfillAllJoinedChannelPosts` enabled.

### Stop live sync while backgrounded

The host owns live-sync lifetime. Cancel the task consuming `events(to:...)` when its scene enters
the background, then create a new stream and task when the scene becomes active. Cancellation
stops refresh/backfill and reconnect work and closes the WebSocket. Starting again runs the normal
connect-time backfill before live events resume.

In SwiftUI, use `scenePhase` as the identity of a `.task(id:)` and return immediately unless the
phase is `.active`; SwiftUI cancels the old consuming task when the phase changes. UIKit and AppKit
hosts should store the consuming `Task`, cancel and discard it from their background callback,
then replace it on activation. Do not use an iOS background task solely to keep live-sync
heartbeats running.

The default REST transport permits constrained and expensive network access, including bulk post
history. MattermostSwift does not currently route bulk history separately because the same
injectable session also carries interactive REST calls. Hosts may inject a REST `URLSession` with
`allowsConstrainedNetworkAccess = false` and pass a separate unconstrained
`webSocketURLSession` when blocking all REST work in Low Data Mode matches their product policy.

## Protect Cached Content At Rest

The SwiftData cache contains message bodies, user and channel names, and file metadata. Disk-backed
`MattermostStore` instances therefore default to owner-only directory permissions (`0700`). On iOS,
the store directory and existing SQLite, WAL, and shared-memory files default to
`completeUntilFirstUserAuthentication`, which keeps them unavailable until the first unlock after
a restart while allowing later locked-device background work.

Choose `.complete` when the cache must be unavailable whenever the device is locked:

```swift
let store = try MattermostStore(
    url: storeURL,
    security: MattermostStoreSecurityOptions(
        directoryPermissions: 0o700,
        fileProtection: .complete
    )
)
```

A host that intentionally places the database in a shared directory can pass
`directoryPermissions: nil` and `.platformDefault` to preserve a policy it manages itself. The
host owns that decision and should ensure the directory cannot be read by unintended users or
processes.

File protection is an iOS facility; it is ignored on macOS. macOS applications should keep the
cache in an application-specific private location and rely on FileVault or equivalent
volume-level encryption for data at rest. The CLI secures both its default `.mattermostswift`
directory and the parent directory of `MATTERMOST_STORE_PATH` with owner-only permissions.

## Keep Secrets Outside The SDK

The SDK does not write credentials to Keychain or local storage. Host apps should provide tokens
at startup and avoid logging token values. On Apple platforms, store a device-bound token in
Keychain with an explicit accessibility class:

```swift
import Foundation
import Security

struct KeychainSaveError: Error {
    let status: OSStatus
}

func storeMattermostToken(_ token: String, account: String) throws {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.example.app.mattermost",
        kSecAttrAccount as String: account,
    ]
#if os(macOS)
    query[kSecUseDataProtectionKeychain as String] = true
#endif

    let tokenData = Data(token.utf8)
    let protectedValues: [String: Any] = [
        kSecValueData as String: tokenData,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(
        query as CFDictionary,
        protectedValues as CFDictionary
    )
    if updateStatus == errSecSuccess {
        return
    }
    guard updateStatus == errSecItemNotFound else {
        throw KeychainSaveError(status: updateStatus)
    }

    query.merge(protectedValues) { _, newValue in newValue }
    let addStatus = SecItemAdd(query as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
        throw KeychainSaveError(status: addStatus)
    }
}
```

`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` keeps this example's token device-bound and
available only while unlocked. Choose a different Keychain accessibility class if the host app
must authenticate during locked-device background work.

Never store bearer tokens in `UserDefaults` or `@AppStorage`; both are plist-backed preference
storage and are not credential stores.

## Topics

### Essentials

- ``MattermostClient``
- <doc:Pagination>
- <doc:ErrorHandling>
- ``MattermostTimelineTarget``
- ``MattermostTimelineRequest``
- ``MattermostTimelinePage``

### Authentication

- <doc:Authentication>
- ``MattermostConfiguration``
- ``MattermostAuthentication``
- ``MattermostSession``
- ``MattermostSessionTokenSource``

### Models

- ``MattermostUser``
- ``MattermostTeam``
- ``MattermostChannel``
- ``MattermostPost``
- ``MattermostPostList``
- ``MattermostThreadResponse``
- ``MattermostFileInfo``
- ``MattermostReaction``

### Caching

- <doc:Caching>
- ``MattermostStore``
- ``MattermostSyncService``
- ``MattermostSyncOptions``
- ``MattermostCachedUserSnapshot``
- ``MattermostCachedChannelSnapshot``
- ``MattermostCachedPostSnapshot``

### Live Events

- <doc:LiveSync>
- ``MattermostLiveEventStream``
- ``MattermostLiveEvent``
- ``MattermostTypedLiveEvent``
- ``MattermostLiveSyncService``
- ``MattermostLiveSyncOptions``
- ``MattermostLiveSyncEvent``
