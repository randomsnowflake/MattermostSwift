## Summary

Describe the problem and the focused Mattermost SDK vertical slice changed by this pull request.

## Verification

List the exact commands run and any checks that could not be run.

## Checklist

- [ ] `scripts/lint.sh` passes.
- [ ] `scripts/test-unit.sh` passes.
- [ ] New behavior has request-construction, decoding, and cache/update tests where applicable.
- [ ] New public symbols have DocC comments and appropriate `Sendable` and `Hashable` conformances.
- [ ] User-facing changes are recorded in `CHANGELOG.md`.
- [ ] README, DocC, architecture, testing, and roadmap documentation are updated where applicable.
- [ ] Live/e2e tests were run only against a safe workspace, or are explicitly marked as not run.
- [ ] No secrets, credentials, cookies, private server data, or generated stores are included.
