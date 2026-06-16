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

    // Native async transport. `URLSession.data(for:)` propagates Task cancellation
    // (it cancels the underlying data task), and a transient network blip is retried once.
    private func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error as URLError where Self.isTransient(error) {
            return try await urlSession.data(for: request)
        }
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed:
            true
        default:
            false
        }
    }


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
