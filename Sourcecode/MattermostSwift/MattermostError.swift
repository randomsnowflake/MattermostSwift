import Foundation

/// Structured error details returned by the Mattermost API.
public struct MattermostAPIErrorBody: Decodable, Equatable, Sendable {
    /// Stable programmatic identifier supplied by Mattermost.
    public let id: String?
    /// Human-readable error message supplied by Mattermost.
    public let message: String?
    /// Additional diagnostic detail supplied by Mattermost.
    public let detailedError: String?
    /// Request identifier that can be correlated with Mattermost server logs.
    public let requestId: String?
    /// HTTP status code repeated in the Mattermost response body.
    public let statusCode: Int?

    public init(
        id: String? = nil,
        message: String? = nil,
        detailedError: String? = nil,
        requestId: String? = nil,
        statusCode: Int? = nil
    ) {
        self.id = id
        self.message = message
        self.detailedError = detailedError
        self.requestId = requestId
        self.statusCode = statusCode
    }
}

/// Errors produced by MattermostSwift.
public enum MattermostError: Error, Equatable, Sendable {
    case missingEnvironmentVariable(String)
    case invalidServerURL(String)
    case insecureServerURL(String)
    case invalidEndpoint(String)
    case invalidHTTPResponse
    case httpStatus(code: Int, message: String?, apiError: MattermostAPIErrorBody?)
    /// The server rejected a request because its rate limit was exceeded.
    ///
    /// `retryAfter` contains the delay in seconds when the response supplied a valid
    /// `Retry-After` value.
    case rateLimited(retryAfter: TimeInterval?)
    case emptyResponse
    case transportFailure(String)
    case fileTooLarge(limit: Int64)
    case incompleteSync(String)
    case liveEventGap
    case missingAuthenticationToken
    case sidebarCategoryNotFound(String)
}

public extension MattermostError {
    /// Whether this error represents an HTTP 401 response.
    var isUnauthorized: Bool {
        if case .httpStatus(401, _, _) = self {
            return true
        }
        return false
    }

    /// Whether this error represents an HTTP 403 response.
    var isForbidden: Bool {
        if case .httpStatus(403, _, _) = self {
            return true
        }
        return false
    }

    /// Whether this error represents an HTTP 404 response.
    var isNotFound: Bool {
        if case .httpStatus(404, _, _) = self {
            return true
        }
        return false
    }
}

extension MattermostError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingEnvironmentVariable(let name):
            "Missing environment variable: \(name)"
        case .invalidServerURL(let url):
            "Invalid Mattermost server URL: \(url)"
        case .insecureServerURL(let url):
            "Refusing to send credentials over an insecure (http) Mattermost URL: \(url). Use https, or pass allowInsecureHTTP: true for a trusted local server."
        case .invalidEndpoint(let endpoint):
            "Invalid Mattermost API endpoint: \(endpoint)"
        case .invalidHTTPResponse:
            "Mattermost returned a non-HTTP response."
        case .httpStatus(let code, let message, _):
            if let message, !message.isEmpty {
                "Mattermost API request failed with HTTP \(code): \(message)"
            } else {
                "Mattermost API request failed with HTTP \(code)."
            }
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Mattermost rate limited the request. Retry after \(retryAfter) seconds."
            } else {
                "Mattermost rate limited the request."
            }
        case .emptyResponse:
            "Mattermost returned an empty response."
        case .transportFailure(let message):
            "Mattermost transport failed: \(message)"
        case .fileTooLarge(let limit):
            "Mattermost file exceeds the configured \(limit)-byte limit."
        case .incompleteSync(let message):
            "Mattermost sync is incomplete: \(message)"
        case .liveEventGap:
            "Mattermost live event delivery overflowed; reconciliation is required."
        case .missingAuthenticationToken:
            "Mattermost login response did not include an authentication token."
        case .sidebarCategoryNotFound(let categoryID):
            "Mattermost sidebar category was not found: \(categoryID)"
        }
    }
}
