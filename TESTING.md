# Testing

## Unit Tests

Run local package tests:

```sh
scripts/test-unit.sh
```

The current unit tests cover:

- server URL normalization,
- environment credential validation,
- username/password login request construction and environment validation,
- request construction,
- post update request construction with the `since` timestamp query,
- unread-context and collapsed-thread request construction,
- thread inbox request construction, thread read-state request construction, decoding, and cache upserts,
- query item construction,
- REST error handling for Mattermost error bodies, non-JSON error bodies, empty successful JSON responses, and binary/data endpoints,
- initial Mattermost response decoding,
- post props/metadata decoding, outbound props request encoding, and SwiftData cache preservation,
- channel search, batch user lookup, user search/autocomplete/known-user request construction, direct/group channel request construction, and custom emoji request/response decoding,
- user preference request construction and decoding,
- WebSocket live event decoding, typed post create/edit/delete/unread and thread update/read/follow event helpers, embedded post/channel/user/member decoding, and tolerant invalidation events,
- WebSocket reconnect backoff policy,
- live-sync reconnect orchestration with an injected lifecycle stream, including backfill on each connecting event, cursor-based recovery of posts missed while disconnected, host-visible connection-state projection, backfill failure diagnostics, capped/all-channel backfill selection, live-event application into SwiftData, unread refresh on `post_unread` invalidation, and thread-state refresh on thread invalidation,
- SwiftData cache upserts, cached reads, unified channel/thread timeline reads, deleted-post filtering, post/thread ordering, reactions, files, live-event merging, channel/post deletion state, timestamp merge policy, and sync cursors.

## Live Verification

Live verification uses a real Mattermost server and requires:

- `MATTERMOST_URL`
- `MATTERMOST_TOKEN`
- `MATTERMOST_CHANNEL_ID` for post history and mutating e2e checks
- `MATTERMOST_TEAM_NAME` optional
- `MATTERMOST_USERNAME` and `MATTERMOST_PASSWORD` optional for `login-test`

Run:

```sh
scripts/test-live.sh
```

The current live script verifies:

- authentication and current user,
- user lookup, profile/default profile image download, batch user lookup, user search/autocomplete/known-user probes, and current-user presence,
- server health/config probing,
- joined team listing, team metadata loading, and team member listing,
- joined channel listing, public team channel discovery, channel detail lookup by id/name, and read-only channel stats/timezone/member-count lookup,
- team-scoped channel search,
- channel membership lookup, paginated channel member listing, unread counts, and typed notification props,
- channel membership management request construction, with automated live smoke kept to read-only membership lookup,
- unread-context post loading around the oldest unread post,
- typing event publication,
- users in a channel,
- sidebar category listing where a team can be resolved,
- read-only thread inbox state loading and in-memory thread cache upsert,
- read-only preference listing/decode plus temporary preference save/load/delete round-trip cleanup,
- recent post listing and pinned-post loading for `MATTERMOST_CHANNEL_ID`,
- custom emoji list/search where the server supports custom emoji,
- read-only group-message channel search,
- live cache hydration with `sync`, including joined team metadata, channel membership, and all joined-channel unread cache records,
- opt-in all-joined-channel live-sync backfill using an in-memory store,
- offline cache readback with `cache-check`, including cached joined-team metadata.

`sync` writes to `.mattermostswift/MattermostSwift.sqlite` by default, or to `MATTERMOST_STORE_PATH` when set. The directory is ignored by git.
When username/password credentials are present, `scripts/test-live.sh` runs `login-test`; otherwise password-login probing is skipped. On the current development server, `login-test` verifies direct password login, prints the non-secret token source, and then proves the returned session token by loading `me`. Unit tests cover both the documented `Token` response header and the official `MMAUTHTOKEN` cookie fallback.

## End-to-End Verification

The e2e script starts with an isolated full-flow run that creates its own
`mmswift-test-` channel and sidebar category, moves the channel into the
category, creates/edits/replies/reacts/uploads/searches/syncs inside that
channel, then soft-deletes the posts, deletes the category, archives the
channel, and restores the original sidebar category order. Later commands in
the script continue to exercise targeted feature flows against
`MATTERMOST_CHANNEL_ID` where an existing channel is useful for live stream and
history checks:

```sh
scripts/test-e2e.sh
```

It creates posts/files/channels/sidebar categories with `mmswift-test-` or `MattermostSwift Test` markers, edits and reads one post back, soft-deletes all created posts, verifies a root/reply thread, verifies unified channel/thread timeline loading and SwiftData sync, verifies post update fetching through the `since` timestamp query, verifies post props round-trip and cache preservation, verifies adding/listing/removing a reaction, verifies search finds a newly-created marker post before cleanup, verifies file upload/attach/download, verifies that the live WebSocket stream receives `posted`, `post_edited`, and `post_deleted` events for a mutating post flow, verifies that `MattermostLiveSyncService` applies a newly-created posted event into SwiftData, verifies live cursor-based reconnect backfill by creating a post after a stored cursor and confirming the next backfill caches it, verifies cursor-based deletion reconciliation by deleting a cached post after the stored cursor and confirming backfill marks it deleted and filters it from visible cached reads, verifies service-level live-sync reconnect by creating a post between injected reconnect lifecycle events and confirming the reconnect backfill caches it, verifies opt-in all-joined-channel reconnect backfill by sweeping every joined channel after a simulated disconnect and confirming the missed post is cached, verifies forced-failure cleanup of temporary posts/categories/channels/sidebar order, verifies typing publication and opportunistically reports whether the current server echoes the event to the sender, verifies the explicit `create-test-channel`, `rename-test-channel`, and `archive-channel` commands, verifies channel create/rename/read-state/view/archive behavior, verifies sidebar category create/rename/order/delete behavior, verifies moving a test channel into a test sidebar category, and finishes with a read-only residue audit that fails if active temporary test channels or sidebar categories remain. Thread-specific WebSocket events are currently covered deterministically by unit decoding tests because their delivery depends on server collapsed-thread/follow state.

Future live tests should continue using the `mmswift-test-` prefix and clean up where safe.
