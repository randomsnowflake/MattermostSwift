# MattermostSwift

MattermostSwift is a Swift Package for operating a Mattermost server from Swift code. The package currently contains the reusable `MattermostSwift` library and `MattermostSwiftCLI`, a developer harness for live verification against a real server.

This is an early implementation. The first live flow is working end-to-end:

```sh
swift run MattermostSwiftCLI me
swift run MattermostSwiftCLI get-user
swift run MattermostSwiftCLI profile-image
swift run MattermostSwiftCLI default-profile-image
swift run MattermostSwiftCLI get-users USER_ID USER_ID
swift run MattermostSwiftCLI get-users-by-username USERNAME
swift run MattermostSwiftCLI status
swift run MattermostSwiftCLI server-info
swift run MattermostSwiftCLI search-users USERNAME
swift run MattermostSwiftCLI autocomplete-users USERNAME
swift run MattermostSwiftCLI known-users --profiles
swift run MattermostSwiftCLI list-channels
swift run MattermostSwiftCLI list-public-channels
swift run MattermostSwiftCLI channel-info
swift run MattermostSwiftCLI channel-by-name --team TEAM_ID town-square
swift run MattermostSwiftCLI channel-by-team-name TEAM_NAME town-square
swift run MattermostSwiftCLI channel-stats
swift run MattermostSwiftCLI channel-timezones
swift run MattermostSwiftCLI channel-member-counts
swift run MattermostSwiftCLI search-channels town
swift run MattermostSwiftCLI search-group-channels USERNAME
swift run MattermostSwiftCLI direct-channel-test USER_ID
swift run MattermostSwiftCLI channel-member
swift run MattermostSwiftCLI list-channel-members
swift run MattermostSwiftCLI channel-members-by-id USER_ID
swift run MattermostSwiftCLI add-channel-member USER_ID
swift run MattermostSwiftCLI remove-channel-member USER_ID
swift run MattermostSwiftCLI channel-unread
swift run MattermostSwiftCLI list-unread-posts
swift run MattermostSwiftCLI list-channel-users
swift run MattermostSwiftCLI send-typing
swift run MattermostSwiftCLI list-categories
swift run MattermostSwiftCLI list-threads
swift run MattermostSwiftCLI list-preferences
swift run MattermostSwiftCLI preferences-test
swift run MattermostSwiftCLI preference-roundtrip-test
swift run MattermostSwiftCLI list-posts
swift run MattermostSwiftCLI list-post-updates 1780000000000
swift run MattermostSwiftCLI send-message "hello from MattermostSwift"
swift run MattermostSwiftCLI edit-message POST_ID "edited from MattermostSwift"
swift run MattermostSwiftCLI delete-message POST_ID
swift run MattermostSwiftCLI pinned-posts
swift run MattermostSwiftCLI thread-test
swift run MattermostSwiftCLI timeline-test
swift run MattermostSwiftCLI props-test
swift run MattermostSwiftCLI unread-posts-test
swift run MattermostSwiftCLI threads-test
swift run MattermostSwiftCLI reaction-test
swift run MattermostSwiftCLI search "from:USERNAME"
swift run MattermostSwiftCLI search-test
swift run MattermostSwiftCLI upload-file ./example.txt
swift run MattermostSwiftCLI download-file FILE_ID ./downloaded-example.txt
swift run MattermostSwiftCLI file-test
swift run MattermostSwiftCLI list-emoji
swift run MattermostSwiftCLI search-emoji party
swift run MattermostSwiftCLI list-teams
swift run MattermostSwiftCLI team-info
swift run MattermostSwiftCLI list-team-members
swift run MattermostSwiftCLI stream-events 5
swift run MattermostSwiftCLI websocket-test
swift run MattermostSwiftCLI live-sync-test
swift run MattermostSwiftCLI reconnect-backfill-test
swift run MattermostSwiftCLI deletion-backfill-test
swift run MattermostSwiftCLI live-sync-reconnect-test
swift run MattermostSwiftCLI all-channel-backfill-test
swift run MattermostSwiftCLI all-channel-reconnect-test
swift run MattermostSwiftCLI failure-cleanup-test
swift run MattermostSwiftCLI residue-audit
swift run MattermostSwiftCLI typing-test
swift run MattermostSwiftCLI create-test-channel
swift run MattermostSwiftCLI rename-test-channel CHANNEL_ID
swift run MattermostSwiftCLI archive-channel CHANNEL_ID
swift run MattermostSwiftCLI channel-test
swift run MattermostSwiftCLI sidebar-category-test
swift run MattermostSwiftCLI sidebar-move-test
swift run MattermostSwiftCLI sync
swift run MattermostSwiftCLI cache-check
swift run MattermostSwiftCLI since-test
swift run MattermostSwiftCLI login-test
swift run MattermostSwiftCLI check
```

## Installation

Add MattermostSwift to a Swift package with a branch or version requirement after publishing:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/randomsnowflake/MattermostSwift.git", branch: "main"),
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

For local app development before publishing, add this repository as a package dependency and import `MattermostSwift` from the reusable app/core target. The library has no SwiftUI or Combine dependency.

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

## Minimal Use

