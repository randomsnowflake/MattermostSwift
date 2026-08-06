# Changelog

All notable changes to MattermostSwift are documented here.

This project follows semantic versioning before `1.0.0` with one caveat: public APIs may still evolve between minor releases while the SDK hardens against more Mattermost deployments.

## Unreleased

- Exposed the authenticated user's mention notification preferences through
  `MattermostUser.notifyProps`, including parsed mention keys and first-name and
  channel-wide mention switches for host-side notification presentation.
- Live-event lifecycle streams now emit `heartbeat` after each successful WebSocket ping,
  allowing hosts to distinguish a healthy idle connection from a silent broken stream.
- Fixed the live post-props verification to preserve integer JSON values and fail when
  either the server or SwiftData cache round trip changes the tested property bag.
- Replaced the CLI's hand-written parser/help with `swift-argument-parser`, scoped to
  the executable target, adding generated root/per-command help, `--version`, shell
  completions, typed validation with exit code 2, position-independent flags, and a
  dedicated `diag` command group.
- Added global `--json` output for every CLI command shape. SDK response models used by
  the CLI now support encoding as well as decoding, while post messages, props,
  preferences, binary downloads, and multi-record diagnostics retain their full data.
  Live verification now extracts identifiers with `jq`.
- Added TTY-gated progress on stderr for sync, all-channel backfill/reconnect, and event
  waits, plus a guard against writing raw download bytes to an interactive terminal.
- Limited the CLI's testing-SPI import to the reconnect-scenario file that calls the one
  SPI API, and added parser/process/output/TTY regression coverage.
- Completed the issue #75 public API ergonomics sweep. Public Mattermost identifiers now use
  `ID`/`IDs` spelling with deprecated `Id`/`Ids` aliases and explicit wire `CodingKeys`;
  subject-first channel/thread parameter order has deprecated compatibility overloads;
  `channelMembers(userID:teamID:)` replaces `channelMembersForUser`; and bulk
  `addChannelMembers` now returns every decoded membership.
- Added `MattermostPostsOptions`, `MattermostUserSearchOptions`,
  `MattermostChannelSearchOptions`, and `MattermostThreadOptions`. The former long-parameter
  overloads remain deprecated, and the `posts` `since` fork now explicitly documents that it
  ignores page and before/after pagination.
- Added Mattermost millisecond `Date` conversion/accessors, a `Date` thread-read overload, and
  cancellation-aware cursor pagination through `allPosts(channelID:pageSize:)`.
- Password login and MFA checks can opt into insecure HTTP for development. Login sessions retain
  their server URL so `session.client()` uses the authenticated server by default, and
  `fromEnvironment` replaces `liveFromEnvironment` with a deprecated alias.
- Reconnect delays now use `Duration`; the former `Double`-seconds initializer/properties remain
  deprecated. Post metadata is now exposed as typed `metadata` plus tolerant `rawMetadata`, with
  deprecated `postMetadata` compatibility. Insecure configurations no longer write to stderr and
  expose `usesInsecureHTTP` for host-owned warnings and telemetry.
- **Source-breaking:** Replaced raw `String` channel types, user presence statuses, post types,
  and sidebar category types/sorting modes with forward-compatible `RawRepresentable` values
  (`MattermostChannelType`, `MattermostUserStatusValue`, `MattermostPostType`,
  `MattermostSidebarCategoryType`, and `MattermostSidebarCategorySorting`). Public request APIs
  now accept these typed values, and unknown server values preserve their raw strings through
  Codable round trips.
- Added curated DocC guides for authentication, pagination, caching, live sync, and error handling;
  documented the complete main-actor `MattermostStore` API and public SwiftData cache-model
  contracts; and corrected the README cache example for Swift 6 strict concurrency.
- Added and documented the supported app-lifecycle contract for live events and live sync: hosts cancel the
  consuming task on background and create a fresh stream on activation, triggering normal
  connect-time backfill. Also made explicit the deliberate default of allowing bulk REST history
  on Low Data Mode/expensive paths and documented the injectable whole-REST alternative.
- `MattermostSwiftCLI --help` and empty invocations now print help without requiring
  Mattermost credentials. Unknown or malformed commands report a specific diagnostic
  on stderr and exit with status 2 instead of printing help and exiting successfully.
- Declared tvOS 18, watchOS 11, and visionOS 2 support alongside iOS 18 and macOS 15,
  with CI builds for every supported Apple platform and documentation of the current Linux limits.
- Workspace sync now persists scoped ETags for joined-team, joined-channel, and sidebar-category
  lists, sends `If-None-Match` on later syncs, and treats HTTP 304 as cached unchanged data.
  Post timelines and unread-count requests remain unconditional.
- Channel-user cache hydration now fetches every profile page instead of silently stopping at
  the first 60 users.
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
- Added typed embedded post `metadata` with `files` and `reactions`, so clients can skip per-post
  lookups when the server delivers them inline. `rawMetadata` preserves unknown fields and malformed
  typed metadata yields `nil` without failing post decoding.
- Added typed channel mute helpers for notification props so clients can suppress channel delivery while preserving unknown Mattermost fields.

## 0.1.0

Initial public release.

- Added the `MattermostSwift` library product and `MattermostSwiftCLI` verification executable.
- Added bearer-token and username/password session helpers.
- Added users, teams, channels, posts, files, reactions, threads, preferences, sidebar categories, custom emoji, server probing, and timeline APIs.
- Added WebSocket live events, typed event helpers, reconnect handling, live sync, reconnect backfill, and SwiftData caching.
- Added unit, live, and end-to-end verification scripts for local development.
