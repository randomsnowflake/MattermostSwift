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
public struct MattermostSidebarCategory: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let userID: String?
    public let teamID: String?
    public let displayName: String
    public let type: MattermostSidebarCategoryType
    public let sortOrder: Int?
    public let channelIDs: [String]
    public let sorting: MattermostSidebarCategorySorting?
    public let muted: Bool?
    public let collapsed: Bool?

    public var isCustom: Bool {
        type == .custom
    }

    init(
        id: String,
        userID: String?,
        teamID: String?,
        displayName: String,
        type: MattermostSidebarCategoryType,
        sortOrder: Int?,
        channelIDs: [String],
        sorting: MattermostSidebarCategorySorting?,
        muted: Bool?,
        collapsed: Bool?
    ) {
        self.id = id
        self.userID = userID
        self.teamID = teamID
        self.displayName = displayName
        self.type = type
        self.sortOrder = sortOrder
        self.channelIDs = channelIDs
        self.sorting = sorting
        self.muted = muted
        self.collapsed = collapsed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "userId"
        case teamID = "teamId"
        case displayName
        case type
        case sortOrder
        case channelIDs = "channelIds"
        case sorting
        case muted
        case collapsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        teamID = try container.decodeIfPresent(String.self, forKey: .teamID)
        displayName = try container.decode(String.self, forKey: .displayName)
        type = try container.decode(MattermostSidebarCategoryType.self, forKey: .type)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        channelIDs = try container.decodeIfPresent([String].self, forKey: .channelIDs) ?? []
        sorting = try container.decodeIfPresent(MattermostSidebarCategorySorting.self, forKey: .sorting)
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted)
        collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed)
    }

    @available(*, deprecated, renamed: "userID")
    public var userId: String? { userID }
    @available(*, deprecated, renamed: "teamID")
    public var teamId: String? { teamID }
    @available(*, deprecated, renamed: "channelIDs")
    public var channelIds: [String] { channelIDs }
}

/// Server-authoritative result after changing sidebar category channel membership.
public struct MattermostSidebarCategoryMoveResult: Equatable, Sendable {
    public let updatedCategories: [MattermostSidebarCategory]
    public let categories: [MattermostSidebarCategory]

    public var movedCategory: MattermostSidebarCategory? {
        updatedCategories.last
    }
}
