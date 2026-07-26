import Foundation
import Testing
@testable import MattermostSwiftCLI

@Suite("CLI helper logic")
struct CLIHelpersTests {
    @Test("contentType maps known extensions")
    func contentTypeMapsKnownExtensions() {
        #expect(MattermostSwiftCLI.contentType(for: URL(fileURLWithPath: "/tmp/notes.txt")) == "text/plain")
        #expect(MattermostSwiftCLI.contentType(for: URL(fileURLWithPath: "/tmp/data.json")) == "application/json")
        #expect(MattermostSwiftCLI.contentType(for: URL(fileURLWithPath: "/tmp/image.png")) == "image/png")
        #expect(MattermostSwiftCLI.contentType(for: URL(fileURLWithPath: "/tmp/photo.jpg")) == "image/jpeg")
        #expect(MattermostSwiftCLI.contentType(for: URL(fileURLWithPath: "/tmp/photo.jpeg")) == "image/jpeg")
        #expect(MattermostSwiftCLI.contentType(for: URL(fileURLWithPath: "/tmp/doc.pdf")) == "application/pdf")
    }

    @Test("contentType falls back for unknown extensions")
    func contentTypeFallback() {
        #expect(MattermostSwiftCLI.contentType(for: URL(fileURLWithPath: "/tmp/archive.zip")) == "application/octet-stream")
        #expect(MattermostSwiftCLI.contentType(for: URL(fileURLWithPath: "/tmp/noext")) == "application/octet-stream")
    }

    @Test("imageSignature detects magic bytes")
    func imageSignatureDetectsMagicBytes() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        let riff = Data([0x52, 0x49, 0x46, 0x46, 0x00])
        let unknown = Data([0x00, 0x01, 0x02, 0x03])

