# Roadmap

## Done

- Swift Package with `MattermostSwift` library and `MattermostSwiftCLI` executable.
- Source layout under `Sourcecode/`.
- Personal access token REST authentication.
- Username/password login API and `login-test` CLI probe that sends the official web-client login header and extracts the session token from either the documented Mattermost `Token` response header or the official `MMAUTHTOKEN` browser session cookie.
- Public `MattermostSession` login result with source-compatible `MattermostLoginSession` alias.
- Live `me`, `server-info`, `list-channels`, `list-categories`, and `check` CLI commands.
- User search, autocomplete, known-user, users-by-id, users-by-username, and profile/default profile image APIs with read-only CLI verification.
- Joined-team listing, team metadata loading by id/name, paginated team member listing, dedicated `MattermostTeamService`, and read-only `list-teams`/`team-info`/`list-team-members` CLI probes.
- Post history, pinned-post loading, send, edit, delete, and a post e2e CLI flow.
- Explicit post update fetching by `since` timestamp, with cursor sync using a single update fetch after initial backfill and a live CLI verification.
- Unread-context post loading around the oldest unread post, including collapsed-thread query flags and a read-only live CLI verification.
- Thread loading through Mattermost root/reply semantics.
- Per-user/team thread inbox state loading and SwiftData caching for Collapsed Reply Threads, with a read-only live CLI verification.
- Unified `MattermostTimelineService` for channel and thread timelines, with SwiftData cache reads/sync and a live CLI timeline check.
- Post props/metadata decoding, outbound post props, SwiftData cache preservation, and a live props round-trip CLI check.
- Reaction add/list/remove and a reaction e2e CLI flow.
- Team post search and a search e2e CLI flow.
- User lookup, channel users, and presence status lookup.
- File upload, attach-to-post, metadata, and download.
- WebSocket connection, authentication, tolerant event decoding, and a live posted/edit/delete event e2e check.
- Reconnecting WebSocket event stream wrapper with configurable exponential backoff.
- Typed WebSocket event helpers for posts, thread update/read/follow signals, unread invalidation, reactions, typing, presence, and channel-viewed events.
- Channel detail lookup by id/name, public team channel discovery, channel statistics/timezone/member-count lookup, channel membership read/list/by-ids/add/remove, unread counts, view/read marking, typed notify props read/update, create, rename, and archive APIs.
- Direct message channel open, group message channel open, and read-only group message channel search APIs.
- Team-scoped channel search plus broad all-channel search for callers with permission.
- Typing event publication through the REST API.
- Sidebar category create, rename, delete, and category order APIs.
- Sidebar channel move/reorder helpers and a live sidebar move e2e check.
- User preference list/load/save/delete APIs with a read-only live preference decode probe and temporary save/load/delete round-trip verification.
- SwiftData cache foundation for teams, users, statuses, channels, posts, reactions, files, sidebar categories, and sync cursors.
- SwiftData cache for current-user channel membership/read state and active-channel unread counts.
- Store merging for common live post, reaction, unread invalidation, and presence events.
- Store merging for live channel updates/deletes, channel member updates, user updates, and sidebar preference invalidation refreshes.
- Timestamp-aware cache merge policy for posts and channels so older payloads cannot overwrite newer edits or resurrect deleted/archived state.
- Deletion reconciliation for cached posts now handles `post_deleted` live events without embedded post bodies when the event includes post id/timestamp data, and cached timeline reads can filter deleted tombstones for host UI lists.
- Cursor-based channel post sync helper.
- Public `MattermostSyncService` facade for joined-team/current-user hydration, paginated channel post sync, joined-channel membership sync, all joined-channel unread refresh, sidebar category sync, and cache-count reporting.
- Public service facades for server capability probing, users, channels, posts, threads, timelines, files, reactions, search, notifications, sidebar categories, typing, preferences, emoji, and sync over the proven endpoint methods.
- Public `MattermostLiveSyncService` facade that emits live-sync lifecycle events with host-visible connection-state projection, reports backfill failures before terminating the throwing stream, runs connect/reconnect backfill with capped-by-default and opt-in all-joined-channel modes, applies WebSocket events into SwiftData, refreshes unread counts from `channel_viewed`/`post_unread` events where possible, refreshes per-user thread state from thread invalidation events where possible, and has a live CLI posted-event cache check.
- Unit-tested live-sync reconnect orchestration using an injected lifecycle stream, including fresh backfill on every connecting event, deterministic missed-post recovery through cursor backfill, connection-state projection, backfill failure diagnostics, backfill channel selection, event application into SwiftData, unread refresh on `post_unread` invalidation, and thread-state refresh on thread invalidation.
- Live CLI reconnect-backfill check that seeds a channel post cursor, creates a temporary post after that cursor, runs `syncChannelPosts`, verifies the post is returned and cached, and cleans up the temporary post.
- Live CLI deletion-backfill check that caches a temporary post, advances the cursor, deletes the post while disconnected, then verifies cursor backfill returns the deletion tombstone, marks the cached post deleted, filters it from visible cached reads, and advances the cursor.
- Live CLI live-sync reconnect simulation that drives `MattermostLiveSyncService` through connecting/reconnecting/connecting lifecycle events, creates a temporary post while disconnected, verifies the reconnect backfill returns and caches it, and cleans up the post.
- Read-only live CLI all-channel backfill check that runs `MattermostLiveSyncService` with opt-in `backfillAllJoinedChannelPosts`, verifies every joined channel is swept, and uses an in-memory store.
- Live CLI all-channel reconnect simulation that opts into `backfillAllJoinedChannelPosts`, creates a temporary post while disconnected, verifies reconnect backfill sweeps every joined channel and caches the missed post, and cleans up the post.
- CLI `sync` and `cache-check` commands proving live hydration and offline cached reads.
- Explicit `create-test-channel`, `rename-test-channel`, and guarded `archive-channel` CLI commands, verified at the start of `scripts/test-e2e.sh`.
- Isolated `e2e-test` CLI flow that creates a temporary `mmswift-test-` channel/sidebar category, exercises post edit, reply/thread, reaction, file upload/download, search, sidebar move, view/unread, and SwiftData timeline sync, then cleans up the posts/category/channel and restores sidebar order.
- Targeted e2e CLI commands now use best-effort cleanup for the temporary posts, reactions, channels, sidebar categories, and sidebar order they create when an intermediate live assertion fails.
- Forced-failure cleanup CLI check that creates temporary e2e resources, simulates an intermediate failure, proves the shared cleanup helper deletes the post/category/channel and restores sidebar order, and runs in `scripts/test-e2e.sh`.
- Read-only e2e residue audit that fails if active `MattermostSwift` temporary channels or sidebar categories remain on the live server after mutating checks.
- DocC quick-start article covering token auth, password login token source, cache hydration, unified timelines, live sync, all-channel reconnect backfill, and credential ownership.
- Expanded symbol-level DocC comments across the public service facades so host apps can discover the intended high-level API without reading endpoint wrappers first.
- Library force-unwrap audit: the reusable `MattermostSwift` target has no `try!`, `as!`, or forced optional unwraps in production code.
- Pagination hardening: post/channel search, channel users, channel posts, and custom emoji list requests clamp invalid page and per-page inputs before hitting the REST API.
- Custom emoji list, lookup, search, autocomplete, and image download APIs.
- Typed models for user, team, channel, server info, client config, and sidebar categories.
- Typed models for post pages, posts, channel membership/read state, and live event envelopes.
- Focused unit tests for configuration, request construction, REST error handling, decoding, typed live events, and cache upserts.

