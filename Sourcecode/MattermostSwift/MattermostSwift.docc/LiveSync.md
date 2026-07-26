# Live Sync

Combine reconnecting WebSocket events with REST backfill to maintain a local store.

## Run Live Cache Maintenance

Create and consume live sync on the main actor because it mutates ``MattermostStore``:

```swift
@MainActor
func runLiveSync(
    client: MattermostClient,
    store: MattermostStore,
    channelIDs: [String]
) async throws {
    let stream = client.liveSyncService().events(
        to: store,
        options: MattermostLiveSyncOptions(
            channelIDs: channelIDs,
            maxBackfillChannels: channelIDs.count
        )
    )

    for try await event in stream {
        if let state = event.connectionState {
            print("live sync state: \(state)")
        }

        switch event {
        case .eventApplied(_, let typedEvent):
            print("applied \(typedEvent)")
        case .channelUnreadRefreshed(let unread):
            print("unread \(unread.channelId): \(unread.msgCount)")
        case .backfillFailed(let failure):
            print("backfill failed on attempt \(failure.attempt): \(failure.message)")
        default:
            break
        }
    }
}
```

Before every connection attempt, live sync runs REST backfill and then saves applied events at its
event boundaries. Reconnect backfill uses stored per-channel cursors to recover posts created or
modified while the socket was unavailable.

## Select Backfill Scope

By default, backfill is bounded by the explicitly supplied channel IDs and
`maxBackfillChannels`. For a small workspace or an explicit catch-up action, opt into every joined
channel:

```swift
let options = MattermostLiveSyncOptions(
    backfillAllJoinedChannelPosts: true
)
```

This can generate one or more REST requests per joined channel on every connection and reconnect,
so enable it deliberately.

## Respond to Invalidations

With the corresponding options enabled, live sync refreshes affected unread counts after
`channel_viewed`, `multiple_channels_viewed`, and `post_unread`; refreshes thread state after
thread invalidations; and refreshes sidebar categories after preference changes. These server
reads are authoritative where the service has enough user, team, and channel context.

A finite live-event queue protects memory. If a raw stream consumer falls behind, it finishes with
``MattermostError/liveEventGap``. Restart live sync so its normal authoritative backfill can
reconcile the gap before presenting the cache as current.

Default live-event streams use a dedicated long-lived URL session. When injecting transport
sessions, pass a separate WebSocket session if REST and live events need different timeout
policies.

## See Also

- <doc:Caching>
- <doc:ErrorHandling>
- ``MattermostLiveSyncEvent``
- ``MattermostLiveSyncConnectionState``
