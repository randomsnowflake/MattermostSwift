import Foundation

// MARK: - User preference models

/// User preference entry used by Mattermost for client-side settings.
public struct MattermostPreference: Codable, Equatable, Sendable, Identifiable {
    public let userID: String
    public let category: String
    public let name: String
    public let value: String

    public var id: String {
        Self.cacheID(userID: userID, category: category, name: name)
    }

    public init(userID: String, category: String, name: String, value: String) {
        self.userID = userID
        self.category = category
        self.name = name
        self.value = value
    }

    @available(*, deprecated, message: "Use init(userID:category:name:value:)")
    public init(userId: String, category: String, name: String, value: String) {
        self.init(userID: userId, category: category, name: name, value: value)
    }

    @available(*, deprecated, renamed: "userID")
    public var userId: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case category
        case name
        case value
    }

    public static func cacheID(userID: String, category: String, name: String) -> String {
        "\(userID):\(category):\(name)"
    }
}
