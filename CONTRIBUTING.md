# Contributing

Thanks for helping improve MattermostSwift.

## Development Setup

Use a recent Xcode/Swift toolchain that supports Swift 6 packages. The package currently declares:

- Swift tools version: `6.0`
- Platforms: iOS 18 and macOS 15
- Products: `MattermostSwift` and `MattermostSwiftCLI`

Run unit tests before opening a pull request:

```sh
scripts/test-unit.sh
```

## Live Verification

Live verification uses a real Mattermost server. Set credentials through environment variables and do not commit secrets:

```sh
export MATTERMOST_URL="https://mattermost.example.com"
export MATTERMOST_TOKEN="your-personal-access-token"
export MATTERMOST_CHANNEL_ID="channel-id-for-post-tests"
```

Then run:

```sh
scripts/test-live.sh
```

The end-to-end script performs mutating checks against a real server:

```sh
scripts/test-e2e.sh
```

Only run it against a workspace and account where temporary test posts, files, channels, sidebar changes, preference changes, and archive operations are expected. The script uses `mmswift-test-` and `MattermostSwift Test` markers and attempts cleanup, but interrupted runs can leave residue. See `TESTING.md` for the current live-test scope.

## Pull Requests

- Keep changes focused on one vertical slice.
- Add request-construction or decoding tests for new endpoints.
- Add cache/update tests when persistence behavior changes.
- Preserve the public credential rule: the library does not store tokens and must not log secrets.
- Update `README.md`, DocC, `ROADMAP.md`, and `CHANGELOG.md` when user-facing behavior changes.
