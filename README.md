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
- Platforms: iOS 18 and macOS 15
- Products: `MattermostSwift` library and `MattermostSwiftCLI` executable
- Documentation: hosted by Swift Package Index at `https://swiftpackageindex.com/randomsnowflake/MattermostSwift`
- Stability: pre-`1.0.0`; public APIs may evolve between minor releases

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

## Documentation

The package includes DocC documentation for the library target. Swift Package Index builds and hosts the latest documentation from the package page:

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
let store = try MattermostStore(inMemory: false)

let result = try await client.syncService().sync(
    to: store,
    channelID: "channel-id"
)

try store.save()
print("cached \(result.cachedChannelsCount) channels")
```

Listen for live events:

```swift
for try await event in client.liveEventStream().events() {
    if let post = try event.decodedPost() {
        print("post event: \(event.event) \(post.id)")
    }
}
```

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

Store any returned token in your app's secure storage, such as Keychain on Apple platforms.
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
- WebSocket live events, typed live-event decoding, reconnect handling, live sync, reconnect backfill, and a SwiftData cache/store.

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

`scripts/test-e2e.sh` includes an isolated mutating flow that creates a temporary test channel/category and cleans up the resources it created.

See `ARCHITECTURE.md`, `TESTING.md`, and `ROADMAP.md` for the current design and next milestones.
The library target also includes a DocC quick-start article at `Sourcecode/MattermostSwift/MattermostSwift.docc/MattermostSwift.md`.
