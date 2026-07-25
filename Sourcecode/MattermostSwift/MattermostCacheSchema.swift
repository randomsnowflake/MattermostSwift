@preconcurrency import SwiftData

/// The first released shape of the MattermostSwift cache.
///
/// Schema versions and migration stages are append-only release artifacts. Future changes must
/// add a complete new snapshot and a stage to `MattermostCacheMigrationPlan`; never edit V1.
enum MattermostCacheSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static let models: [any PersistentModel.Type] = [
        MattermostCachedUser.self,
        MattermostCachedUserStatus.self,
        MattermostCachedTeam.self,
        MattermostCachedChannel.self,
        MattermostCachedChannelMember.self,
        MattermostCachedChannelUnread.self,
        MattermostCachedThread.self,
        MattermostCachedPost.self,
        MattermostCachedReaction.self,
        MattermostCachedFile.self,
        MattermostCachedSidebarCategory.self,
        MattermostSyncCursor.self,
    ]
}

/// Adds conditional-list validators without changing any V1 model.
enum MattermostCacheSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static let models: [any PersistentModel.Type] = [
        MattermostCachedUser.self,
        MattermostCachedUserStatus.self,
        MattermostCachedTeam.self,
        MattermostCachedChannel.self,
        MattermostCachedChannelMember.self,
        MattermostCachedChannelUnread.self,
        MattermostCachedThread.self,
        MattermostCachedPost.self,
        MattermostCachedReaction.self,
        MattermostCachedFile.self,
        MattermostCachedSidebarCategory.self,
        MattermostSyncCursor.self,
        MattermostCacheETag.self,
    ]
}

/// Migration history for stores created by `MattermostStore`'s standard initializer.
enum MattermostCacheMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        MattermostCacheSchemaV1.self,
        MattermostCacheSchemaV2.self,
    ]
    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: MattermostCacheSchemaV1.self, toVersion: MattermostCacheSchemaV2.self),
    ]
}