## Next Slices

1. Deepen live sync lifecycle: add true forced-network-disconnect stress verification for missed-event backfill; deterministic unit coverage, live cursor-backfill, and live service-level reconnect simulation now prove the recovery path without forcing a transport drop.
2. Password-login deployment follow-up: document any proxy/server deployments that strip both the `Token` header and `MMAUTHTOKEN` cookie, if encountered.
3. Broader incremental sync: live stress testing all-channel missed-event backfill under true transport reconnects and any remaining deletion edge cases found on real server traffic; normal connect-time, service-level reconnect all-joined-channel sweeps, and missed deletion tombstone reconciliation now have live CLI checks.
4. Broader e2e hardening: extend reusable cleanup where future mutating flows need it; active channel/category residue auditing now guards the existing mutating script.
5. Public API refinement pass: continue reducing duplicate raw-client/service surface where it improves clarity; the main service facade methods now have host-app-oriented DocC comments.

## Known Notes

- On the current macOS development machine, compiled `URLSession` requests to the Cloudflare-fronted test server can fail before an HTTP/WebSocket response. The SDK keeps URLSession as the primary transport, uses a macOS-only curl fallback for REST, and uses a macOS-only Python `websockets` fallback for live-event verification when `URLSessionWebSocketTask` fails during the upgrade.
- Sidebar category create/update/delete request bodies require the actual user id and team id in the JSON body on the current server, even when the path uses `me`.
- Moving a channel into a custom sidebar category succeeded live by updating the destination category channel list; the helper avoids rewriting built-in categories directly.
- The current server accepts typing publication, but did not echo this account's own typing event back to the same WebSocket session during live testing. Typed decoding is covered by unit tests and `typing-test` reports live receive status when available.
- The broad `/channels/search` endpoint returned HTTP 403 for the current test token; the CLI uses team-scoped `/teams/{team_id}/channels/search`, which succeeded live with ordinary team permissions.
- `POST /users/login` decoded the supplied test user on the current server and live verification now extracts the documented `Token` response header. The earlier missing-token result came from the macOS curl fallback losing response headers before they reached `HTTPURLResponse`. The SDK also sends Mattermost's official web-client `X-Requested-With: XMLHttpRequest` login header and accepts the official `MMAUTHTOKEN` cookie as a session-token fallback, matching the web/desktop client path while still returning a bearer-capable token to host apps.
