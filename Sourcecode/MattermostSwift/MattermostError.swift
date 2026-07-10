import Foundation

/// Errors produced by MattermostSwift.
public enum MattermostError: Error, Equatable, Sendable {
    case missingEnvironmentVariable(String)
    case invalidServerURL(String)
    case insecureServerURL(String)
    case invalidEndpoint(String)
    case invalidHTTPResponse
    case httpStatus(code: Int, message: String?)
    case emptyResponse
    case transportFailure(String)
    case fileTooLarge(limit: Int64)
    case incompleteSync(String)
    case liveEventGap
    case missingAuthenticationToken
    case sidebarCategoryNotFound(String)
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
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                "Mattermost API request failed with HTTP \(code): \(message)"
            } else {
                "Mattermost API request failed with HTTP \(code)."
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
