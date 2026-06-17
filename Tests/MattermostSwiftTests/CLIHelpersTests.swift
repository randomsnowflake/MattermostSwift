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

    @Test("Command parses representative argv arrays")
    func commandParsing() {
        #expect(Command(arguments: ["me"]) == .me)
        #expect(Command(arguments: ["check"]) == .check)
        #expect(Command(arguments: ["get-user", "abc123"]) == .getUser(userID: "abc123"))
        #expect(Command(arguments: ["get-user"]) == .getUser(userID: "me"))
        #expect(Command(arguments: ["send-message", "hello", "world"]) == .sendMessage(channelID: nil, message: "hello world"))
        #expect(Command(arguments: ["send-message", "--channel", "chan", "hello", "world"]) == .sendMessage(channelID: "chan", message: "hello world"))
        #expect(Command(arguments: []) == .help)
        #expect(Command(arguments: ["totally-unknown-command"]) == .help)
    }
}
