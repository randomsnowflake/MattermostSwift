# MattermostSwift

[![Swift Package Index](https://img.shields.io/endpoint?url=https://swiftpackageindex.com/api/packages/randomsnowflake/MattermostSwift/badge?type=swift-versions)](https://swiftpackageindex.com/randomsnowflake/MattermostSwift)
[![Swift Package Index](https://img.shields.io/endpoint?url=https://swiftpackageindex.com/api/packages/randomsnowflake/MattermostSwift/badge?type=platforms)](https://swiftpackageindex.com/randomsnowflake/MattermostSwift)
[![Documentation](https://img.shields.io/badge/documentation-DocC-blue)](https://swiftpackageindex.com/randomsnowflake/MattermostSwift/documentation/mattermostswift)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

MattermostSwift is an unofficial Swift SDK for Mattermost. It gives you the core loop for building your own Swift-based Mattermost app: authenticate, load teams and channels, read timelines, send and edit posts, sync local state, and react to live WebSocket events.

This project is not affiliated with, endorsed by, sponsored by, or supported by Mattermost, Inc. Mattermost is a trademark of Mattermost, Inc.; this repository uses the name only to describe API compatibility.

The package is written with Swift concurrency, ships as a Swift Package, and keeps UI choices out of the library target so it can be used from SwiftUI, AppKit/UIKit, command-line tools, or shared app cores.

## At a Glance

- Swift tools version: 6.0
- Library platforms: iOS 18, macOS 15, tvOS 18, watchOS 11, and visionOS 2
- Products: `MattermostSwift` library and `MattermostSwiftCLI` executable
- Documentation: hosted by Swift Package Index at `https://swiftpackageindex.com/randomsnowflake/MattermostSwift`
- Stability: pre-`1.0.0`; public APIs may evolve between minor releases

The `MattermostSwift` library is built in CI for every declared Apple platform. The
`MattermostSwiftCLI` executable is a macOS development and verification harness.

Linux is not currently supported. The package's cache layer depends on SwiftData, which is
Apple-platform-only, and its live-event transport depends on the Apple Foundation implementation
of `URLSessionWebSocketTask`. Supporting Linux would require separating the portable REST layer
from the SwiftData cache and Apple WebSocket implementation; the package does not expose that split
today.

## Installation

Add MattermostSwift to your package with a version requirement:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/randomsnowflake/MattermostSwift.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourAppCore",
        dependencies: [
            .product(name: "MattermostSwift", package: "MattermostSwift"),
        ]
    ),
]
```

To test unreleased changes, use a branch or local path dependency during app development:

```swift
.package(url: "https://github.com/randomsnowflake/MattermostSwift.git", branch: "main")
```

The library target has no SwiftUI or Combine dependency.

Safe REST reads and the SDK's explicitly audited read-only POST endpoints automatically retry
HTTP 429 and 503 responses up to two times. Numeric `Retry-After` response values are honored;
mutating requests are never replayed automatically. A rate limit that cannot be retried or remains
after those attempts throws `MattermostError.rateLimited(retryAfter:)`, allowing host apps to
present server-directed retry timing.

## Error Handling

Server failures surface as `MattermostError.httpStatus(code:message:apiError:)`. The
`MattermostAPIErrorBody` preserves Mattermost's stable error `id`, diagnostic detail,
`requestId`, and body `statusCode` so apps can branch on stable identity and retain the request
identifier for server-log correlation. Common status checks do not require pattern matching:

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

## Documentation

The package includes curated DocC guides for authentication, pagination, caching, live sync, and
error handling alongside the symbol reference. Swift Package Index builds and hosts the latest
documentation from the package page:

`https://swiftpackageindex.com/randomsnowflake/MattermostSwift`

## Quick Start

Create a client, load the current account, find joined channels, and send a post:

```swift
import Foundation
import MattermostSwift

let client = try MattermostClient(
    serverURL: URL(string: "https://mattermost.example.com")!,
    token: "personal-access-token"
)

let me = try await client.currentUser()
let teams = try await client.teams()
let channels = try await client.joinedChannelsAcrossTeams()

if let channel = channels.first {
    let post = try await client.sendPost(
        channelID: channel.id,
        message: "hello from MattermostSwift"
    )

    let timeline = try await client.timeline(.channel(id: channel.id))
    print("sent \(post.id), loaded \(timeline.posts.count) posts")
}

print("signed in as \(me.username), joined \(teams.count) teams")
```

Load a channel timeline:

```swift
let page = try await client.timeline(.channel(id: "channel-id"))

for post in page.posts {
    print("\(post.userId): \(post.message)")
}
```

Keep an app cache warm with SwiftData:

```swift
@MainActor
func hydrateCache(
    client: MattermostClient,
    channelID: String
) async throws {
    let store = try MattermostStore(inMemory: false)

    let result = try await client.syncService().sync(
        to: store,
        channelID: channelID
    )

    print("cached \(result.cachedChannelsCount) channels")
}
```

`MattermostStore` and the sync methods that mutate it are main-actor isolated. The high-level sync
service saves before returning; when calling store mutation methods directly, call `store.save()`
after staging the related changes.

Listen for live events:

```swift
for try await event in client.liveEventStream().events() {
    if let post = try event.decodedPost() {
        print("post event: \(event.event) \(post.id)")
    }
}
```

Default live-event streams use a dedicated long-lived `URLSession` so the bounded HTTP
resource timeout does not recycle healthy WebSockets. Apps that inject transport sessions can
pass a separate `webSocketURLSession` to `MattermostClient` when REST and live events need
different policies. Enterprise deployments can pass `urlSessionDelegate` to install a custom
server-trust or certificate-pinning policy on both SDK-created sessions; callers constructing
sessions directly can use `URLSession.mattermost(delegate:)` and
`URLSession.mattermostLiveEvents(delegate:)`.

Hosts that need connection diagnostics can consume `lifecycleEvents()`. Malformed event frames
are skipped without disconnecting and yield `eventDecodeFailed` with a
`MattermostLiveEventStreamFailure`, so wire-format changes remain observable.

Live sync always performs its REST backfill before the first connection. Reconnects skip that
fan-out when the socket was down for less than 10 seconds by default, avoiding a full workspace
refresh after a momentary network flap. Set `MattermostLiveSyncOptions.minimumBackfillGap` to
another `Duration`, or set it to `nil` to backfill on every reconnect.

### App lifecycle and network cost

Live sync is foreground-owned work. A host app must stop consuming the live stream when its
scene enters the background and start a new stream when the scene becomes active. Cancelling the
consuming task cancels reconnect/backfill work and closes the WebSocket; the new stream performs
its normal REST backfill before reconnecting, recovering events missed while backgrounded.

SwiftUI can make the scene phase the task identity:

```swift
@Environment(\.scenePhase) private var scenePhase

var body: some View {
    ContentView()
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }

            do {
                for try await event in client.liveSyncService().events(to: store) {
                    updateConnectionUI(with: event)
                }
            } catch is CancellationError {
                // Expected when SwiftUI replaces the task on a scene-phase change.
            } catch {
                presentLiveSyncError(error)
            }
        }
}
```

UIKit/AppKit hosts should keep the consuming `Task`, call `cancel()` from their background
lifecycle callback, discard it, and create a new task on activation. Do not extend the live
stream with an iOS background task merely to keep heartbeats or reconnect backfill running.

The default REST session currently allows Low Data Mode (constrained) and expensive network
paths, including paginated post history and live-sync backfill. This is deliberate: REST
authentication, interactive message operations, unread refresh, and bulk history currently share
one injectable session, so disabling constrained access there would also disable interactive
operations and turn catch-up into a transport failure rather than a reliably deferred transfer.
Hosts that want a whole-REST Low Data Mode policy can inject a `URLSession` whose configuration
sets `allowsConstrainedNetworkAccess = false` (and, if desired,
`allowsExpensiveNetworkAccess = false`), while passing a separate unconstrained
`webSocketURLSession`. MattermostSwift does not currently classify only bulk-history requests for
a different transport policy.

## Authentication

Use a Mattermost personal access token when possible:

```swift
let client = try MattermostClient(
    serverURL: URL(string: "https://mattermost.example.com")!,
    token: "personal-access-token"
)
```

For tools, tests, or local scripts, credentials can also come from the environment:

```sh
export MATTERMOST_URL="https://mattermost.example.com"
export MATTERMOST_TOKEN="your-personal-access-token"
```

```swift
let client = try MattermostClient.liveFromEnvironment()
```

Username/password login is available for deployments that permit it. The SDK returns the session token to the caller and does not store it:

```swift
let session = try await MattermostClient.login(
    serverURL: URL(string: "https://mattermost.example.com")!,
    loginID: "user@example.com",
    password: "password"
)

let client = try session.client(serverURL: URL(string: "https://mattermost.example.com")!)

// Best-effort remote cleanup before discarding a password-login session locally.
try await client.logoutCurrentSession()
```

Store any returned token in your app's secure storage, such as Keychain on Apple platforms; the
DocC guide includes an add-or-update example using
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Never put bearer tokens in `UserDefaults` or
`@AppStorage`. The textual and debug descriptions of sessions, authentication values, and
configurations redact bearer tokens so logging those values does not expose credentials.
`logoutCurrentSession()` revokes Mattermost server sessions; hosts should still discard their
local token even if remote cleanup fails. Personal access tokens may not be accepted by this endpoint.

## Supported APIs

The SDK currently covers:

- Authentication helpers for personal access tokens and username/password sessions.
- Users, profiles, profile images, statuses, custom statuses, MFA helpers, and sessions.
- Teams and team members.
- Channels, direct messages, group messages, channel members, unread state, typing, notification props, and channel view state.
- Posts, replies, pinned posts, edits, deletes, search, files, reactions, threads, per-user thread read state, and timeline loading.
- Preferences, sidebar categories, category order, and channel moves.
- Custom emoji listing, lookup, search, autocomplete, and image downloads.
- Server ping and client configuration.
- WebSocket live events, typed live-event decoding, full-jitter reconnect handling, live sync,
  reconnect backfill, cross-session single/multi-channel unread refresh, and a SwiftData cache/store.

## Package Layout

Source lives in `Sourcecode/`:

- `Sourcecode/MattermostSwift`: reusable SDK library.
- `Sourcecode/MattermostSwiftCLI`: executable test/debug harness.

The SwiftUI app lives in the separate `MattCha` repository and consumes this package as a dependency.

## Environment

Set live credentials through environment variables. Do not commit secrets.

```sh
export MATTERMOST_URL="https://mattermost.example.com"
export MATTERMOST_TOKEN="your-personal-access-token"
export MATTERMOST_AUTH_TOKEN="your-personal-access-token"
export MATTERMOST_CHANNEL_ID="channel-id-for-post-tests"
export MATTERMOST_TEAM_NAME="team-name"
export MATTERMOST_STORE_PATH="./.mattermostswift/MattermostSwift.sqlite"
export MATTERMOST_USERNAME="user@example.com"
export MATTERMOST_PASSWORD="password"
```

`MATTERMOST_AUTH_TOKEN` is accepted as a local-tooling alias for `MATTERMOST_TOKEN`.
`MATTERMOST_TEAM_NAME` is optional for `list-channels`; `list-categories` uses it when present and otherwise derives a team from joined channels. `list-preferences` prints categories, names, and value byte counts without printing preference values.
`MATTERMOST_STORE_PATH` is optional for CLI cache probes; the default is `.mattermostswift/MattermostSwift.sqlite` under the current working directory.
`MATTERMOST_USERNAME` and `MATTERMOST_PASSWORD` are optional and are used only by `login-test`. Password login sends Mattermost's browser-style `X-Requested-With: XMLHttpRequest` login header and returns a `MattermostSession` from the `Token` response header when present, or from Mattermost's `MMAUTHTOKEN` session cookie when a deployment follows the browser/webapp path.
`notify-props-test` is read-only; it loads channel membership and prints the typed per-channel notification properties plus the raw server keys.

## Live Test Warning

`scripts/test-live.sh` and `scripts/test-e2e.sh` run against a real Mattermost server. Some e2e flows create, edit, delete, archive, upload, move sidebar items, change preferences, and send WebSocket-visible events. Run them only against a workspace and account where that activity is expected.

The e2e script uses `mmswift-test-` and `MattermostSwift Test` markers and attempts to clean up created resources, but interrupted runs or server-side failures can leave residue. See `TESTING.md` for details.

## Development

```sh
scripts/test-unit.sh
scripts/test-live.sh
scripts/test-e2e.sh
```

`MattermostSwiftCLI` is a development and verification harness, not the primary product surface. Use it to probe endpoints, exercise live server behavior, and run the scripted checks.

Run `swift run MattermostSwiftCLI --help` to list commands without configuring credentials.
Invalid commands and malformed arguments print a specific error to stderr and exit with status 2;
runtime or server failures exit with status 1.

`scripts/test-e2e.sh` includes an isolated mutating flow that creates a temporary test channel/category and cleans up the resources it created.

See `ARCHITECTURE.md`, `TESTING.md`, and `ROADMAP.md` for the current design and next milestones.
The library target also includes a DocC quick-start article at `Sourcecode/MattermostSwift/MattermostSwift.docc/MattermostSwift.md`.

## Cache and large files

`MattermostStore` uses an append-only SwiftData schema/migration history and
`ModelContainer.mainContext`. Every store operation is main-actor isolated, including sync and
live-sync cache writes, fetches, `prunePosts`, and `deleteChannelContent`; the package does not
provide a background model context. Large cache scans can therefore cause a visible main-thread
hitch. Run them only during an app-controlled idle window where that tradeoff is acceptable.

Hosts own cache retention. As a starting policy, prune each retained channel after initial
hydration and then about once per day during an idle window. Call `deleteChannelContent` when a
channel leaves the app's retention scope. Joined channels, memberships, sidebar categories, and
unread rows are reconciled only from complete scoped server responses, so an empty response can
safely remove stale local rows for that scope.
Post pruning and channel-content deletion also remove reactions, files, and cached thread inbox
state rooted at the deleted posts.
When channel-user hydration is enabled for a selected timeline channel, `MattermostSyncService`
follows every profile page so channels with more than 60 members are cached completely.
`MattermostSyncService` also persists server ETags and ordered list membership for joined teams,
joined channels, and sidebar categories. Later syncs send `If-None-Match`; a `304 Not Modified`
reuses the scoped cached list without rewriting it. Post timelines and unread counts deliberately
bypass this conditional-list cache so their freshness behavior is unchanged.
For work outside that actor, use `cachedUserSnapshots()`, `cachedChannelSnapshots()`, or
`cachedPostSnapshots(...)`; these immutable `Sendable` values do not retain a SwiftData context.
Post snapshots carry `propsJSON` and `metadataJSON` without decoding them while the store is on the
main actor. Call the snapshot's throwing `decodedProps()` or `decodedMetadata()` helper only in
views or background work that needs those payloads.

Disk-backed stores default to owner-only directory permissions (`0700`). On iOS, the store
directory and SQLite files also default to complete-until-first-user-authentication protection.
Hosts that do not need locked-device background access can select `.complete`; hosts using a
shared, separately managed directory can pass `nil` for `directoryPermissions`:

```swift
let store = try MattermostStore(
    url: storeURL,
    security: MattermostStoreSecurityOptions(
        directoryPermissions: 0o700,
        fileProtection: .complete
    )
)
```

Apple file protection does not provide a macOS at-rest guarantee. macOS hosts remain responsible
for choosing a private cache location and enabling FileVault or equivalent volume encryption.

For production-sized attachments, use the file URL overloads instead of materialising the payload:

```swift
let uploaded = try await client.uploadFile(
    channelID: channelID,
    filename: "archive.zip",
    fileURL: sourceURL
)
try await client.downloadFile(id: uploaded.fileInfos[0].id, to: destinationURL, maximumSize: 500_000_000)
```

Live event streams use finite queues, including a 256-event limit while the WebSocket
authentication handshake is pending. If a server or consumer overruns a queue, the stream finishes
with `MattermostError.liveEventGap`; restart live sync to run its normal authoritative backfill
before presenting the cache as current.

Live sync skips an individual WebSocket event when its embedded payload cannot be decoded and
emits `eventApplyFailed` so the host can report schema drift without reconnecting. Failed unread,
sidebar-category, and thread-state refreshes are likewise emitted through their corresponding
`MattermostLiveSyncEvent` failure cases; cancellation still stops the stream.
