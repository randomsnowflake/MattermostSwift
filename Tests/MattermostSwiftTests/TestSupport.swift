import Foundation
import Testing
@testable import MattermostSwift

enum MattermostTestSupport {
    typealias URLHandler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    static func urlSession(handler: @escaping URLHandler) async -> URLSession {
        let handlerID = UUID().uuidString
        await MattermostMockURLProtocolHandlers.shared.setHandler(handler, id: handlerID)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MattermostMockURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            MattermostMockURLProtocol.handlerIDHeader: handlerID,
        ]
        return URLSession(configuration: configuration)
    }

    static func response(
        statusCode: Int,
        body: Data,
        contentType: String = "application/json",
        request: URLRequest
    ) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        ))
        return (response, body)
    }

    static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw MattermostTestError.unreadableBodyStream
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

enum MattermostTestError: Error {
    case unreadableBodyStream
}

final class MattermostRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock {
            storage.append(value)
        }
    }
}

final class MattermostMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let handlerIDHeader = "X-MattermostSwift-Test-Handler-ID"

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: handlerIDHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            do {
                let (response, data) = try await MattermostMockURLProtocolHandlers.shared.response(for: request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

actor MattermostMockURLProtocolHandlers {
    static let shared = MattermostMockURLProtocolHandlers()

    private var handlers: [String: MattermostTestSupport.URLHandler] = [:]

    func setHandler(_ handler: @escaping MattermostTestSupport.URLHandler, id: String) {
        handlers[id] = handler
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard let handlerID = request.value(forHTTPHeaderField: MattermostMockURLProtocol.handlerIDHeader),
              let handler = handlers[handlerID] else {
            throw MattermostError.invalidHTTPResponse
        }
        return try handler(request)
    }
}
