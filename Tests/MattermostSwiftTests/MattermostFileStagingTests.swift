import Foundation
import Testing
@testable import MattermostSwift

@Test
func failedDownloadInstallKeepsOriginalByteIdentical() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appending(path: "file.bin")
    let original = Data("original".utf8)
    try original.write(to: destination)

    // A vanished temporary download makes the install fail after validation.
    #expect(throws: (any Error).self) {
        try MattermostHTTPClient.installDownload(from: directory.appending(path: "missing"), to: destination)
    }
    #expect(try Data(contentsOf: destination) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["file.bin"])

    let replacement = directory.appending(path: "incoming")
    try Data("replacement".utf8).write(to: replacement)
    try MattermostHTTPClient.installDownload(from: replacement, to: destination)
    #expect(try Data(contentsOf: destination) == Data("replacement".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["file.bin"])
}

@Test
func failedMultipartBodyConstructionLeavesNoTemporaryFile() throws {
    let client = try MattermostClient(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        token: "token"
    )
    func bodyFiles() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("MattermostSwift-") && $0.hasSuffix(".multipart") })
    }
    let before = try bodyFiles()

    #expect(throws: (any Error).self) {
        _ = try client.httpClient.makeMultipartBodyFile(
            parts: [],
            filePart: MattermostMultipartFilePart(
                name: "files",
                filename: "missing.txt",
                contentType: "text/plain",
                fileURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).missing")
            ),
            boundary: "boundary"
        )
    }
    #expect(try bodyFiles() == before)
}
