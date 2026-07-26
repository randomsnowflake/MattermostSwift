import Foundation

/// Apple file-protection policy for a disk-backed Mattermost cache.
///
/// File protection is applied to the store directory and SQLite files on iOS.
/// Other supported platforms ignore this setting; macOS hosts should protect the
/// volume with FileVault and choose an appropriately secured store location.
public enum MattermostStoreFileProtection: Sendable, Equatable {
    /// Use the platform or host application's existing file-protection policy.
    case platformDefault

    /// Make the cache available only while the device is unlocked.
    case complete

    /// Keep an already-open cache available while locked, then protect it when closed.
    case completeUnlessOpen

    /// Make the cache available after the first device unlock following a restart.
    case completeUntilFirstUserAuthentication

    /// Explicitly disable Apple file protection.
    case none
}

/// Filesystem security applied when `MattermostStore` opens a disk-backed cache.
public struct MattermostStoreSecurityOptions: Sendable {
    /// POSIX mode applied to the store directory.
    ///
    /// The secure default is owner-only access (`0700`). Pass `nil` only when the
    /// directory is shared and its permissions are managed by the host application.
    public var directoryPermissions: UInt16?

    /// Apple file-protection policy for the store directory and SQLite files.
    public var fileProtection: MattermostStoreFileProtection

    /// Creates a cache security policy.
    ///
    /// - Parameters:
    ///   - directoryPermissions: POSIX directory mode, or `nil` to leave it unchanged.
    ///   - fileProtection: Apple file-protection policy. The default balances at-rest
    ///     protection with background sync after the first unlock.
    public init(
        directoryPermissions: UInt16? = 0o700,
        fileProtection: MattermostStoreFileProtection = .completeUntilFirstUserAuthentication
    ) {
        self.directoryPermissions = directoryPermissions
        self.fileProtection = fileProtection
    }
}

enum MattermostStoreFilesystemSecurity {
    static func prepareStoreDirectory(
        for storeURL: URL,
        options: MattermostStoreSecurityOptions,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        var attributes: [FileAttributeKey: Any] = [:]
        if let permissions = options.directoryPermissions {
            attributes[.posixPermissions] = NSNumber(value: permissions)
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: attributes.isEmpty ? nil : attributes
        )

        // createDirectory does not update an existing directory. Apply the requested
        // mode explicitly so caches created by older SDK versions are hardened too.
        if let permissions = options.directoryPermissions {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: permissions)],
                ofItemAtPath: directoryURL.path
            )
        }

        try applyFileProtection(options.fileProtection, to: directoryURL, fileManager: fileManager)
    }

    static func secureStoreFiles(
        at storeURL: URL,
        options: MattermostStoreSecurityOptions,
        fileManager: FileManager = .default
    ) throws {
        guard options.fileProtection != .platformDefault else { return }

        for url in [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ] where fileManager.fileExists(atPath: url.path) {
            try applyFileProtection(options.fileProtection, to: url, fileManager: fileManager)
        }
    }

    private static func applyFileProtection(
        _ protection: MattermostStoreFileProtection,
        to url: URL,
        fileManager: FileManager
    ) throws {
        #if os(iOS)
        let value: FileProtectionType
        switch protection {
        case .platformDefault:
            return
        case .complete:
            value = .complete
        case .completeUnlessOpen:
            value = .completeUnlessOpen
        case .completeUntilFirstUserAuthentication:
            value = .completeUntilFirstUserAuthentication
        case .none:
            value = .none
        }

        try fileManager.setAttributes(
            [.protectionKey: value],
            ofItemAtPath: url.path
        )
        #else
        _ = protection
        _ = url
        _ = fileManager
        #endif
    }
}
