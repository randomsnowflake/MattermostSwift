# Changelog

All notable changes to MattermostSwift are documented here.

This project follows semantic versioning before `1.0.0` with one caveat: public APIs may still evolve between minor releases while the SDK hardens against more Mattermost deployments.

## Unreleased

- Added typed channel mute helpers for notification props so clients can suppress channel delivery while preserving unknown Mattermost fields.

## 0.1.0

Initial public release.

- Added the `MattermostSwift` library product and `MattermostSwiftCLI` verification executable.
- Added bearer-token and username/password session helpers.
- Added users, teams, channels, posts, files, reactions, threads, preferences, sidebar categories, custom emoji, server probing, and timeline APIs.
- Added WebSocket live events, typed event helpers, reconnect handling, live sync, reconnect backfill, and SwiftData caching.
- Added unit, live, and end-to-end verification scripts for local development.
