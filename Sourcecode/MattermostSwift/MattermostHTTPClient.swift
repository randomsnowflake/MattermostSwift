import Foundation

struct MattermostHTTPClient: Sendable {
    private let configuration: MattermostConfiguration
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(configuration: MattermostConfiguration, urlSession: URLSession) {
        self.configuration = configuration
        self.urlSession = urlSession

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func get<Response: Decodable & Sendable>(
        _ endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(endpoint: endpoint, method: "GET", queryItems: queryItems)
        let (data, response) = try await loadData(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MattermostError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MattermostError.httpStatus(
                code: httpResponse.statusCode,
                message: decodeMattermostAPIError(from: data)?.message
            )
        }

        guard !data.isEmpty else {
            throw MattermostError.emptyResponse
        }

        return try decoder.decode(Response.self, from: data)
    }

    func post<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ endpoint: String,
        body: Request,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(endpoint, method: "POST", body: body, queryItems: queryItems)
    }

    func put<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ endpoint: String,
        body: Request,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(endpoint, method: "PUT", body: body, queryItems: queryItems)
    }

    func delete<Response: Decodable & Sendable>(
        _ endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(endpoint: endpoint, method: "DELETE", queryItems: queryItems)
        return try await perform(request: request)
    }

    func data(
        _ endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        let request = try makeRequest(endpoint: endpoint, method: "GET", queryItems: queryItems)
        let (data, response) = try await loadData(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MattermostError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MattermostError.httpStatus(
                code: httpResponse.statusCode,
                message: decodeMattermostAPIError(from: data)?.message
            )
        }

        return data
    }

    func multipart<Response: Decodable & Sendable>(
        _ endpoint: String,
        parts: [MattermostMultipartPart],
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let boundary = "MattermostSwift-\(UUID().uuidString)"
        var request = try makeRequest(endpoint: endpoint, method: "POST", queryItems: queryItems)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(parts: parts, boundary: boundary)
        return try await perform(request: request)
    }

    private func send<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ endpoint: String,
        method: String,
        body: Request,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        let request = try makeJSONRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            queryItems: queryItems
        )
        return try await perform(request: request)
    }

    private func perform<Response: Decodable & Sendable>(request: URLRequest) async throws -> Response {
        try await performWithResponse(request: request).value
    }

    func performWithResponse<Response: Decodable & Sendable>(
        request: URLRequest
    ) async throws -> MattermostHTTPResponse<Response> {
        let (data, response) = try await loadData(for: request)
        return try decodeResponse(data: data, response: response)
    }

#if os(macOS)
    func performWithCurlResponse<Response: Decodable & Sendable>(
        request: URLRequest
    ) throws -> MattermostHTTPResponse<Response> {
        let (data, response) = try loadDataWithCurl(for: request)
        return try decodeResponse(data: data, response: response)
    }

    func performLoginWithCurlResponse<Response: Decodable & Sendable>(
        request: URLRequest
    ) throws -> MattermostHTTPResponse<Response> {
        let (data, response) = try loadLoginDataWithCurl(for: request)
        return try decodeResponse(data: data, response: response)
    }
