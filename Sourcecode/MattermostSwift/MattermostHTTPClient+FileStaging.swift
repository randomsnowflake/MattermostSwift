import Foundation

// File staging, apart from JSON requests and retries: download installation and
// streamed multipart bodies, each owning its temporary file until it hands it over.
extension MattermostHTTPClient {
    /// Stages the download beside its destination, then swaps it in. An existing file is kept
    /// until the replacement succeeds, so a failed install never loses the previous copy.
    static func installDownload(from temporaryURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stagedURL = directory.appendingPathComponent(".\(UUID().uuidString).download")
        try fileManager.moveItem(at: temporaryURL, to: stagedURL)
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagedURL)
            } else {
                try fileManager.moveItem(at: stagedURL, to: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }
    }

    /// Owns the temporary body until it returns; any construction failure removes it.
    func makeMultipartBodyFile(
        parts: [MattermostMultipartPart],
        filePart: MattermostMultipartFilePart,
        boundary: String
    ) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MattermostSwift-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        var transferred = false
        defer { if !transferred { try? FileManager.default.removeItem(at: bodyURL) } }
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }

        func write(_ value: String) throws {
            try output.write(contentsOf: Data(value.utf8))
        }
        func writeHeaders(for part: some MattermostMultipartPartProtocol) throws {
            try write("--\(boundary)\r\n")
            try write(part.contentDisposition)
            try write("\r\n")
            if let contentType = part.contentType {
                try write("Content-Type: \(contentType)\r\n")
            }
            try write("\r\n")
        }

        for part in parts {
            try writeHeaders(for: part)
            try output.write(contentsOf: part.data)
            try write("\r\n")
        }
        try writeHeaders(for: filePart)
        let input = try FileHandle(forReadingFrom: filePart.fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try write("\r\n--\(boundary)--\r\n")
        transferred = true
        return bodyURL
    }
}
