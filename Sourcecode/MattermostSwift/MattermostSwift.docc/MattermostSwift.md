# MattermostSwift

Build Mattermost clients in Swift with REST commands, WebSocket live events, and a
SwiftData-backed cache.

## Overview

``MattermostClient`` is the root entry point for a single Mattermost server and account. Start
with token or password-session authentication, call its user, team, channel, post, and timeline
operations, then add ``MattermostSyncService`` and ``MattermostLiveSyncService`` when an app needs
offline state.

The SDK doesn't store credentials or provide UI. Host apps own secure token storage, presentation,
and cache retention.

## Topics

### Essentials

- ``MattermostClient``
- <doc:Pagination>
- <doc:ErrorHandling>
- ``MattermostTimelineTarget``
- ``MattermostTimelineRequest``
- ``MattermostTimelinePage``

### Authentication

- <doc:Authentication>
- ``MattermostConfiguration``
- ``MattermostAuthentication``
- ``MattermostSession``
- ``MattermostSessionTokenSource``

### Models

- ``MattermostUser``
- ``MattermostTeam``
- ``MattermostChannel``
- ``MattermostPost``
- ``MattermostPostList``
- ``MattermostThreadResponse``
- ``MattermostFileInfo``
- ``MattermostReaction``

### Caching

- <doc:Caching>
- ``MattermostStore``
- ``MattermostSyncService``
- ``MattermostSyncOptions``
- ``MattermostCachedUserSnapshot``
- ``MattermostCachedChannelSnapshot``
- ``MattermostCachedPostSnapshot``

### Live Events

- <doc:LiveSync>
- ``MattermostLiveEventStream``
- ``MattermostLiveEvent``
- ``MattermostTypedLiveEvent``
- ``MattermostLiveSyncService``
- ``MattermostLiveSyncOptions``
- ``MattermostLiveSyncEvent``
