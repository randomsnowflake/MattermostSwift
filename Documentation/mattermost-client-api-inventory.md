# MattermostSwift API Inventory

Short inventory of the public SDK surface intended for app clients such as MattCha. The SwiftUI app lives in a separate repository and depends on this package.

## Entry Points

- `MattermostClient`: high-level server/account client.
- `MattermostClient.login(serverURL:loginID:password:urlSession:)`: username/password login returning `MattermostSession`.
- `MattermostSession.client(serverURL:urlSession:)`: creates a token-authenticated client.
- Service accessors include user, team, channel, notification, typing, preference, sidebar category, post, thread, timeline, reaction, search, file, emoji, and live-event services.

## App-Relevant Public Capabilities

- Users: current user, profile images, user lookup/search/autocomplete, statuses.
- Teams/channels: joined teams, team members, joined/public channels, channel metadata, stats, members, channel creation/patch/delete, DMs, group DMs, sidebar categories.
- Posts/timeline: paged posts, pinned posts, posts since a timestamp, posts around unread, send/edit/delete, cached timeline sync.
- Threads: user thread list/state, thread load, reply.
- Reactions: add, list, remove.
- Files: upload, file info(s), download.
- Search: posts and channels.
- Notifications/typing: unread state, channel notify props, view channel, send typing.
- Realtime: `MattermostLiveEventStream`, typed events, reconnect policies, post/channel/user/reaction/typing decoding.
- Persistence: `MattermostStore` with SwiftData-backed upsert/query helpers for users, teams, channels, members, unread state, posts, threads, reactions, files, sidebar categories, sync cursors, and live-event application.

## UI Mock Boundary

The preview UI uses `ChatPreviewProviding` and `MockChatPreviewService`. Future production view models can keep the SwiftUI views and replace that protocol with thin adapters around `MattermostClient`/service calls.
