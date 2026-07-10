# Changelog

All notable changes to MattermostSwift are documented here.

This project follows semantic versioning before `1.0.0` with one caveat: public APIs may still evolve between minor releases while the SDK hardens against more Mattermost deployments.

## Unreleased

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
