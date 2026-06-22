# LLM Maintenance Guide

This file is for AI coding agents and other maintainers working on MattermostSwift. Keep the public package metadata, release notes, and Swift Package Index integration updated whenever the package changes.

## Package Metadata Checklist

When changing package products, supported platforms, Swift language mode, or minimum toolchain:

- update `Package.swift`,
- update the badges and platform/toolchain text in `README.md`,
- update the package summary in `CONTRIBUTING.md` if the development requirements changed,
- check whether `.spi.yml` still names the correct documentation target,
- run `scripts/test-unit.sh`.

## Swift Package Index Checklist

MattermostSwift is listed at:

`https://swiftpackageindex.com/randomsnowflake/MattermostSwift`

Keep `.spi.yml` in the repository root. It tells Swift Package Index to build hosted DocC documentation for `MattermostSwift`:

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [MattermostSwift]
```

If the library target is renamed, update `.spi.yml`, README badge links, and DocC paths in the same change.

## Documentation Checklist

When adding, removing, or renaming public APIs:

- update symbol-level DocC comments for the changed public API,
- update `Sourcecode/MattermostSwift/MattermostSwift.docc/MattermostSwift.md` when the quick-start flow changes,
- update `README.md` when install, authentication, live sync, cache, or major supported API coverage changes,
- update `ARCHITECTURE.md` for new layers or important behavior,
- update `TESTING.md` when test scripts add or remove live/e2e coverage,
- update `ROADMAP.md` by moving completed work from "Next Slices" to "Done" where appropriate.

## Release Checklist

Before a public tag:

1. Ensure `CHANGELOG.md` has an entry for the version.
2. Ensure README installation examples use the intended semver requirement.
3. Run `scripts/test-unit.sh`.
4. Run live/e2e scripts only when credentials and a safe test workspace are available.
5. Confirm `git status --short` is clean after committing.
6. Create a fully qualified semantic version tag, such as `0.1.1`.
7. Push the tag so Swift Package Index and SwiftPM can discover the release.

Do not move or recreate an existing release tag unless the user explicitly asks for that history rewrite.

## Security And Secrets

Never print, commit, or place secrets in process arguments. This includes:

- Mattermost bearer tokens,
- username/password credentials,
- `MMAUTHTOKEN` cookie values,
- private server URLs when the user has not already made them public,
- generated SwiftData stores from live accounts.

Prefer environment variables for local credentials and redact values in logs, docs, and test output.
