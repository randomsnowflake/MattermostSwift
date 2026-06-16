You are building MattermostSwift, a production-ready Swift Package that provides a high-level SDK for operating a Mattermost chat server from Swift code.

The package must be reusable in future SwiftUI apps, but this package itself must contain no SwiftUI UI components. It may include a CLI executable for testing, debugging, and scripted end-to-end verification.

Core goal

Create a tested, reusable, idiomatic Swift SDK for Mattermost that can fully operate against a Mattermost Community Edition server.

This SDK should support a future fully featured Mattermost chat app and should be semantically interchangeable with the official Mattermost web client where Mattermost API behavior allows it.

Build wide and deep. Do not create a thin toy wrapper. Design a serious chat SDK with clean abstractions, reliable sync, live events, persistence, and integration-test coverage.

Package

Name: MattermostSwift

Swift Package products:

* MattermostSwift library
* MattermostSwiftCLI executable for manual and scripted testing

Supported platforms:

* iOS 26+
* iPadOS 26+
* macOS 26+

No SwiftUI dependency in the library.

Use modern Swift only:

* async/await
* actors where useful
* AsyncSequence / AsyncStream for live streams
* SwiftData for local persistence
* structured concurrency
* Sendable correctness where practical

Do not use Combine.

Authentication

Support simple non-OAuth authentication:

* Personal access token auth
* Username/password login if Mattermost supports it cleanly

Credential storage is the responsibility of the host app. Do not store credentials in Keychain inside the library.

Never hardcode credentials. Never commit secrets. Never print secrets in logs.

Read development/test credentials from environment variables:

* MATTERMOST_URL
* MATTERMOST_TOKEN
* MATTERMOST_USERNAME
* MATTERMOST_PASSWORD
* MATTERMOST_TEAM_NAME

The SDK only needs to handle one server and one account at a time. No multi-account abstraction for now.

Mattermost API strategy

Use whatever official Mattermost APIs provide the most complete and correct implementation.

Expected approach:

* REST API for normal commands, fetching, pagination, search, uploads, mutations
* WebSocket API for streaming events, message updates, typing, presence, deletes, edits, reactions, channel changes, unread changes, etc.

Before implementing, inspect the available Mattermost API documentation and the actual server behavior. Prefer official API semantics over guessing.

The target development server runs the newest Mattermost Community Edition.

Architecture expectation

Expose a high-level SDK, not just raw endpoint functions.

Suggested top-level API shape:

* MattermostClient
* MattermostSession
* ChannelService
* PostService
* ThreadService
* FileService
* UserService
* ReactionService
* SearchService
* NotificationService
* SidebarCategoryService
* SyncService
* LiveEventStream
* MattermostStore

Design clean public models and map Mattermost API models internally.

The SDK should let host apps do things like:

* authenticate
* load current user
* load team
* list channels
* list sidebar categories
* load posts
* load threads
* send posts
* edit posts
* delete posts
* react/unreact
* upload/download files
* search messages
* observe live events
* maintain local cache
* sync incrementally
* manage channels
* manage sidebar categories
* handle unread state
* handle notification state
* handle typing indicators

Keep API ergonomic. A host app should not need to know random endpoint details to build a chat frontend.

Required features

Implement support for:

Team/server basics

* Connect to one Mattermost server
* Resolve current user
* Resolve configured team
* Load team metadata
* Basic server/version capability probing if useful

Channels

* List channels
* List joined channels
* Get channel details
* Create channel
* Rename channel
* Archive/delete channel where supported
* Move/manage channels in sidebar categories where supported
* Channel membership
* Unread counts
* Notification state
* Channel search if available

Sidebar categories

Support Mattermost sidebar categories for the configured team:

* List categories
* Create category
* Rename category
* Delete category
* Move channels between categories
* Reorder categories/channels where supported

Messages/posts

* Fetch channel messages with pagination
* Send message
* Edit message
* Delete message
* Fetch updates since a cursor/timestamp
* Handle message props/metadata as needed
* Correctly handle root posts and replies
* Correctly model deleted/edited messages
* Support markdown/plain Mattermost message body as provided by the API

Threads

Implement threaded conversations using Mattermost post/root semantics.

Support:

* Root post
* Replies
* Thread loading
* Thread updates
* Collapsed Reply Threads behavior if enabled on server
* A unified abstraction that lets consumers work with channel timelines and thread timelines without awkward branching

Live streaming

Use WebSocket events to receive and expose:

* new posts
* edited posts
* deleted posts
* reactions
* typing indicators
* channel changes
* sidebar/category changes where available
* unread/notification changes where available
* relevant user/profile changes
* reconnect events
* sync invalidation events

WebSocket behavior must include:

* automatic connect
* authenticated connection
* reconnect with backoff
* heartbeat/ping handling if required
* clear lifecycle API
* safe shutdown
* event decoding with unknown-event tolerance