        #expect(MattermostSwiftCLI.imageSignature(for: png) == "png")
        #expect(MattermostSwiftCLI.imageSignature(for: jpeg) == "jpeg")
        #expect(MattermostSwiftCLI.imageSignature(for: gif) == "gif")
        #expect(MattermostSwiftCLI.imageSignature(for: riff) == "webp-or-riff")
        #expect(MattermostSwiftCLI.imageSignature(for: unknown) == "unknown")
        #expect(MattermostSwiftCLI.imageSignature(for: Data()) == "unknown")
    }

    @Test("resolvedStoreURL creates and hardens the default cache directory")
    func resolvedStoreURLHardensDefaultDirectory() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MattermostSwiftCLITests-\(UUID().uuidString)", isDirectory: true)
        let cacheDirectory = root.appendingPathComponent(".mattermostswift", isDirectory: true)
        try fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: UInt16(0o755))]
        )
        defer { try? fileManager.removeItem(at: root) }

        let url = try MattermostSwiftCLI.resolvedStoreURL(
            fileManager: fileManager,
            environment: [:],
            currentDirectoryURL: root
        )

        #expect(url == cacheDirectory.appendingPathComponent("MattermostSwift.sqlite"))
        #expect(try permissions(at: cacheDirectory, fileManager: fileManager) == 0o700)
    }

    @Test("resolvedStoreURL secures a custom cache directory")
    func resolvedStoreURLSecuresCustomDirectory() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MattermostSwiftCLITests-\(UUID().uuidString)", isDirectory: true)
        let expectedURL = root
            .appendingPathComponent("custom", isDirectory: true)
            .appendingPathComponent("cache.sqlite")
        defer { try? fileManager.removeItem(at: root) }

        let url = try MattermostSwiftCLI.resolvedStoreURL(
            fileManager: fileManager,
            environment: ["MATTERMOST_STORE_PATH": expectedURL.path],
            currentDirectoryURL: nil
        )

        #expect(url == expectedURL.standardizedFileURL)
        #expect(try permissions(at: expectedURL.deletingLastPathComponent(), fileManager: fileManager) == 0o700)
    }

    @Test("Command parses representative argv arrays")
    func commandParsing() {
        #expect(Command(arguments: ["me"]) == .me)
        #expect(Command(arguments: ["check"]) == .check)
        #expect(Command(arguments: ["get-user", "abc123"]) == .getUser(userID: "abc123"))
        #expect(Command(arguments: ["get-user"]) == .getUser(userID: "me"))
        #expect(Command(arguments: ["send-message", "hello", "world"]) == .sendMessage(channelID: nil, message: "hello world"))
        #expect(Command(arguments: ["send-message", "--channel", "chan", "hello", "world"]) == .sendMessage(channelID: "chan", message: "hello world"))
        #expect(Command(arguments: []) == .help)
        #expect(Command(arguments: ["--help"]) == .help)
        #expect(
            Command(arguments: ["totally-unknown-command"])
                == .usageError("unknown command 'totally-unknown-command'")
        )
        #expect(
            Command(arguments: ["send-message"])
                == .usageError("send-message requires a message")
        )
        #expect(
            Command(arguments: ["create-group-channel", "one-user"])
                == .usageError("create-group-channel requires at least two user ids")
        )
    }

    @Test("--help succeeds without Mattermost credentials and writes only stdout")
    func helpProcessBehavior() throws {
        for arguments in [[], ["--help"]] {
            let result = try #require(MattermostSwiftCLI.processPlan(arguments: arguments))

            #expect(result.status == 0)
            #expect(result.stdout.contains("MattermostSwiftCLI"))
            #expect(result.stdout.contains("Usage:"))
            #expect(result.stderr.isEmpty)
        }
    }

    @Test("unknown and malformed commands fail with usage diagnostics")
    func usageErrorProcessBehavior() throws {
        let unknown = try #require(
            MattermostSwiftCLI.processPlan(arguments: ["totally-unknown-command"])
        )
        #expect(unknown.status == 2)
        #expect(unknown.stdout.isEmpty)
        #expect(unknown.stderr == "error: unknown command 'totally-unknown-command'\n")

        let malformed = try #require(
            MattermostSwiftCLI.processPlan(arguments: ["send-message"])
        )
        #expect(malformed.status == 2)
        #expect(malformed.stdout.isEmpty)
        #expect(malformed.stderr == "error: send-message requires a message\n")
    }

    @Test("malformed parser branches provide specific diagnostics")
    func malformedParserDiagnostics() {
        let cases: [([String], Command)] = [
            (["get-users"], .usageError("get-users requires at least one user id")),
            (["get-users-by-username"], .usageError("get-users-by-username requires at least one username")),
            (["search-users"], .usageError("search-users requires search terms")),
            (["autocomplete-users"], .usageError("autocomplete-users requires a name")),
            (["channel-by-name"], .usageError("channel-by-name requires exactly one channel name")),
            (
                ["channel-by-name", "--team", "team-only"],
                .usageError("channel-by-name requires a team id and channel name after --team")
            ),
            (
                ["channel-by-team-name", "team-only"],
                .usageError("channel-by-team-name requires a team name and channel name")
            ),
            (["search-channels"], .usageError("search-channels requires search terms")),
            (["search-group-channels"], .usageError("search-group-channels requires search terms")),
            (
                ["create-group-channel", "one-user"],
                .usageError("create-group-channel requires at least two user ids")
            ),
            (["channel-members-by-id"], .usageError("channel-members-by-id requires at least one user id")),
            (["add-channel-member"], .usageError("add-channel-member requires exactly one user id")),
            (["remove-channel-member"], .usageError("remove-channel-member requires exactly one user id")),
            (["send-message"], .usageError("send-message requires a message")),
            (
                ["send-message", "--channel", "channel-only"],
                .usageError("send-message requires a channel id and message after --channel")
            ),
            (["edit-message"], .usageError("edit-message requires a post id and message")),
            (["edit-message", "post-only"], .usageError("edit-message requires a message")),
            (["delete-message"], .usageError("delete-message requires a post id")),
            (
                ["list-post-updates", "not-a-timestamp"],
                .usageError("list-post-updates requires a numeric since timestamp")
            ),
            (["search"], .usageError("search requires search terms")),
            (["upload-file"], .usageError("upload-file requires a path")),
            (
                ["upload-file", "--channel", "channel-only"],
                .usageError("upload-file requires a channel id and path after --channel")
            ),
            (["download-file"], .usageError("download-file requires a file id")),
            (["search-emoji"], .usageError("search-emoji requires a search term")),
        ]

        for (arguments, expected) in cases {
            #expect(Command(arguments: arguments) == expected)
        }
    }

    private func permissions(at url: URL, fileManager: FileManager) throws -> UInt16 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let value = try #require(attributes[.posixPermissions] as? NSNumber)
        return value.uint16Value & 0o777
    }
}
