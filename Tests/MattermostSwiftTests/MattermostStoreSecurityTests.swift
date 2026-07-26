import Foundation
import Testing
@testable import MattermostSwift

@MainActor
@Test("Disk-backed store hardens its directory")
func diskBackedStoreHardensDirectory() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("MattermostStoreSecurityTests-\(UUID().uuidString)", isDirectory: true)
    let directory = root.appendingPathComponent("cache", isDirectory: true)
    let storeURL = directory.appendingPathComponent("MattermostSwift.sqlite")
    try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: UInt16(0o755))]
    )
    defer { try? fileManager.removeItem(at: root) }

    do {
        _ = try MattermostStore(
            url: storeURL,
            security: MattermostStoreSecurityOptions(fileProtection: .platformDefault)
        )
    }

    #expect(try posixPermissions(at: directory, fileManager: fileManager) == 0o700)
}

@Test("Store directory permissions are host configurable")
func storeDirectoryPermissionsAreConfigurable() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("MattermostStoreSecurityTests-\(UUID().uuidString)", isDirectory: true)
    let directory = root.appendingPathComponent("shared", isDirectory: true)
    let storeURL = directory.appendingPathComponent("MattermostSwift.sqlite")
    try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: UInt16(0o750))]
    )
    defer { try? fileManager.removeItem(at: root) }

    try MattermostStoreFilesystemSecurity.prepareStoreDirectory(
        for: storeURL,
        options: MattermostStoreSecurityOptions(
            directoryPermissions: nil,
            fileProtection: .platformDefault
        ),
        fileManager: fileManager
    )

    #expect(try posixPermissions(at: directory, fileManager: fileManager) == 0o750)
}

@Test("Store security creates a missing directory with owner-only permissions")
func storeSecurityCreatesRestrictiveDirectory() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("MattermostStoreSecurityTests-\(UUID().uuidString)", isDirectory: true)
    let directory = root.appendingPathComponent("new-cache", isDirectory: true)
    let storeURL = directory.appendingPathComponent("MattermostSwift.sqlite")
    defer { try? fileManager.removeItem(at: root) }

    try MattermostStoreFilesystemSecurity.prepareStoreDirectory(
        for: storeURL,
        options: MattermostStoreSecurityOptions(fileProtection: .platformDefault),
        fileManager: fileManager
    )

    #expect(try posixPermissions(at: directory, fileManager: fileManager) == 0o700)
}

#if os(iOS)
@Test("Store file protection is applied and configurable")
func storeFileProtectionIsAppliedAndConfigurable() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("MattermostStoreSecurityTests-\(UUID().uuidString)", isDirectory: true)
    let storeURL = root.appendingPathComponent("MattermostSwift.sqlite")
    defer { try? fileManager.removeItem(at: root) }

    try MattermostStoreFilesystemSecurity.prepareStoreDirectory(
        for: storeURL,
        options: MattermostStoreSecurityOptions(fileProtection: .complete),
        fileManager: fileManager
    )

    let attributes = try fileManager.attributesOfItem(atPath: root.path)
    #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
}
#endif

private func posixPermissions(at url: URL, fileManager: FileManager) throws -> UInt16 {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    let value = try #require(attributes[.posixPermissions] as? NSNumber)
    return value.uint16Value & 0o777
}
