# Security Policy

## Supported Versions

MattermostSwift is currently pre-`1.0.0`. Security fixes are expected to land on `main` first and be included in the next tagged release.

## Reporting a Vulnerability

Please do not open a public issue for token handling, credential leakage, authentication bypass, transport security, or other sensitive vulnerabilities.

Report security issues privately through GitHub's private vulnerability reporting for this repository when available, or contact the maintainer directly through the GitHub profile for `randomsnowflake`.

Include:

- affected version or commit,
- a concise reproduction,
- expected and observed behavior,
- whether credentials, tokens, cookies, or server logs are involved.

## Credential Handling Expectations

MattermostSwift must not persist tokens for host apps. The SDK returns tokens to callers, and host apps are responsible for storing them securely, such as in Keychain on Apple platforms.

Tests and CLI tools read credentials from environment variables. Do not commit real Mattermost URLs, tokens, usernames, passwords, channel IDs from private workspaces, captured cookies, or generated local stores.
