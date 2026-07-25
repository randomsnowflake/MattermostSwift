# Contributing

Thanks for helping improve MattermostSwift.

## Development Setup

Use a recent Xcode/Swift toolchain that supports Swift 6 packages. The package currently declares:

- Swift tools version: `6.0`
- Platforms: iOS 18 and macOS 15
- Products: `MattermostSwift` and `MattermostSwiftCLI`

Read the repository guidance before making broad package or release changes:

- [`AGENTS.md`](AGENTS.md) contains the rules for automated coding agents.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) describes the package layers and endpoint expansion rules.
- [`TESTING.md`](TESTING.md) documents unit, live, and end-to-end verification.
- [`LLM_MAINTENANCE.md`](LLM_MAINTENANCE.md) contains package metadata, documentation, and release upkeep.

## Where Things Live

- Reusable SDK code belongs in `Sourcecode/MattermostSwift`.
- The development and live-verification CLI belongs in `Sourcecode/MattermostSwiftCLI`.
- Unit tests belong in `Tests/MattermostSwiftTests`.
- DocC articles belong in `Sourcecode/MattermostSwift/MattermostSwift.docc`.
- Local and CI entry points belong in `scripts`.

Follow the [architecture expansion rules](ARCHITECTURE.md#expansion-rules) when adding an endpoint.
Keep each change to one vertical slice: request construction and decoding, a focused public API or
service facade, cache behavior where applicable, unit tests, and practical live CLI verification.
Do not add a package dependency for the library target when an Apple platform API already provides
the required behavior. Dependencies used only by the CLI must remain scoped to the executable target.

## Formatting and Tests

The repository uses the Swift toolchain's `swift format` command and the checked-in `.swift-format`
configuration. Check formatting without changing files:

```sh
scripts/lint.sh
```

Apply the formatter locally:

```sh
swift format format --in-place --recursive --configuration .swift-format Sourcecode Tests
```

Run all unit tests:

```sh
scripts/test-unit.sh
```

Run one XCTest case or method by passing SwiftPM's test filter:

```sh
swift test --filter MattermostClientTests
swift test --filter MattermostClientTests/testCurrentUserRequest
```

Generate the same LCOV report uploaded by CI:

```sh
scripts/test-coverage.sh
```

Coverage export requires Xcode's `xcrun` and writes `coverage.lcov` by default. Set
`COVERAGE_OUTPUT` to choose another output path.

## Public API Checklist

For every new or changed public symbol:

- Add a useful DocC comment describing behavior, parameters, return value, and important errors.
- Add `Sendable` conformance when values cross concurrency boundaries.
- Add `Hashable` when the value has stable value semantics and can support it correctly.
- Preserve Swift 6 concurrency correctness and the current platform requirements.
- Add a concise entry to the `Unreleased` section of `CHANGELOG.md`.
- Update the DocC quick start, README, architecture, testing guide, and roadmap when their documented behavior changes.

Before `1.0.0`, source-breaking public API changes may ship in a minor release when necessary, but
they should not be casual. Deprecate an existing API first when a practical migration path exists,
document the replacement, and call out unavoidable source breaks prominently in the changelog.

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

Only run it against a workspace and account where temporary test posts, files, channels, sidebar
changes, preference changes, and archive operations are expected. The script uses `mmswift-test-`
and `MattermostSwift Test` markers and attempts cleanup, but interrupted runs can leave residue.
See `TESTING.md` for the current live-test scope.

## Commits and Pull Requests

Use an imperative Conventional Commit-style subject for commits and pull request titles:
`feat: add custom status lookup`, `fix: preserve deleted post cursor`, or
`docs: explain session token ownership`. Keep the subject focused and omit issue-only prefixes.

- Keep changes focused on one vertical slice.
- Add request-construction or decoding tests for new endpoints.
- Add cache/update tests when persistence behavior changes.
- Preserve the public credential rule: the library does not store tokens and must not log secrets.
- Update `README.md`, DocC, `ROADMAP.md`, and `CHANGELOG.md` when user-facing behavior changes.
- In the pull request, list the exact validation commands run and state honestly when a required
  Apple toolchain or live Mattermost workspace was unavailable.
