import Foundation

// MARK: - User preference models

/// User preference entry used by Mattermost for client-side settings.
public struct MattermostPreference: Codable, Equatable, Sendable, Identifiable {
    public let userId: String
    public let category: String
    public let name: String
    public let value: String

    public var id: String {
        Self.cacheID(userID: userId, category: category, name: name)
    }

    public init(userId: String, category: String, name: String, value: String) {
        self.userId = userId
        self.category = category
        self.name = name
        self.value = value
    }

    public static func cacheID(userID: String, category: String, name: String) -> String {
        "\(userID):\(category):\(name)"
    }
}
