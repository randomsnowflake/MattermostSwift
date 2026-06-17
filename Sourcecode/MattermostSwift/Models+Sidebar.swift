import Foundation

// MARK: - Sidebar category models

/// Sidebar categories and server-provided ordering for a user's team sidebar.
public struct MattermostSidebarCategoryList: Decodable, Equatable, Sendable {
    public let categories: [MattermostSidebarCategory]
    public let order: [String]

    public var orderedCategories: [MattermostSidebarCategory] {
        guard !order.isEmpty else {
            return categories
        }

        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let ordered = order.compactMap { categoriesByID[$0] }
        let orderedIDs = Set(order)
        return ordered + categories.filter { !orderedIDs.contains($0.id) }
    }
}

/// Sidebar category metadata for a user's team sidebar.
public struct MattermostSidebarCategory: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let userId: String?
    public let teamId: String?
    public let displayName: String
    public let type: String
    public let sortOrder: Int?
    public let channelIds: [String]
    public let sorting: String?
    public let muted: Bool?
    public let collapsed: Bool?

    public var isCustom: Bool {
        type == "custom"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case teamId
        case displayName
        case type
        case sortOrder
        case channelIds
        case sorting
        case muted
        case collapsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        teamId = try container.decodeIfPresent(String.self, forKey: .teamId)
        displayName = try container.decode(String.self, forKey: .displayName)
        type = try container.decode(String.self, forKey: .type)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        channelIds = try container.decodeIfPresent([String].self, forKey: .channelIds) ?? []
        sorting = try container.decodeIfPresent(String.self, forKey: .sorting)
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted)
        collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed)
    }
}

/// Server-authoritative result after changing sidebar category channel membership.
public struct MattermostSidebarCategoryMoveResult: Equatable, Sendable {
    public let updatedCategories: [MattermostSidebarCategory]
    public let categories: [MattermostSidebarCategory]

    public var movedCategory: MattermostSidebarCategory? {
        updatedCategories.last
    }
}
