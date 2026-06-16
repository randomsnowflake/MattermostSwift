# MattermostSwift Architecture

MattermostSwift is a Swift Package with two products:

- `MattermostSwift`: the reusable SDK library.
- `MattermostSwiftCLI`: a developer/test executable used to verify real server behavior.

Source lives under `Sourcecode/` so future app targets can sit beside the library and CLI without changing the package layout.

## Current Milestone

The first milestone is deliberately narrow: prove live authentication, current-user loading, and channel listing end-to-end before expanding the SDK surface.

Implemented flow:

1. Build a `MattermostClient` from a server URL and bearer token.
2. Login with username/password via `POST /api/v4/users/login`, extracting the session token from the documented `Token` response header or the official `MMAUTHTOKEN` session cookie.
3. Call `GET /api/v4/users/me`.
4. Lookup users via `GET /api/v4/users/{user_id}`, download profile/default profile images via `GET /api/v4/users/{user_id}/image` and `/image/default`, batch-load users via `POST /api/v4/users/ids` and `POST /api/v4/users/usernames`, search/autocomplete users via `POST /api/v4/users/search` and `GET /api/v4/users/autocomplete`, load known user IDs via `GET /api/v4/users/known`, and list channel users via `GET /api/v4/users?in_channel=...`.
5. Lookup presence via `GET /api/v4/users/{user_id}/status` and `POST /api/v4/users/status/ids`.
6. List joined teams via `GET /api/v4/users/me/teams`.
7. Resolve the configured team via `GET /api/v4/teams/name/{team_name}` when `MATTERMOST_TEAM_NAME` is set, load team metadata via `GET /api/v4/teams/{team_id}`, and list team membership records via `GET /api/v4/teams/{team_id}/members`.
8. List joined channels via `GET /api/v4/users/me/teams/{team_id}/channels` and public team channels via `GET /api/v4/teams/{team_id}/channels`.
9. If no team name is configured, list all joined channels via `GET /api/v4/users/me/channels`.
10. Resolve channel details by id, by team id plus channel name, or by team name plus channel name.
11. Load channel membership, list paginated channel members, lookup specific channel members by user id, add/remove channel members where permissions allow, and manage member counts, channel stats, channel member timezones, unread counts, notification props, and view/read state.
12. Create, patch, and archive test channels where permissions allow.
13. Open direct message channels, open group message channels, and search existing group message channels.
14. Search channels through the team-scoped channel search API; the broader all-channel search API is also exposed for callers with permission.
15. Probe server health/configuration via `GET /api/v4/system/ping` and `GET /api/v4/config/client`.
16. List, create, update, delete, reorder sidebar categories, and move/reorder channels in custom sidebar categories.
17. Load, send, edit, and delete posts via the Mattermost posts API, including `since` timestamp update fetches, pinned-post loading, unread-context loading around the oldest unread post, plus tolerant JSON props and metadata on post payloads.
18. Load threads via `GET /api/v4/posts/{post_id}/thread`, including collapsed-thread query flags for servers with CRT enabled.
19. Load and cache per-user thread inbox state via `GET /api/v4/users/{user_id}/teams/{team_id}/threads`.
20. Load channel and thread timelines through a unified `MattermostTimelineTarget` abstraction and cache them through `MattermostStore`.
21. Add, list, and remove reactions via the Mattermost reactions API.
22. Search team posts via `POST /api/v4/teams/{team_id}/posts/search`.
23. Upload, attach, inspect, and download files via the Mattermost files API.
24. List, search, autocomplete, inspect, and download custom emoji metadata/images.
25. Publish typing via `POST /api/v4/users/{user_id}/typing`.
26. List, load, save, and delete user preferences through `GET/PUT/POST /api/v4/users/{user_id}/preferences...`, with read-only decode verification and a temporary save/load/delete live round-trip.
27. Connect to `GET /api/v4/websocket`, authenticate, decode live events, emit lifecycle/reconnect notifications, and map common post, thread, reaction, typing, presence, unread, channel, channel-member, user, and preference invalidation events into typed cases.
28. Hydrate a SwiftData cache from live user/channel/sidebar/post slices through `MattermostSyncService` and read it back offline through the CLI.
29. Maintain the SwiftData cache from live WebSocket events through `MattermostLiveSyncService`, including bounded connect/reconnect backfill and live posted-event cache application.
30. Live-verify cursor-based missed-post backfill by seeding a stored channel cursor, creating a temporary post, syncing with `since`, and confirming the post lands in SwiftData.
31. Live-verify failure cleanup by creating temporary e2e resources, simulating an intermediate failure, and proving posts/categories/channels/sidebar order are cleaned up through the shared helper.
32. Live-verify WebSocket message lifecycle delivery for posted, edited, and deleted posts through the CLI harness.

