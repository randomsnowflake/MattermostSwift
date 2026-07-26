import Foundation
import Testing
import MattermostSwift
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

    @Test("ArgumentParser maps representative commands")
    func commandParsing() throws {
        #expect(try MattermostSwiftCLI.parseInvocation(["me"]).command == .me)
        #expect(try MattermostSwiftCLI.parseInvocation(["check"]).command == .check)
        #expect(
            try MattermostSwiftCLI.parseInvocation(["get-user", "abc123"]).command
                == .getUser(userID: "abc123")
        )
        #expect(
            try MattermostSwiftCLI.parseInvocation(["get-user"]).command
                == .getUser(userID: "me")
        )
        #expect(
            try MattermostSwiftCLI.parseInvocation(["send-message", "hello", "world"]).command
                == .sendMessage(channelID: nil, message: "hello world")
        )
        #expect(
            try MattermostSwiftCLI.parseInvocation(["diag", "reaction-test"]).command
                == .reactionTest
        )
    }

    @Test("Flags parse in any position")
    func flagsParseInAnyPosition() throws {
        let expected = Command.sendMessage(channelID: "chan", message: "hello world")
        #expect(
            try MattermostSwiftCLI.parseInvocation(
                ["send-message", "--channel", "chan", "hello", "world"]
            ).command == expected
        )
        #expect(
            try MattermostSwiftCLI.parseInvocation(
                ["send-message", "hello", "--channel", "chan", "world"]
            ).command == expected
        )
        #expect(
            try MattermostSwiftCLI.parseInvocation(
                ["send-message", "hello", "world", "--channel", "chan"]
            ).command == expected
        )
        #expect(
            try MattermostSwiftCLI.parseInvocation(
                ["channel-members-by-id", "user-a", "user-b", "--channel", "chan"]
            ).command == .channelMembersByID(
                channelID: "chan",
                userIDs: ["user-a", "user-b"]
            )
        )
        #expect(
            try MattermostSwiftCLI.parseInvocation(
                ["known-users", "--profiles"]
            ).command == .knownUsers(includeProfiles: true)
        )
    }

    @Test("Global JSON parses before and after nested commands")
    func globalJSONPosition() throws {
        let before = try MattermostSwiftCLI.parseInvocation(["--json", "me"])
        let after = try MattermostSwiftCLI.parseInvocation(["me", "--json"])
        let nestedBefore = try MattermostSwiftCLI.parseInvocation(
            ["--json", "diag", "reaction-test"]
        )
        let nestedAfter = try MattermostSwiftCLI.parseInvocation(
            ["diag", "reaction-test", "--json"]
        )

        #expect(before == ParsedCLIInvocation(command: .me, json: true))
        #expect(after == before)
        #expect(nestedBefore == ParsedCLIInvocation(command: .reactionTest, json: true))
        #expect(nestedAfter == nestedBefore)
    }

    @Test("Invalid and missing values fail parsing")
    func invalidValuesFail() {
        #expect(throws: (any Error).self) {
            try MattermostSwiftCLI.parseInvocation(["stream-events", "not-a-number"])
        }
        #expect(throws: (any Error).self) {
            try MattermostSwiftCLI.parseInvocation(["stream-events", "0"])
        }
        #expect(throws: (any Error).self) {
            try MattermostSwiftCLI.parseInvocation(["list-post-updates", "yesterday"])
        }
        #expect(throws: (any Error).self) {
            try MattermostSwiftCLI.parseInvocation(["send-message"])
        }
        #expect(throws: (any Error).self) {
            try MattermostSwiftCLI.parseInvocation(["totally-unknown-command"])
        }
        #expect(throws: (any Error).self) {
            try MattermostSwiftCLI.parseInvocation(["reaction-test"])
        }
    }

    @Test("Generated help separates diagnostics and documents each command")
    func generatedHelp() {
        let rootHelp = RootCommand.helpMessage()
        let sendHelp = SendMessage.helpMessage()
        let diagnosticsHelp = Diagnostics.helpMessage()

        #expect(rootHelp.contains("MattermostSwiftCLI"))
        #expect(rootHelp.contains("--json"))
        #expect(rootHelp.contains("diag"))
        #expect(!rootHelp.contains("reaction-test"))
        #expect(sendHelp.contains("--channel"))
        #expect(sendHelp.contains("<message>"))
        #expect(diagnosticsHelp.contains("reaction-test"))
        #expect(diagnosticsHelp.contains("all-channel-backfill-test"))
    }

    @Test("JSON encoding is stable and preserves post content")
    func stableLosslessJSON() throws {
        let post = MattermostPost(
            id: "post",
            createAt: 1,
            updateAt: 2,
            editAt: 0,
            deleteAt: 0,
            userId: "user",
            channelId: "channel",
            rootId: "",
            originalId: nil,
            message: "first line\nsecond\tline",
            type: .standard,
            hashtags: nil,
            pendingPostId: nil,
            fileIds: ["file"],
            hasReactions: true,
            props: ["nested": .object(["value": .string("kept")])],
            metadata: nil,
            replyCount: 0,
            lastReplyAt: 0
        )

        let first = try MattermostSwiftCLI.encodedJSON(post)
        let second = try MattermostSwiftCLI.encodedJSON(post)
        let decoded = try JSONDecoder().decode(MattermostPost.self, from: first)
        let object = try #require(
            JSONSerialization.jsonObject(with: first) as? [String: Any]
        )

        #expect(first == second)
        #expect(decoded.message == "first line\nsecond\tline")
        #expect(decoded.props == post.props)
        #expect(object["message"] as? String == "first line\nsecond\tline")
    }

    @Test("TTY progress and binary guards are deterministic")
    func ttyBehavior() throws {
        #expect(
            MattermostSwiftCLI.progressLine("Working…", stderrIsTTY: false) == nil
        )
        #expect(
            MattermostSwiftCLI.progressLine("Working…", stderrIsTTY: true)
                == "Working…\n"
        )
        try MattermostSwiftCLI.validateBinaryStandardOutput(
            path: "/tmp/download.bin",
            json: false,
            stdoutIsTTY: true
        )
        try MattermostSwiftCLI.validateBinaryStandardOutput(
            path: nil,
            json: true,
            stdoutIsTTY: true
        )
        #expect(throws: CLIError.self) {
            try MattermostSwiftCLI.validateBinaryStandardOutput(
                path: nil,
                json: false,
                stdoutIsTTY: true
            )
        }
    }

    @Test("CLI process generates help and version and exits 2 for invalid input")
    func processBehavior() throws {
        let executable = try cliExecutableURL()

        let help = try runProcess(executable, arguments: ["--help"])
        #expect(help.status == 0)
        #expect(help.stdout.contains("USAGE: MattermostSwiftCLI"))
        #expect(help.stdout.contains("diag"))

        let subcommandHelp = try runProcess(
            executable,
            arguments: ["send-message", "--help"]
        )
        #expect(subcommandHelp.status == 0)
        #expect(subcommandHelp.stdout.contains("--channel"))

        let version = try runProcess(executable, arguments: ["--version"])
        #expect(version.status == 0)
        #expect(version.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "0.1.0")

        let completions = try runProcess(
            executable,
            arguments: ["--generate-completion-script", "bash"]
        )
        #expect(completions.status == 0)
        #expect(completions.stdout.contains("MattermostSwiftCLI"))

        let invalid = try runProcess(
            executable,
            arguments: ["stream-events", "not-a-number"]
        )
        #expect(invalid.status == 2)
        #expect(invalid.stderr.lowercased().contains("error"))
    }

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func cliExecutableURL() throws -> URL {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()

        for _ in 0..<7 {
            let candidate = directory.appendingPathComponent("MattermostSwiftCLI")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        // Under the xctest runner argv[0] points outside .build, so fall back to scanning it.
        // Prefer this test run's build configuration: a stale binary left behind by an
        // earlier build of the other configuration would otherwise win the enumeration.
#if DEBUG
        let preferredConfiguration = "debug"
#else
        let preferredConfiguration = "release"
#endif
        let buildDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent(".build")
        var candidates: [URL] = []
        if let enumerator = fileManager.enumerator(
            at: buildDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let candidate as URL in enumerator
            where candidate.lastPathComponent == "MattermostSwiftCLI"
                && fileManager.isExecutableFile(atPath: candidate.path) {
                candidates.append(candidate)
            }
        }

        if let match = candidates.first(where: {
            $0.deletingLastPathComponent().lastPathComponent == preferredConfiguration
        }) {
            return match
        }
        if let anyCandidate = candidates.first {
            return anyCandidate
        }

        throw CLIError.usage("Could not locate the built MattermostSwiftCLI executable.")
    }

    private func runProcess(_ executable: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
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

    private func permissions(at url: URL, fileManager: FileManager) throws -> UInt16 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let value = try #require(attributes[.posixPermissions] as? NSNumber)
        return value.uint16Value & 0o777
    }

}