```swift
import Foundation
import MattermostSwift

guard let serverURL = URL(string: "https://mattermost.example.com") else {
    throw URLError(.badURL)
}

let client = try MattermostClient(serverURL: serverURL, token: "personal-access-token")
let users = try await client.userService().search(term: "alice")
print(users.map(\.username))
let resolvedUsers = try await client.userService().users(ids: users.map(\.id))
print(resolvedUsers.count)
let namedUsers = try await client.userService().users(usernames: ["alice"])
print(namedUsers.count)
let suggestions = try await client.userService().autocomplete(name: "ali")
print(suggestions.allUsers.map(\.username))
let knownUserIDs = try await client.userService().knownUserIDs()
print(knownUserIDs.count)
let notifyProps = try await client.notificationService().channelNotifyProps(channelID: "channel-id")
print(notifyProps.desktop ?? "default")
let dm = try await client.channelService().createDirectChannel(
    userID: "current-user-id",
    otherUserID: "other-user-id"
)
print(dm.id)

let session = try await MattermostClient.login(
    serverURL: serverURL,
    loginID: "user@example.com",
    password: "password"
)
let passwordClient = try session.client(serverURL: serverURL)
print(session.tokenSource)

let users = client.userService()
let teams = client.teamService()
let channelService = client.channelService()
let posts = client.postService()
let preferences = client.preferenceService()
let threads = client.threadService()
let timelines = client.timelineService()

let user = try await users.currentUser()
let status = try await users.status(userID: user.id)
let avatar = try await users.profileImage(userID: user.id)
let joinedTeams = try await teams.joinedTeams()
let teamMembers = try await teams.members(teamID: "team-id", perPage: 20)
let channels = try await channelService.joinedChannelsAcrossTeams()
let publicChannels = try await channelService.publicChannels(teamID: "team-id", perPage: 20)
let townSquare = try await channelService.channel(teamID: "team-id", name: "town-square")
let stats = try await channelService.stats(channelID: townSquare.id)
let timezones = try await channelService.timezones(channelID: townSquare.id)
let memberCounts = try await channelService.memberCounts(channelIDs: [townSquare.id])
let userPreferences = try await preferences.list()
let store = try await MattermostStore(inMemory: true)

try await store.upsert(user: user)
try await store.upsert(status: status)
try await store.upsert(teams: joinedTeams)
try await store.upsert(channels: channels)
try await store.save()
print(teamMembers.count)

if let channel = channels.first {
    let unread = try await client.channelUnread(channelID: channel.id)
    let member = try await client.channelMember(channelID: channel.id)
    let pageOfMembers = try await channelService.channelMembers(channelID: channel.id, perPage: 20)
    let resolvedMembers = try await channelService.channelMembers(channelID: channel.id, userIDs: [user.id])

    let post = try await posts.sendPost(
        channelID: channel.id,
        message: "hello from MattermostSwift",
        props: [
            "client": .string("MattermostSwift"),
        ]
    )

    try await store.upsert(member: member)
    try await store.upsert(unread: unread, userID: user.id)
    let postSync = try await posts.syncChannelPosts(channelID: channel.id, to: store)
    let timeline = try await timelines.load(.channel(id: channel.id))
    let pinned = try await posts.pinnedPosts(channelID: channel.id)
    let updates = try await posts.postsSince(channelID: channel.id, since: postSync.cursorLastSyncAt)
    _ = try await posts.postsAroundLastUnread(
        channelID: channel.id,
        collapsedThreads: true,
        collapsedThreadsExtended: true
    )
    try await store.save()
}

if let teamID = channels.compactMap(\.teamId).first {
    let threadList = try await threads.list(teamID: teamID, request: MattermostThreadListRequest(perPage: 20, extended: true))
    try await store.upsert(threads: threadList, userID: user.id, teamID: teamID)
    try await store.save()
}

if let firstChannelID = channels.first?.id {
    _ = try store.cachedTimeline(
        .channel(id: firstChannelID),
        includeDeleted: false
    )
}

let syncResult = try await client.syncService().sync(
    to: store,
    channelID: channels.first?.id
)

for try await event in client.liveSyncService().events(
    to: store,
    options: MattermostLiveSyncOptions(channelIDs: channels.prefix(3).map(\.id))
) {
    if let state = event.connectionState {
        print("live-sync state: \(state)")
    }
    if case .backfillFailed(let failure) = event {
        print("live-sync backfill failed: \(failure.message)")
    }
    print(event)
    break
}

// For a small workspace or an explicit catch-up action, hosts can ask reconnect
// backfill to sweep every joined channel instead of the default channel cap.
let fullBackfill = MattermostLiveSyncOptions(backfillAllJoinedChannelPosts: true)
```

## Development

```sh
scripts/test-unit.sh
scripts/test-live.sh
scripts/test-e2e.sh
```

`scripts/test-e2e.sh` includes an isolated mutating flow that creates a temporary
test channel/category and cleans up the resources it created.

See `ARCHITECTURE.md`, `TESTING.md`, and `ROADMAP.md` for the current design and next milestones.
The library target also includes a DocC quick-start article at `Sourcecode/MattermostSwift/MattermostSwift.docc/MattermostSwift.md`.
