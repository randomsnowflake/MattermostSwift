import Foundation

struct MattermostHTTPClient: Sendable {
    private let configuration: MattermostConfiguration
    private let urlSession: URLSession

    init(configuration: MattermostConfiguration, urlSession: URLSession) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func get<Response: Decodable & Sendable>(
        _ endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(endpoint: endpoint, method: "GET", queryItems: queryItems)
        let (data, response) = try await loadData(for: request)

        _ = try validate(data, response)

        guard !data.isEmpty else {
            throw MattermostError.emptyResponse
        }

        return try mattermostSnakeCaseDecoder.decode(Response.self, from: data)
    }

    func post<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ endpoint: String,
        body: Request,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(endpoint, method: "POST", body: body, queryItems: queryItems)
    }

    func post<Response: Decodable & Sendable>(
        _ endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(endpoint: endpoint, method: "POST", queryItems: queryItems)
        return try await perform(request: request)
    }

    func put<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ endpoint: String,
        body: Request,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(endpoint, method: "PUT", body: body, queryItems: queryItems)
    }

    func put<Response: Decodable & Sendable>(
        _ endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(endpoint: endpoint, method: "PUT", queryItems: queryItems)
        return try await perform(request: request)
    }

    func delete<Response: Decodable & Sendable>(
        _ endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(endpoint: endpoint, method: "DELETE", queryItems: queryItems)
        return try await perform(request: request)
    }

    func delete<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ endpoint: String,
        body: Request,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(endpoint, method: "DELETE", body: body, queryItems: queryItems)
    }

    func data(
        _ endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        let request = try makeRequest(endpoint: endpoint, method: "GET", queryItems: queryItems)
        let (data, response) = try await loadData(for: request)

        _ = try validate(data, response)

        return data
    }

    func multipart<Response: Decodable & Sendable>(
        _ endpoint: String,
        method: String = "POST",
        parts: [MattermostMultipartPart],
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let boundary = "MattermostSwift-\(UUID().uuidString)"
        var request = try makeRequest(endpoint: endpoint, method: method, queryItems: queryItems)
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

    private func decodeResponse<Response: Decodable & Sendable>(
        data: Data,
        response: URLResponse
    ) throws -> MattermostHTTPResponse<Response> {
        let httpResponse = try validate(data, response)

        guard !data.isEmpty else {
            throw MattermostError.emptyResponse
        }

        return MattermostHTTPResponse(
            value: try mattermostSnakeCaseDecoder.decode(Response.self, from: data),
            httpResponse: httpResponse
        )
    }

    private func validate(_ data: Data, _ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MattermostError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MattermostError.httpStatus(
                code: httpResponse.statusCode,
                message: decodeMattermostAPIError(from: data)?.message
            )
        }

        return httpResponse
    }

    // Native async transport. `URLSession.data(for:)` propagates Task cancellation
    // (it cancels the underlying data task). Only safe read requests retry a transient
    // keep-alive socket reset: a mutation may have committed before its response was
    // lost, so replaying POST/PUT/PATCH/DELETE is not generally safe.
    private func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                return try await urlSession.data(for: request)
            } catch {
                attempt += 1
                if Self.isCancellation(error) {
                    throw error
                }
                guard attempt <= Self.maxTransientRetries,
                      Self.isTransient(error),
                      Self.allowsAutomaticRetry(for: request) else {
                    throw MattermostError.transportFailure(error.localizedDescription)
                }
                try await Task.sleep(for: .milliseconds(200 * attempt))
            }
        }
    }

    private static let maxTransientRetries = 2

    private static func allowsAutomaticRetry(for request: URLRequest) -> Bool {
        switch request.httpMethod?.uppercased() {
        case nil, "GET", "HEAD", "OPTIONS":
            true
        default:
            false
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }

    private static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .timedOut, .cannotConnectToHost,
                 .dnsLookupFailed, .notConnectedToInternet:
                return true
            default:
                break
            }
        }
        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 // ENOTCONN
    }


    func makeRequest(
        endpoint: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: configuration.apiBaseURL.appending(path: endpoint.mattermostTrimmingLeadingSlashes),
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
        request.httpBody = try mattermostSnakeCaseEncoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func makeMultipartBody(parts: [MattermostMultipartPart], boundary: String) -> Data {
        var body = Data()
        let estimatedCapacity = parts.reduce(0) { total, part in
            total + part.contentDisposition.utf8.count + (part.contentType?.utf8.count ?? 0) + part.data.count + 64
        } + boundary.utf8.count + 8
        body.reserveCapacity(estimatedCapacity)

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
        return try? mattermostSnakeCaseDecoder.decode(MattermostAPIError.self, from: data)
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
        var value = "Content-Disposition: form-data; name=\"\(name.multipartQuotedStringEscaped)\""
        if let filename {
            value += "; filename=\"\(filename.multipartQuotedStringEscaped)\""
        }
        return value
    }
}

private struct MattermostAPIError: Decodable, Sendable {
    let message: String?
}

private extension String {
    var multipartQuotedStringEscaped: String {
        var escaped = ""
        escaped.reserveCapacity(count)

        for scalar in unicodeScalars {
            switch scalar {
            case "\\", "\"":
                escaped.append("\\")
                escaped.unicodeScalars.append(scalar)
            case "\r", "\n":
                escaped.append(" ")
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }

        return escaped
    }

}

private extension Data {
    mutating func appendString(_ string: String) {
        append(contentsOf: string.utf8)
    }
}
