# Error Handling

Handle authentication, transport, server, synchronization, and live-delivery failures explicitly.

## Branch on Mattermost Errors

SDK-specific failures use ``MattermostError``:

```swift
do {
    let me = try await client.currentUser()
    print(me.username)
} catch let error as MattermostError {
    switch error {
    case .httpStatus(code: 401, message: _):
        // Discard the rejected local token and present sign-in again.
        print("Authentication required")

    case .httpStatus(let code, let message):
        print("Mattermost HTTP \(code): \(message ?? "no server message")")

    case .transportFailure(let message):
        print("Network transport failed: \(message)")

    case .liveEventGap:
        // Restart live sync so REST backfill reconciles missed events.
        print("Live reconciliation required")

    default:
        print(error.localizedDescription)
    }
} catch {
    print(error.localizedDescription)
}
```

The HTTP layer preserves a server error message when Mattermost supplies one, but callers should
not parse that human-readable string for control flow. Branch on the status code.

## Recover From 401

An HTTP 401 means the configured token is no longer accepted. Remove it from host-owned secure
storage, return to authentication, and build a new ``MattermostClient`` after obtaining a new
token. A client is immutable; don't try to replace authentication in place.

For password sessions, ``MattermostClient/logoutCurrentSession()`` is best-effort remote cleanup,
not a prerequisite for deleting a rejected local token.

## Preserve Sync Correctness

``MattermostError/incompleteSync(_:)`` means a bounded backfill couldn't prove that it captured
every change. Don't advance or replace the last known-good cursor. Increase the relevant page
bound and retry.

``MattermostError/liveEventGap`` means a finite WebSocket queue overflowed. Treat the cache as
potentially stale and restart ``MattermostLiveSyncService`` so it performs REST backfill before
resuming live delivery.

Cancellation can surface as `CancellationError` rather than ``MattermostError``. Preserve it when
ending tasks or async sequences instead of presenting it as a network failure.

## See Also

- <doc:Authentication>
- <doc:Pagination>
- <doc:LiveSync>