The CLI reads credentials from environment variables:

- `MATTERMOST_URL`
- `MATTERMOST_TOKEN`
- `MATTERMOST_AUTH_TOKEN` as a compatibility alias for local tooling
- `MATTERMOST_TEAM_NAME` optional for team-scoped channel listing
- `MATTERMOST_STORE_PATH` optional for CLI cache probes
- `MATTERMOST_USERNAME` and `MATTERMOST_PASSWORD` optional for password-login probing

The library never stores credentials and never logs token values.

## Layers

`MattermostClient` is the root public entry point. It owns:

- `MattermostConfiguration`: base URL and authentication method.
- `MattermostSession`: user plus session token returned by username/password login, including whether the token came from the `Token` response header or `MMAUTHTOKEN` cookie; host apps decide if and how to store it.
- `MattermostHTTPClient`: request construction, bearer auth, JSON decoding, and HTTP error mapping.
- Proven endpoint methods for the current vertical slices.
- Factory methods for concept-specific facades: `MattermostUserService`, `MattermostTeamService`, `MattermostChannelService`, `MattermostPostService`, `MattermostThreadService`, `MattermostTimelineService`, `MattermostFileService`, `MattermostReactionService`, `MattermostSearchService`, `MattermostNotificationService`, `MattermostSidebarCategoryService`, `MattermostTypingService`, `MattermostPreferenceService`, `MattermostEmojiService`, `MattermostSyncService`, and `MattermostLiveSyncService`.

HTTP and WebSocket requests set a browser-shaped macOS Safari `User-Agent`, matching the deployment reality that Mattermost's official desktop app is an Electron/browser wrapper and reducing the chance that a fronting edge layer classifies compiled SDK traffic as unusual automation. On macOS, `MattermostHTTPClient` still has a narrow `curl` fallback when compiled `URLSession` requests fail with `NSURLErrorNetworkConnectionLost` before an HTTP response. This keeps the CLI useful against the current Cloudflare-fronted development server while preserving URLSession as the primary SDK transport. The fallback passes authorization headers through curl config stdin so tokens are not placed in process arguments; password-login retry streams its JSON body over stdin instead of writing credentials to a temporary file.

`MattermostLiveEventStream` uses `URLSessionWebSocketTask` as its primary WebSocket transport. `events()` is a single authenticated connection; `reconnectingEvents(policy:)` wraps it with exponential backoff for long-running consumers; `lifecycleEvents(policy:)` also emits connecting/reconnecting notices for sync orchestration. On the current macOS development machine the same fronted server can close the Foundation WebSocket upgrade before the first frame; for live CLI verification only, the stream falls back to a macOS Python `websockets` bridge and passes the token over stdin rather than process arguments.

Public models are intentionally small and stable while the first flow hardens:

- `MattermostUser`
- `MattermostSession`
- `MattermostUserStatus`
- `MattermostTeam`
- `MattermostTeamMember`
- `MattermostChannel`
- `MattermostChannelSearchResults`
- `MattermostChannelMember`
- `MattermostChannelNotifyProps`
- `MattermostChannelUnread`
- `MattermostSidebarCategory`
- `MattermostSidebarCategoryMoveResult`
- `MattermostPost`
- `MattermostPostList`
- `MattermostTimelineTarget`
- `MattermostTimelineRequest`
- `MattermostTimelinePage`
- `MattermostTimelineSyncResult`
- `MattermostThreadListRequest`
- `MattermostThreadResponse`
- `MattermostThreadList`
- `MattermostReaction`
- `MattermostPostSearchResults`
- `MattermostFileInfo`
- `MattermostCustomEmoji`
- `MattermostPreference`
- `MattermostLiveEvent`
- `MattermostTypedLiveEvent`
- `MattermostTypingEvent`
- `MattermostCacheInvalidationEvent`
- `MattermostThreadEvent`

`MattermostStore` is a `@MainActor` SwiftData wrapper for local cache/persistence. It exposes app-friendly model classes for cached teams, users, statuses, channels, channel deletion/archive state, channel membership/read state, unread counts, per-user thread inbox state, posts, reactions, files, sidebar categories, and sync cursors. It can also merge common typed live events into the cache, including post edits/deletes, reactions, unread invalidations, presence changes, channel updates/deletes, channel member updates, and user updates.

`MattermostTimelineService` gives host apps one API shape for channel timelines and thread timelines. `MattermostTimelineTarget.channel(id:)` loads and caches channel post pages; `MattermostTimelineTarget.thread(rootPostID:)` loads and caches a root/reply thread, with request options for `fromPost`, `fromCreateAt`, direction, and collapsed-thread query flags. The target also owns the cache cursor scope so timeline sync and offline reads can avoid ad hoc string keys in app code.

`MattermostSyncService` is the first high-level sync facade. It hydrates joined team metadata, current user, current-user status, joined channels, current-user channel memberships, all joined-channel unread counts, optional channel users, optional paginated channel posts, sidebar categories, and team/channel cursor records. `MattermostClient.syncChannelPosts(channelID:to:perPage:maxPages:)` remains available for targeted timeline backfill using the store cursor: the first pass pages recent channel history, while later passes use Mattermost's `since` timestamp query once per sync to fetch updates created or modified after the stored cursor. The service is still deliberately bounded and does not yet reconcile every possible server-side deletion across every channel.

The cache merge policy is server timestamp last-write-wins where Mattermost exposes timestamps. Cached posts compare `create_at`, `update_at`, `edit_at`, and `delete_at`; cached channels compare `create_at`, `update_at`, and `delete_at`. Older payloads are ignored so a delayed REST page or WebSocket event cannot overwrite a newer edit or resurrect a deleted/archived item. Post deletion events without an embedded post can still tombstone an existing cached post from the event id/timestamp, and cached timeline reads can include tombstones for sync/debug views or filter them for normal message lists. Objects without useful server timestamps still use straightforward upsert semantics.

