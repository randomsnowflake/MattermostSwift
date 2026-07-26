# Changelog

All notable changes to MattermostSwift are documented here.

This project follows semantic versioning before `1.0.0` with one caveat: public APIs may still evolve between minor releases while the SDK hardens against more Mattermost deployments.

## Unreleased

- Live sync now skips the full REST backfill after reconnect gaps shorter than 10 seconds by
  default, while always backfilling the first connection. Hosts can tune
  `MattermostLiveSyncOptions.minimumBackfillGap` or set it to `nil` to backfill every reconnect;
  skipped backfills emit `.connected` once the socket connection succeeds.
- Live-sync channel backfill and bulk unread refresh now share the sync service's width-8 bounded
  concurrency, reducing reconnect and mark-all-read latency while preserving cancellation and
  channel/user result association.
- Added a host-provided `URLSessionDelegate` hook for server-trust evaluation on both default REST
  and WebSocket sessions, with matching session factories for direct URLSession construction.
- Bounded WebSocket events buffered during authentication to 256; overflow now reports
  `MattermostError.liveEventGap` and requires normal reconnect reconciliation.
- Added concrete Keychain token-storage guidance using
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and warned against `UserDefaults`/`@AppStorage`.
- Live sync now skips and reports malformed WebSocket events instead of terminating the stream,
  and surfaces unread, sidebar-category, and thread-state refresh failures to host apps.
- Malformed WebSocket event frames now emit an `eventDecodeFailed` lifecycle signal before
  being skipped, preserving the connection while exposing wire-format failures to host apps.
- WebSocket reconnect backoff now uses full jitter from zero through the capped exponential
  delay, preventing clients affected by the same outage from retrying in lockstep.
- Safe REST reads and audited read-only POST requests now retry HTTP 429 and 503 responses
  with bounded backoff, honoring numeric `Retry-After` values. Mutations are never replayed,
  and exhausted HTTP 429 responses surface as `MattermostError.rateLimited(retryAfter:)`.
- **Breaking:** `MattermostError.httpStatus` now includes a third `apiError` associated value.
  `MattermostAPIErrorBody` preserves Mattermost error IDs, detailed errors, request IDs, and body
  status codes; `MattermostError` also provides `isUnauthorized`, `isForbidden`, and `isNotFound`.
  Existing `httpStatus` pattern matches must accept the new associated value.
- **Breaking:** `MattermostLiveSyncFailure` now carries error and underlying-error domain/code
  identity in addition to its attempt and message, and preserves a typed `MattermostError` when
  available. Its public initializer now requires structured error identity, and backfill failures
  populate it from the thrown error.
- Batched channel-member cleanup when authoritative joined-channel sync removes multiple channels,
  and reused a shared plain JSON decoder for multi-channel viewed timestamps.
- Disk-backed `MattermostStore` caches and CLI cache directories now use owner-only permissions
  by default. iOS stores apply configurable file protection to the directory and SQLite files,
  while macOS hosts retain responsibility for volume-level encryption.
- Corrected the `MattermostStore` threading documentation: all store, sync, live-sync, and
  retention work uses the main actor, with host guidance for scheduling potentially expensive
  pruning and channel cleanup.
- Live sync now skips SwiftData saves for non-mutating events such as typing indicators and
  coalesces event application plus refresh results into at most one save per applied event.
- **Source-breaking:** `MattermostCachedPostSnapshot` now exposes `propsJSON` and
  `metadataJSON` instead of eagerly decoded `props` and `metadata`. Snapshot creation performs no
  JSON decoding; call the new throwing `decodedProps()` and `decodedMetadata()` methods on demand.
- Public channel, post, user, team, timeline-target, sidebar-category, thread, file,
  reaction, custom-emoji, and immutable cache-snapshot value types now conform to
  `Hashable` for use in SwiftUI navigation and hash-based collections.
- `MattermostLiveSyncEvent` now conforms to `Equatable`, enabling direct comparison
  in host-app live-sync reducer tests.
- Redacted bearer tokens from the textual and debug descriptions of `MattermostSession`,
  `MattermostAuthentication`, and `MattermostConfiguration`.
- Server ping and client-configuration decoding now tolerates key casing and separator drift across Mattermost releases.
- Cached thread inbox rows are now removed when their root posts are pruned or their channel
  content is deleted, preventing stale unread threads and unbounded cache growth.
- Channel deletion now removes cached channel memberships, preventing live
  `channel_deleted` events from leaving orphaned membership rows.
- Default live-event streams now use a dedicated long-lived URL session, preventing the
  bounded HTTP session's five-minute resource deadline from recycling healthy WebSockets.
- WebSocket heartbeats now detect URLSession tasks that CFNetwork cancelled after route loss,
  ensuring a silently dead socket enters the normal reconnect and backfill path.
- Added `multiple_channels_viewed` live event decoding (`MattermostMultipleChannelsViewedEvent` with
  per-channel viewed timestamps). Servers with collapsed reply threads enabled emit this instead of
  `channel_viewed` when channels are marked read, so clients ignoring it never see cross-device reads.
- Exposed `last_picture_update` on the user model (`MattermostUser.lastPictureUpdate`)
  so clients can detect whether a user has a custom profile picture (0 = none) and
  cache-bust `/users/{id}/image` bytes.
- Exposed and cached Mattermost collapsed-reply-thread channel unread counters (`total_msg_count`/`total_msg_count_root`, `last_post_at`/`last_root_post_at` on channels; `msg_count_root`/`mention_count_root` on channel members and unread) and added `collapsed_threads_supported` to the view-channel request, so CRT-aware clients can compute channel unread from root counts and mark a channel viewed without auto-reading its threads.
- Channel post pagination now accepts Mattermost's collapsed-thread options, allowing clients to
  load recent channel roots without busy thread replies consuming the entire page.
- Added disk-backed file upload/download APIs, a versioned SwiftData cache schema baseline, and
  scoped authoritative cache reconciliation for channels, memberships, sidebar categories, and unreads.
- Live streams now use bounded queues and report an explicit reconciliation-required gap instead
  of silently dropping events. Incremental post sync refuses to advance a saturated cursor.
- Added immutable `Sendable` cache snapshots for users, channels, and posts, for safe transfer
  into background actors without retaining SwiftData-managed objects.
- Added `MattermostClient.logoutCurrentSession()` for server-side revocation of the authenticated session.
- Added `MattermostClient.markThreadRead` for Mattermost's per-user thread read endpoint, using Mattermost millisecond server timestamps.
- Added `MattermostPost.postMetadata` with typed embedded `files` and `reactions`, so clients can skip per-post `fileInfos`/`reactions` lookups when the server delivers them inline. Decoded tolerantly: malformed metadata yields `nil` instead of failing post decoding.
- Added typed channel mute helpers for notification props so clients can suppress channel delivery while preserving unknown Mattermost fields.

## 0.1.0

Initial public release.

- Added the `MattermostSwift` library product and `MattermostSwiftCLI` verification executable.
- Added bearer-token and username/password session helpers.
- Added users, teams, channels, posts, files, reactions, threads, preferences, sidebar categories, custom emoji, server probing, and timeline APIs.
- Added WebSocket live events, typed event helpers, reconnect handling, live sync, reconnect backfill, and SwiftData caching.
- Added unit, live, and end-to-end verification scripts for local development.