#endif

    private func decodeResponse<Response: Decodable & Sendable>(
        data: Data,
        response: URLResponse
    ) throws -> MattermostHTTPResponse<Response> {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MattermostError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MattermostError.httpStatus(
                code: httpResponse.statusCode,
                message: decodeMattermostAPIError(from: data)?.message
            )
        }

        guard !data.isEmpty else {
            throw MattermostError.emptyResponse
        }

        return MattermostHTTPResponse(
            value: try decoder.decode(Response.self, from: data),
            httpResponse: httpResponse
        )
    }

    private func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await loadDataWithURLSession(for: request)
        } catch {
#if os(macOS)
            if (error as NSError).domain == NSURLErrorDomain,
               (error as NSError).code == NSURLErrorNetworkConnectionLost {
                return try loadDataWithCurl(for: request)
            }
#endif
            throw error
        }
    }

    private func loadDataWithURLSession(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let response else {
                    continuation.resume(throwing: MattermostError.invalidHTTPResponse)
                    return
                }

                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

#if os(macOS)
    private func loadDataWithCurl(for request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw MattermostError.invalidEndpoint("")
        }

        let marker = "\n__MATTERMOST_SWIFT_HTTP_STATUS__:"
        let temporaryHeaderURL = FileManager.default.temporaryDirectory
            .appending(path: "mattermostswift-\(UUID().uuidString).headers")
        let temporaryBodyURL = try writeTemporaryBodyIfNeeded(for: request)
        defer {
            try? FileManager.default.removeItem(at: temporaryHeaderURL)
            if let temporaryBodyURL {
                try? FileManager.default.removeItem(at: temporaryBodyURL)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var arguments = [
            "--silent",
            "--show-error",
            "--request",
            request.httpMethod ?? "GET",
            "--output",
            "-",
            "--dump-header",
            temporaryHeaderURL.path,
            "--write-out",
            "\(marker)%{http_code}",
            "--config",
            "-",
            url.absoluteString,
        ]
        if let temporaryBodyURL {
            arguments.insert(contentsOf: ["--data-binary", "@\(temporaryBodyURL.path)"], at: arguments.count - 1)
        }
        process.arguments = arguments

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let curlConfiguration = curlConfiguration(for: request)
        try process.run()
        standardInput.fileHandleForWriting.write(Data(curlConfiguration.utf8))
        try standardInput.fileHandleForWriting.close()
        process.waitUntilExit()

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = standardError.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MattermostError.transportFailure(message ?? "curl exited with status \(process.terminationStatus)")
        }

        guard let markerRange = output.lastRange(of: Data(marker.utf8)),
              let statusCode = Int(String(decoding: output[markerRange.upperBound...], as: UTF8.self)) else {
            throw MattermostError.transportFailure("curl response did not include an HTTP status")
        }

        let body = output[..<markerRange.lowerBound]
        let headerFields = try parseCurlHeaders(at: temporaryHeaderURL)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headerFields
        ) else {
            throw MattermostError.invalidHTTPResponse
        }

        return (Data(body), response)
    }

    private func loadLoginDataWithCurl(for request: URLRequest) throws -> (Data, URLResponse) {
        guard request.value(forHTTPHeaderField: "Authorization") == nil else {
            throw MattermostError.transportFailure("login curl fallback refuses authenticated requests")
        }
        guard let url = request.url else {
            throw MattermostError.invalidEndpoint("")
        }

        let marker = "\n__MATTERMOST_SWIFT_HTTP_STATUS__:"
        let temporaryHeaderURL = FileManager.default.temporaryDirectory
            .appending(path: "mattermostswift-\(UUID().uuidString).headers")
        defer {
            try? FileManager.default.removeItem(at: temporaryHeaderURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var arguments = [
            "--silent",
            "--show-error",
            "--request",
            request.httpMethod ?? "POST",
            "--output",
            "-",
            "--dump-header",
            temporaryHeaderURL.path,
            "--write-out",
            "\(marker)%{http_code}",
        ]
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            arguments.append(contentsOf: ["--header", "\(name): \(value)"])
        }
        if request.httpBody?.isEmpty == false {
            arguments.append(contentsOf: ["--data-binary", "@-"])
        }
        arguments.append(url.absoluteString)
        process.arguments = arguments

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        if let body = request.httpBody, !body.isEmpty {
            standardInput.fileHandleForWriting.write(body)
        }
        try standardInput.fileHandleForWriting.close()
        process.waitUntilExit()

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = standardError.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MattermostError.transportFailure(message ?? "curl exited with status \(process.terminationStatus)")
        }

        guard let markerRange = output.lastRange(of: Data(marker.utf8)),
              let statusCode = Int(String(decoding: output[markerRange.upperBound...], as: UTF8.self)) else {
            throw MattermostError.transportFailure("curl response did not include an HTTP status")
        }

        let body = output[..<markerRange.lowerBound]
        let headerFields = try parseCurlHeaders(at: temporaryHeaderURL)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headerFields
        ) else {
            throw MattermostError.invalidHTTPResponse
        }

        return (Data(body), response)
    }

    private func curlConfiguration(for request: URLRequest) -> String {
        var lines: [String] = []
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            lines.append("header = \"\(name): \(value.replacing("\"", with: "\\\""))\"")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func writeTemporaryBodyIfNeeded(for request: URLRequest) throws -> URL? {
        guard let body = request.httpBody, !body.isEmpty else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "mattermostswift-\(UUID().uuidString).body")
        try body.write(to: url, options: .atomic)
        return url
    }

    private func parseCurlHeaders(at url: URL) throws -> [String: String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard let finalHeaderBlock = normalizedText
            .components(separatedBy: "\n\n")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .last(where: { $0.hasPrefix("HTTP/") }) else {
            return [:]
        }

        var headers: [String: String] = [:]
        for line in finalHeaderBlock.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = headers[name] {
                headers[name] = "\(existing), \(value)"
            } else {
                headers[name] = value
            }
        }
        return headers
    }
#endif

    func makeRequest(
        endpoint: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: configuration.apiBaseURL.appending(path: endpoint.trimmingLeadingSlash),
            resolvingAgainstBaseURL: false
        ) else {
            throw MattermostError.invalidEndpoint(endpoint)
        }

        components.percentEncodedPath = components.percentEncodedPath.replacing("//", with: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw MattermostError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        MattermostUserAgent.applyBrowserUserAgent(to: &request)

        switch configuration.authentication {
        case .none:
            break
        case .bearerToken(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    func makeJSONRequest<Request: Encodable & Sendable>(
        endpoint: String,
        method: String,
        body: Request,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        var request = try makeRequest(endpoint: endpoint, method: method, queryItems: queryItems)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func makeMultipartBody(parts: [MattermostMultipartPart], boundary: String) -> Data {
        var body = Data()

        for part in parts {
            body.appendString("--\(boundary)\r\n")
            body.appendString(part.contentDisposition)
            body.appendString("\r\n")

            if let contentType = part.contentType {
                body.appendString("Content-Type: \(contentType)\r\n")
            }

            body.appendString("\r\n")
            body.append(part.data)
            body.appendString("\r\n")
        }

        body.appendString("--\(boundary)--\r\n")
        return body
    }

    private func decodeMattermostAPIError(from data: Data) -> MattermostAPIError? {
        guard !data.isEmpty else {
            return nil
        }
        return try? decoder.decode(MattermostAPIError.self, from: data)
    }
}

struct MattermostHTTPResponse<Value: Sendable>: Sendable {
    let value: Value
    let httpResponse: HTTPURLResponse
}

struct MattermostMultipartPart: Sendable {
    let name: String
    let filename: String?
    let contentType: String?
    let data: Data

    var contentDisposition: String {
        var value = "Content-Disposition: form-data; name=\"\(name)\""
        if let filename {
            value += "; filename=\"\(filename)\""
        }
        return value
    }
}

private struct MattermostAPIError: Decodable, Sendable {
    let message: String?
}

private extension String {
    var trimmingLeadingSlash: String {
        var result = self
        while result.hasPrefix("/") {
            result.removeFirst()
        }
        return result
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