`MattermostLiveSyncService` builds on the raw stream and sync service. Before each socket connection attempt it runs REST backfill, optionally across joined channel timelines, then applies typed live events into `MattermostStore` as they arrive. Reconnect backfill uses each channel's stored post cursor, so posts created or modified while the socket was down can be fetched through Mattermost's `since` query and merged before live event consumption resumes. It emits `MattermostLiveSyncEvent` values so host apps can show connecting, backfilled, event-applied, unread-refreshed, sidebar-refreshed, thread-state-refreshed, reconnecting, and backfill-failed states; each lifecycle event also exposes a derived `connectionState` for host UI indicators. If REST backfill fails, the stream yields a non-secret failure diagnostic before terminating with the original error. `channel_viewed` and `post_unread` events refresh channel unread counts when configured, using the current synced user as a fallback when the WebSocket payload omits a user id. Thread events such as `response`, `thread_updated`, `thread_follow_changed`, and `thread_read_changed` trigger a targeted `GET /api/v4/users/{user_id}/teams/{team_id}/threads/{thread_id}` refresh when enough user/team/thread context is available, then upsert the returned per-user thread state and root post/participants. Replies themselves continue to enter the cache through normal `posted` events. Preference events trigger a sidebar category refresh for the active team when configured. The current policy is still intentionally simple: backfill is page/channel bounded by default, but hosts can opt into `backfillAllJoinedChannelPosts` for a full joined-channel missed-event sweep on connect/reconnect. Conflict handling remains server-timestamp last-write-wins through normal cache upserts. Its reconnect orchestration, missed-post cursor recovery, connection-state projection, backfill failure diagnostics, channel-selection policy, unread invalidation refresh, and thread-state invalidation refresh are unit-tested with an injected lifecycle stream so backfill-on-each-connect behavior can be proven without forcing a real network drop.

The internal REST layer decodes Mattermost snake_case payloads and maps errors into `MattermostError`.

## Expansion Rules

Do not add broad chat features until the first live loop keeps working:

```sh
swift run MattermostSwiftCLI me
swift run MattermostSwiftCLI profile-image
swift run MattermostSwiftCLI default-profile-image
swift run MattermostSwiftCLI status
swift run MattermostSwiftCLI list-teams
swift run MattermostSwiftCLI team-info
swift run MattermostSwiftCLI list-team-members
swift run MattermostSwiftCLI get-users-by-username USERNAME
swift run MattermostSwiftCLI search-users USERNAME
swift run MattermostSwiftCLI autocomplete-users USERNAME
swift run MattermostSwiftCLI known-users --profiles
swift run MattermostSwiftCLI list-channels
swift run MattermostSwiftCLI list-public-channels
swift run MattermostSwiftCLI channel-info
swift run MattermostSwiftCLI channel-by-name --team TEAM_ID CHANNEL_NAME
swift run MattermostSwiftCLI channel-stats
swift run MattermostSwiftCLI channel-timezones
swift run MattermostSwiftCLI channel-member-counts
swift run MattermostSwiftCLI search-channels town
swift run MattermostSwiftCLI search-group-channels USERNAME
swift run MattermostSwiftCLI direct-channel-test USER_ID
swift run MattermostSwiftCLI channel-member
swift run MattermostSwiftCLI list-channel-members
swift run MattermostSwiftCLI channel-members-by-id USER_ID
swift run MattermostSwiftCLI channel-unread
swift run MattermostSwiftCLI unread-posts-test
swift run MattermostSwiftCLI threads-test
swift run MattermostSwiftCLI check
swift run MattermostSwiftCLI list-posts
swift run MattermostSwiftCLI pinned-posts
swift run MattermostSwiftCLI e2e-test
swift run MattermostSwiftCLI thread-test
swift run MattermostSwiftCLI timeline-test
swift run MattermostSwiftCLI since-test
swift run MattermostSwiftCLI props-test
swift run MattermostSwiftCLI reaction-test
swift run MattermostSwiftCLI search-test
swift run MattermostSwiftCLI file-test
swift run MattermostSwiftCLI list-emoji
swift run MattermostSwiftCLI search-emoji a
swift run MattermostSwiftCLI preferences-test
swift run MattermostSwiftCLI preference-roundtrip-test
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
swift run MattermostSwiftCLI login-test
```

After that, grow the SDK one vertical slice at a time: posts, WebSocket events, sidebar categories, reactions, files, search, sync, and persistence. Each slice should include request construction tests, cache/update tests where applicable, plus live CLI verification where practical.

## API Sources

The first endpoints are based on Mattermost API v4:

