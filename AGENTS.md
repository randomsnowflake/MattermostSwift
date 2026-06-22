# AGENTS

Guidance for AI coding agents working in this repository.

## Core Rules

- Read `README.md`, `ARCHITECTURE.md`, `TESTING.md`, `ROADMAP.md`, and `LLM_MAINTENANCE.md` before broad package or release work.
- Keep changes focused on one Mattermost SDK vertical slice at a time.
- Preserve Swift 6 concurrency correctness and the package's current iOS/macOS platform requirements unless the user explicitly asks to change them.
- Do not commit secrets, generated SwiftData stores, live Mattermost credentials, captured cookies, or private test output.
- Do not rewrite existing release tags unless the user explicitly requests it.

## Verification

- Run `scripts/test-unit.sh` for normal code changes.
- Run `scripts/test-live.sh` only when live Mattermost credentials are configured and read-only/live behavior needs verification.
- Run `scripts/test-e2e.sh` only against a workspace where mutating test activity is expected.

## Documentation

- Update `CHANGELOG.md` for user-facing changes.
- Update README and DocC when install, authentication, cache, live sync, or supported API behavior changes.
- Update `.spi.yml` if the documented target changes.
- Follow `LLM_MAINTENANCE.md` for Swift Package Index, release, and documentation upkeep.
