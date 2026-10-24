import Foundation
@_spi(Testing) import MattermostSwift

// Sidebar category scenarios.
extension MattermostSwiftCLI {
    static func runSidebarCategoryTest(client: MattermostClient) async throws {
        let teamID = try await loadTeamID(client: client)
        let suffix = String(Int(Date.now.timeIntervalSince1970))
        let originalOrder = try await client.sidebarCategoryOrder(teamID: teamID)
        var category: MattermostSidebarCategory?

        do {
            let createdCategory = try await client.createSidebarCategory(
                teamID: teamID,
                displayName: "MattermostSwift Test \(suffix)"
            )
            category = createdCategory
            let updated = try await client.updateSidebarCategory(
                teamID: teamID,
                categoryID: createdCategory.id,
                displayName: "MattermostSwift Test Renamed \(suffix)",
                channelIDs: createdCategory.channelIDs
            )
            let orderWithCategory = try await client.sidebarCategoryOrder(teamID: teamID)
            let deleted = try await client.deleteSidebarCategory(teamID: teamID, categoryID: createdCategory.id)
            let restoredOrder = try await client.updateSidebarCategoryOrder(
                teamID: teamID,
                order: originalOrder.filter { $0 != createdCategory.id }
            )

            print("category: \(createdCategory.id)")
            print("created-name: \(createdCategory.displayName)")
            print("renamed-name: \(updated.displayName)")
            print("order-contained-category: \(orderWithCategory.contains(createdCategory.id))")
            print("delete-status: \(deleted.status)")
            print("restored-order-count: \(restoredOrder.count)")
        } catch {
            let categoryID = category?.id
            if let categoryID {
                _ = try? await client.deleteSidebarCategory(teamID: teamID, categoryID: categoryID)
            }
            _ = try? await client.updateSidebarCategoryOrder(
                teamID: teamID,
                order: categoryID.map { id in originalOrder.filter { $0 != id } } ?? originalOrder
            )
            throw error
        }
    }

    static func runSidebarMoveTest(client: MattermostClient) async throws {
        let teamID = try await loadTeamID(client: client)
        let suffix = String(Int(Date.now.timeIntervalSince1970))
        let originalOrder = try await client.sidebarCategoryOrder(teamID: teamID)
        var channel: MattermostChannel?
        var category: MattermostSidebarCategory?

        do {
            let createdChannel = try await client.createChannel(
                teamID: teamID,
                name: "mmswift-test-move-\(suffix)",
                displayName: "MattermostSwift Move Test \(suffix)",
                purpose: "Created by MattermostSwiftCLI sidebar move verification."
            )
            channel = createdChannel
            let createdCategory = try await client.createSidebarCategory(
                teamID: teamID,
                displayName: "MattermostSwift Move Test \(suffix)"
            )
            category = createdCategory

            let moveResult = try await client.moveChannelToSidebarCategory(
                teamID: teamID,
                channelID: createdChannel.id,
                categoryID: createdCategory.id,
                position: 0
            )
            let movedCategory = moveResult.categories.first { $0.id == createdCategory.id }
            let deletedCategory = try await client.deleteSidebarCategory(teamID: teamID, categoryID: createdCategory.id)
            let deleteChannelStatus = try await client.deleteChannel(id: createdChannel.id)
            let restoredOrder = try await client.updateSidebarCategoryOrder(
                teamID: teamID,
                order: originalOrder.filter { $0 != createdCategory.id }
            )

            print("channel: \(createdChannel.id)")
            print("category: \(createdCategory.id)")
            print("updated-categories: \(moveResult.updatedCategories.count)")
            print("category-contained-channel: \(movedCategory?.channelIDs.contains(createdChannel.id) == true)")
            print("category-first-channel: \(movedCategory?.channelIDs.first == createdChannel.id)")
            print("delete-category-status: \(deletedCategory.status)")
            print("delete-channel-status: \(deleteChannelStatus.status)")
            print("restored-order-count: \(restoredOrder.count)")
        } catch {
            let categoryID = category?.id
            if let categoryID {
                _ = try? await client.deleteSidebarCategory(teamID: teamID, categoryID: categoryID)
            }
            if let channelID = channel?.id {
                _ = try? await client.deleteChannel(id: channelID)
            }
            _ = try? await client.updateSidebarCategoryOrder(
                teamID: teamID,
                order: categoryID.map { id in originalOrder.filter { $0 != id } } ?? originalOrder
            )
            throw error
        }
    }
}