- Current user: `GET /api/v4/users/{user_id}`, where `me` identifies the authenticated user.
- User profile images: `GET /api/v4/users/{user_id}/image` and `GET /api/v4/users/{user_id}/image/default`.
- Joined teams: `GET /api/v4/users/{user_id}/teams`.
- Team metadata: `GET /api/v4/teams/{team_id}` and `GET /api/v4/teams/name/{team_name}`.
- Team membership: `GET /api/v4/teams/{team_id}/members?page=...&per_page=...&sort=...&exclude_deleted_users=...`.
- Team channels: joined channel listing via `GET /api/v4/users/{user_id}/teams/{team_id}/channels` and public channel discovery via `GET /api/v4/teams/{team_id}/channels?page=...&per_page=...`.
- All channels for a user: `GET /api/v4/users/{user_id}/channels`.
- Channel detail resolution: `GET /api/v4/channels/{channel_id}`, `GET /api/v4/teams/{team_id}/channels/name/{channel_name}`, and `GET /api/v4/teams/name/{team_name}/channels/name/{channel_name}`.
- Channel statistics/timezones: `GET /api/v4/channels/{channel_id}/stats`, `GET /api/v4/channels/{channel_id}/timezones`, and `POST /api/v4/channels/stats/member_count`.
- Channel membership: `GET /api/v4/channels/{channel_id}/members?page=...&per_page=...`, `GET /api/v4/channels/{channel_id}/members/{user_id}`, `POST /api/v4/channels/{channel_id}/members/ids`, `POST /api/v4/channels/{channel_id}/members`, and `DELETE /api/v4/channels/{channel_id}/members/{user_id}`.
- Channel post updates: `GET /api/v4/channels/{channel_id}/posts?since={unix_ms}`.
- Pinned posts: `GET /api/v4/channels/{channel_id}/pinned`.
- Posts around oldest unread: `GET /api/v4/users/{user_id}/channels/{channel_id}/posts/unread?limit_before=...&limit_after=...&skipFetchThreads=...&collapsedThreads=...&collapsedThreadsExtended=...`.
- Thread loading: `GET /api/v4/posts/{post_id}/thread?perPage=...&fromPost=...&fromCreateAt=...&direction=...&skipFetchThreads=...&collapsedThreads=...&collapsedThreadsExtended=...`.
- Thread inbox state: `GET /api/v4/users/{user_id}/teams/{team_id}/threads?since=...&before=...&after=...&per_page=...&extended=...&unread=...`.
- User preferences: `GET /api/v4/users/{user_id}/preferences`, `GET /api/v4/users/{user_id}/preferences/{category}`, `GET /api/v4/users/{user_id}/preferences/{category}/name/{name}`, `PUT /api/v4/users/{user_id}/preferences`, and `POST /api/v4/users/{user_id}/preferences/delete`.
- WebSocket event delivery: Mattermost documents the `/api/v4/websocket` authentication challenge and the event list, including `channel_viewed`, `post_unread`, `response`, `thread_updated`, `thread_follow_changed`, and `thread_read_changed`; the SDK treats these as typed invalidation/thread signals where practical.
- Post props: Mattermost documents `props` as a JSON property bag for post integrations; the SDK keeps props/metadata generic through `MattermostJSONValue` instead of overfitting server-specific shapes.

Personal access tokens are treated as bearer/session tokens for REST authentication. Username/password login follows Mattermost's official browser-client semantics where safe: the SDK sends `X-Requested-With: XMLHttpRequest` like the web app so Mattermost can attach browser session cookies, prefers the `Token` response header used by non-browser API clients, and falls back to the `MMAUTHTOKEN` cookie used by the web app and Electron desktop app. The cookie value is returned as a bearer-capable session token; the SDK still does not maintain a browser cookie jar or store credentials. This mirrors the upstream desktop/web split: the Electron desktop app loads the web app in a `WebContentsView` and its main-process helpers authenticate through Electron's default-session cookies, while the web client posts `/users/login`, stores the `Token` header when visible, and relies on browser cookies plus CSRF state for browser-authenticated traffic.