Expose live updates as AsyncSequence / AsyncStream.

Users

* Current user
* Basic user profile view data
* Lookup user by id
* Lookup users in channel
* Basic presence/online state if supported and useful

Reactions / emoji

* Add reaction
* Remove reaction
* List reactions for post if needed
* Decode reaction events live
* Handle custom emoji metadata if supported without overcomplicating v1

Search

* Search posts/messages
* Return useful result models
* Support pagination if API allows

Files

Keep files simple but real:

* Upload file
* Attach file to post
* Download file
* Basic file metadata
* Progress callbacks if easy and clean
* No elaborate media cache required unless needed for correctness

Typing indicators

* Send typing event
* Receive typing events
* Expose typing state/events to host app

Local persistence

Use SwiftData for local persistence.

Support:

* users
* channels
* sidebar categories
* posts
* threads/replies
* reactions
* files metadata
* unread state
* sync cursors/timestamps

The store should support offline cache reads and incremental sync.

Host apps should be able to use the SDK in an offline-first-ish way:

* load cached data quickly
* sync with server
* receive live updates
* keep local state coherent

Do not overengineer into a full database framework. Keep it clean and KISS.

CLI

Create MattermostSwiftCLI.

The CLI is not a user-facing chat client. It is a developer/test harness.

It should support commands such as:

* me
* server-info
* list-channels
* list-categories
* create-test-channel
* rename-test-channel
* send-message
* edit-message
* delete-message
* thread-test
* reaction-test
* upload-file
* download-file
* search
* stream-events
* sync
* e2e-test

Use the CLI in scripts to verify SDK behavior against the real server.

Testing

Create both mocked tests and live end-to-end tests.

Mocked/unit tests:

* API decoding
* request construction
* model mapping
* persistence behavior
* sync merging
* websocket event decoding
* pagination handling
* error handling

Live tests:

* Run against the configured Mattermost server using env vars
* Create isolated test channels/categories/posts
* Use a clear test prefix, e.g. mmswift-test-
* Clean up after tests where safe
* Verify real end-to-end flows

Live tests should include:

* authenticate
* current user
* list channels
* create channel
* rename channel
* create sidebar category
* move channel into category if supported
* send message
* edit message
* reply/thread
* reaction add/remove
* file upload/download
* search
* typing event if possible
* websocket receive for posted/edited/deleted messages
* unread/sync behavior where practical
* delete/archive cleanup

Do not require GitHub Actions.

Provide local scripts, for example:

* scripts/test-unit.sh
* scripts/test-live.sh
* scripts/test-e2e.sh

The scripts may assume env vars are set.

Documentation

Include:

* README.md
* ROADMAP.md
* ARCHITECTURE.md
* TESTING.md
* .env.example
* Doc comments on public APIs
* MIT license

README should show:

* installation as Swift package
* minimal auth example
* listing channels
* sending a message
* observing live events
* using persistence
* running CLI tests

Do not include private server URL or credentials in docs.

Code quality

Production-ready means:

* small cohesive types
* clean errors
* typed API responses
* clear public API
* no hardcoded server assumptions
* no force unwraps in library code
* no swallowed errors
* no giant god classes
* no fake tests
* no TODO-driven architecture
* no placeholder implementations pretending to work

Prefer simple, boring, correct code.

Use regular review/refactoring passes. Apply the available refactoring/review skills, including Ponytail-style simplification if available, to keep the codebase clean and KISS.

Goal loop workflow

Work in goal-loop iterations.

Each loop should:

1. State the current goal.
2. Inspect existing code/docs/API behavior.
3. Implement a small coherent slice.
4. Add or update tests.
5. Run relevant tests or CLI verification.
6. Fix failures.
7. Refactor.
8. Update docs/roadmap.
9. Record progress and remaining gaps.

Do not stop after a shallow skeleton. Continue until the SDK is genuinely usable.

However, avoid pretending completeness. If a Mattermost feature is blocked by API limitations or unclear server behavior, document it precisely in ROADMAP.md with evidence.

Definition of done

The task is done when:

* The package builds cleanly.
* Unit tests pass.
* CLI works.
* Live e2e tests work against the real server using env vars.
* Core chat operations work.
* Live websocket events work.
* SwiftData persistence works.
* Offline cached reads work.
* Incremental sync works.
* Channel/sidebar/message/thread/reaction/file/search/typing features are implemented.
* Public API is documented enough to use from another Swift app.
* No secrets are committed.
* The repo is ready to publish publicly on GitHub under MIT license.

Aim for a serious first public release, not a demo.

One more tweak I’d add to your agent command before launching:

“Start by creating ARCHITECTURE.md and an executable MattermostSwiftCLI. Do not implement broad features before the first live authentication + me + list-channels flow works end-to-end.”

That prevents the classic agent disease: architecture fanfic before the first HTTP call works.
