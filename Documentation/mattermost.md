

# Native SwiftUI Mattermost Client — Research (2026-06-16)

**Goal:** Multiplatform (iOS 26 / iPadOS / macOS) chat client for the self-hosted Mattermost server. Send text messages, render/exchange markdown with the AI bot (@hermes/@tincan). Modern, fun, visually-pleasing UI.

---

## 1. Feasibility — ✅ YES, fully buildable

Mattermost exposes a complete, documented **REST API v4** + **WebSocket API** that together cover everything a chat client needs: teams, channels, DMs, posts, threads, reactions, file attachments, presence, typing, real-time delivery. You build it from scratch with `URLSession` + `URLSessionWebSocketTask` + `Codable`.

- **No native Swift/SwiftUI Mattermost SDK exists.** Official mobile app is React Native; only `diegotl/MattermostKit` exists and it's webhook-send only (useful as a Codable-model reference, not a foundation). You'd be building the first native client → wrap REST + WS yourself.
- **AI bot needs nothing special client-side.** @hermes/@tincan is a server-side bot account; its replies arrive as ordinary `posted` events over the WebSocket and via normal channel-history REST. Just send a post and receive the reply like any message. For 1:1, `POST /channels/direct` with `[me, bot_id]`.

### API map (feature → mechanism)
- Base: `https://<server>/api/v4`, JSON. Auth: `Authorization: Bearer <token>`.
- Channels: `GET /users/me/teams/{team}/channels`; DM: `POST /channels/direct`.
- History (paginated, `per_page`≤200): `GET /channels/{id}/posts?since=&before=&after=` → `{posts:{id→post}, order:[...]}` (render by `order`).
- Send/reply: `POST /posts` (`channel_id`, `message`, `root_id`, `file_ids`, `props`). Edit `PUT/PATCH /posts/{id}`, delete `DELETE /posts/{id}`.
- Thread: `GET /posts/{id}/thread`. Mark read: `POST /channels/members/me/view`.
- Reactions: `POST /reactions`. Files: `POST /files` → `GET /files/{id}` (+`/thumbnail`,`/preview`).
- Presence: `GET /users/status/ids` (batch). Markdown: server stores **raw** markdown in `post.message` → **client renders it**.

### Auth — use a Personal Access Token (PAT)
Long-lived, bypasses CSRF/cookies, works for both REST (`Bearer`) and the WS auth challenge. Store in **Keychain**. Must be enabled server-side (System Console → Integrations). Fallback if disabled: `POST /users/login` (token returned in the `Token` response header; MFA/TOTP goes in the `token` field). OAuth2 exists but overkill here.

### WebSocket real-time design
- Connect `wss://<server>/api/v4/websocket`, then send first:
  `{"seq":1,"action":"authentication_challenge","data":{"token":"<PAT>"}}`
- Events: `posted`, `post_edited`, `post_deleted`, `reaction_added/removed`, `typing`, `status_change`, `channel_viewed`.
- 🔴 **`data.post` is a JSON string inside JSON — double-parse it.** Most common bug.
- WS is a live tail, not a replay. On (re)connect, backfill missed posts via REST `since=<ms epoch>` per channel. Build your own exponential-backoff reconnect (~3s→cap ~60s), re-auth each reconnect, heartbeat with `sendPing`. `URLSessionWebSocketTask` does ping/pong; you own reconnect + the receive loop (must recurse/loop or delivery stops).

### Other gotchas
- `root_id` is empty string `""` for root posts (not null); replies set it to the thread root.
- Max ~5 files per post. Rate limits off by default; honor 429 + `X-Ratelimit-*` if enabled.
- Self-signed cert on the self-hosted server → `URLSessionDelegate` trust override.
- `typing`/`channel_viewed` events can be disabled server-side — don't assume.

## Sources
- API: https://api.mattermost.com · https://developers.mattermost.com/api-documentation/ · PAT: https://developers.mattermost.com/integrate/reference/personal-access-token/ · Bots: https://developers.mattermost.com/integrate/reference/bot-accounts/



