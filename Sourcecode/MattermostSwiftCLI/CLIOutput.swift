import Foundation
import MattermostSwift

enum CLIOutputMode {
    @TaskLocal static var json = false
}

private struct CLITextRecord: Encodable {
    let text: String
}

private struct CLIImageResult: Encodable {
    let kind: String
    let userID: String
    let byteCount: Int
    let signature: String
    let dataBase64: String
}

private struct CLIKnownUsersResult: Encodable {
    let userIDs: [String]
    let profiles: [MattermostUser]?
}

private struct CLICheckResult: Encodable {
    let user: MattermostUser
    let channels: [MattermostChannel]
}

extension MattermostSwiftCLI {
    static func encodedJSON<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func writeJSON<Value: Encodable>(_ value: Value) {
        do {
            var data = try encodedJSON(value)
            data.append(0x0A)
            FileHandle.standardOutput.write(data)
        } catch {
            writeStandardError("error: could not encode CLI JSON output: \(error.localizedDescription)\n")
            Foundation.exit(1)
        }
    }

    @discardableResult
    static func writeJSONIfRequested<Value: Encodable>(_ value: Value) -> Bool {
        guard CLIOutputMode.json else { return false }
        writeJSON(value)
        return true
    }

    /// Human-oriented scenario output falls back to lossless NDJSON text records.
    ///
    /// Model-backed commands use their concrete `Encodable` values instead.
    static func print(_ line: String) {
        if CLIOutputMode.json {
            writeJSON(CLITextRecord(text: line))
        } else {
            Swift.print(line)
        }
    }

    static func printServerInfo(_ serverInfo: MattermostServerInfo) {
        guard !writeJSONIfRequested(serverInfo) else { return }
        print("status: \(serverInfo.ping.status)")

        if let databaseStatus = serverInfo.ping.databaseStatus, !databaseStatus.isEmpty {
            print("database: \(databaseStatus)")
        }

        if let filestoreStatus = serverInfo.ping.filestoreStatus, !filestoreStatus.isEmpty {
            print("filestore: \(filestoreStatus)")
        }

        if let searchBackend = serverInfo.ping.activeSearchBackend, !searchBackend.isEmpty {
            print("search: \(searchBackend)")
        }

        if let buildNumber = serverInfo.clientConfig.buildNumber, !buildNumber.isEmpty {
            print("build: \(buildNumber)")
        }

        if let buildHash = serverInfo.clientConfig.buildHash, !buildHash.isEmpty {
            print("build-hash: \(buildHash)")
        }

        if let collapsedThreads = serverInfo.clientConfig.collapsedThreads, !collapsedThreads.isEmpty {
            print("collapsed-threads: \(collapsedThreads)")
        }
    }

    static func printUser(_ user: MattermostUser) {
        guard !writeJSONIfRequested(user) else { return }
        print("id: \(user.id)")
        print("username: \(user.username)")

        if let email = user.email, !email.isEmpty {
            print("email: \(email)")
        }

        let displayName = [user.firstName, user.lastName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !displayName.isEmpty {
            print("name: \(displayName)")
        }

        if let nickname = user.nickname, !nickname.isEmpty {
            print("nickname: \(nickname)")
        }
    }

    static func printUsers(_ users: [MattermostUser]) {
        let sortedUsers = users.sorted(by: userSort)
        guard !writeJSONIfRequested(sortedUsers) else { return }
        for user in sortedUsers {
            print("\(user.id)\t\(user.username)")
        }
    }

    static func printImageDownload(label: String, userID: String, data: Data) {
        let result = CLIImageResult(
            kind: label,
            userID: userID,
            byteCount: data.count,
            signature: imageSignature(for: data),
            dataBase64: data.base64EncodedString()
        )
        guard !writeJSONIfRequested(result) else { return }
        print("\(label): \(userID)")
        print("bytes: \(data.count)")
        print("signature: \(imageSignature(for: data))")
    }

    static func imageSignature(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpeg"
        }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "gif"
        }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            return "webp-or-riff"
        }
        return "unknown"
    }

    static func printUserAutocomplete(_ autocomplete: MattermostUserAutocomplete) {
        guard !writeJSONIfRequested(autocomplete) else { return }
        print("users: \(autocomplete.users.count)")
        print("in-channel: \(autocomplete.inChannel.count)")
        print("out-of-channel: \(autocomplete.outOfChannel.count)")
        printUsers(autocomplete.allUsers)
    }

    static func userSort(_ lhs: MattermostUser, _ rhs: MattermostUser) -> Bool {
        lhs.username.localizedStandardCompare(rhs.username) == .orderedAscending
    }

    static func printStatus(_ status: MattermostUserStatus) {
        guard !writeJSONIfRequested(status) else { return }
        print("\(status.userID)\t\(status.status.rawValue)")
    }

    static func printStatusOK(_ status: MattermostStatusOK) {
        guard !writeJSONIfRequested(status) else { return }
        print("status: \(status.status)")
    }

    static func printKnownUsers(userIDs: [String], profiles: [MattermostUser]?) {
        let sortedIDs = userIDs.sorted()
        let sortedProfiles = profiles?.sorted(by: userSort)
        guard !writeJSONIfRequested(
            CLIKnownUsersResult(userIDs: sortedIDs, profiles: sortedProfiles)
        ) else { return }

        print("known-users: \(sortedIDs.count)")
        if let sortedProfiles {
            printUsers(sortedProfiles)
        } else {
            for userID in sortedIDs {
                print(userID)
            }
        }
    }

    static func printCheck(user: MattermostUser, channels: [MattermostChannel]) {
        guard !writeJSONIfRequested(CLICheckResult(user: user, channels: channels)) else { return }
        print("Authenticated as \(user.username) (\(user.id))")
        print("Loaded \(channels.count) channel\(channels.count == 1 ? "" : "s")")
    }

    static func printTeam(_ team: MattermostTeam) {
        guard !writeJSONIfRequested(team) else { return }
        print("id: \(team.id)")
        print("name: \(team.name)")
        print("display-name: \(team.displayName)")

        if let type = team.type, !type.isEmpty {
            print("type: \(type)")
        }

        if let description = team.description, !description.isEmpty {
            print("description: \(description)")
        }
    }

    static func printTeams(_ teams: [MattermostTeam]) {
        let sortedTeams = teams.sorted(by: teamSort)
        guard !writeJSONIfRequested(sortedTeams) else { return }
        for team in sortedTeams {
            print("\(team.id)\t\(team.name)\t\(team.displayName)")
        }
    }

    static func printTeamMembers(_ members: [MattermostTeamMember]) {
        let sortedMembers = members.sorted(by: teamMemberSort)
        guard !writeJSONIfRequested(sortedMembers) else { return }
        for member in sortedMembers {
            print("\(member.teamID)\t\(member.userID)\t\(member.roles ?? "")")
        }
    }

    static func teamSort(_ lhs: MattermostTeam, _ rhs: MattermostTeam) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    static func teamMemberSort(_ lhs: MattermostTeamMember, _ rhs: MattermostTeamMember) -> Bool {
        if lhs.teamID == rhs.teamID {
            return lhs.userID.localizedStandardCompare(rhs.userID) == .orderedAscending
        }
        return lhs.teamID.localizedStandardCompare(rhs.teamID) == .orderedAscending
    }

    static func printCategories(_ categories: [MattermostSidebarCategory]) {
        guard !writeJSONIfRequested(categories) else { return }
        for category in categories {
            print("\(category.id)\t\(category.type.rawValue)\t\(category.displayName)\t\(category.channelIDs.count) channels")
        }
    }

    static func printPreferences(_ preferences: [MattermostPreference]) {
        let sortedPreferences = preferences.sorted(by: preferenceSort)
        guard !writeJSONIfRequested(sortedPreferences) else { return }
        for preference in sortedPreferences {
            print("\(preference.category)\t\(preference.name)\tvalue-bytes:\(preference.value.utf8.count)")
        }
    }

    static func preferenceSort(_ lhs: MattermostPreference, _ rhs: MattermostPreference) -> Bool {
        if lhs.category == rhs.category {
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return lhs.category.localizedStandardCompare(rhs.category) == .orderedAscending
    }

    static func printChannelMember(_ member: MattermostChannelMember) {
        guard !writeJSONIfRequested(member) else { return }
        print("channel: \(member.channelID)")
        print("user: \(member.userID)")
        if let msgCount = member.msgCount {
            print("messages-read: \(msgCount)")
        }
        if let mentionCount = member.mentionCount {
            print("mentions: \(mentionCount)")
        }
        printNotifyProps(member.channelNotifyProps)
    }

    static func printChannelMembers(_ members: [MattermostChannelMember]) {
        let sortedMembers = members.sorted(by: channelMemberSort)
        guard !writeJSONIfRequested(sortedMembers) else { return }
        for member in sortedMembers {
            print("\(member.channelID)\t\(member.userID)\t\(member.roles ?? "")")
        }
    }

    static func channelMemberSort(
        _ lhs: MattermostChannelMember,
        _ rhs: MattermostChannelMember
    ) -> Bool {
        if lhs.channelID == rhs.channelID {
            return lhs.userID.localizedStandardCompare(rhs.userID) == .orderedAscending
        }
        return lhs.channelID.localizedStandardCompare(rhs.channelID) == .orderedAscending
    }

    static func printNotifyProps(_ props: MattermostChannelNotifyProps) {
        guard !writeJSONIfRequested(props) else { return }
        for (name, value) in props.rawValues.sorted(by: { $0.key < $1.key }) {
            print("notify.\(name): \(value)")
        }
    }

    static func printChannelUnread(_ unread: MattermostChannelUnread) {
        guard !writeJSONIfRequested(unread) else { return }
        print("channel: \(unread.channelID)")
        if let teamID = unread.teamID, !teamID.isEmpty {
            print("team: \(teamID)")
        }
        print("messages: \(unread.msgCount)")
        print("mentions: \(unread.mentionCount)")
    }

    static func printPosts(_ posts: [MattermostPost]) {
        guard !writeJSONIfRequested(posts) else { return }
        for post in posts {
            printPost(post)
        }
    }

    static func printSearchResults(_ results: MattermostPostSearchResults) {
        guard !writeJSONIfRequested(results) else { return }
        for post in results.orderedPosts.prefix(20) {
            printPost(post)
        }
    }

    static func printPost(_ post: MattermostPost) {
        guard !writeJSONIfRequested(post) else { return }
        let message = post.message.replacing("\n", with: " ")
        print("\(post.id)\t\(post.channelID)\t\(post.userID)\t\(message)")
    }

    static func printFileInfo(_ fileInfo: MattermostFileInfo) {
        guard !writeJSONIfRequested(fileInfo) else { return }
        print("\(fileInfo.id)\t\(fileInfo.name)\t\(fileInfo.size ?? 0)")
    }

    static func printEmoji(_ emoji: [MattermostCustomEmoji]) {
        let sortedEmoji = emoji.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        guard !writeJSONIfRequested(sortedEmoji) else { return }
        for item in sortedEmoji {
            print("\(item.id)\t\(item.name)")
        }
    }

    static func printLiveEvent(_ event: MattermostLiveEvent) {
        guard !writeJSONIfRequested(event) else { return }
        let channelID = event.broadcast?.channelID ?? "-"
        let postID = (try? event.decodedPost()?.id) ?? "-"
        print("\(event.event)\t\(channelID)\t\(postID)")
    }

    static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "txt", "md", "log":
            "text/plain"
        case "json":
            "application/json"
        case "png":
            "image/png"
        case "jpg", "jpeg":
            "image/jpeg"
        case "gif":
            "image/gif"
        case "pdf":
            "application/pdf"
        default:
            "application/octet-stream"
        }
    }

    static func printChannels(_ channels: [MattermostChannel]) {
        let sortedChannels = channels.sorted(by: channelSort)
        guard !writeJSONIfRequested(sortedChannels) else { return }
        for channel in sortedChannels {
            let displayName = channel.displayName.isEmpty ? channel.name : channel.displayName
            print("\(channel.id)\t\(channel.type.rawValue)\t\(displayName)")
        }
    }

    static func printChannel(_ channel: MattermostChannel) {
        guard !writeJSONIfRequested(channel) else { return }
        print("channel: \(channel.id)")
        if let teamID = channel.teamID, !teamID.isEmpty {
            print("team: \(teamID)")
        }
        print("type: \(channel.type.rawValue)")
        print("name: \(channel.name)")
        print("display-name: \(channel.displayName)")
    }

    static func printChannelStats(_ stats: MattermostChannelStats) {
        guard !writeJSONIfRequested(stats) else { return }
        if let channelID = stats.channelID, !channelID.isEmpty {
            print("channel: \(channelID)")
        }
        if let memberCount = stats.memberCount {
            print("members: \(memberCount)")
        }
        if let guestCount = stats.guestCount {
            print("guests: \(guestCount)")
        }
        if let pinnedPostCount = stats.pinnedPostCount {
            print("pinned-posts: \(pinnedPostCount)")
        }
        if let totalMessageCount = stats.totalMessageCount {
            print("total-messages: \(totalMessageCount)")
        }
    }

    static func printTimezones(_ timezones: [String]) {
        let sortedTimezones = timezones.sorted()
        guard !writeJSONIfRequested(sortedTimezones) else { return }
        for timezone in sortedTimezones {
            print(timezone)
        }
    }

    static func printChannelMemberCounts(_ counts: [String: Int64]) {
        guard !writeJSONIfRequested(counts) else { return }
        for channelID in counts.keys.sorted() {
            print("\(channelID)\t\(counts[channelID] ?? 0)")
        }
    }

    static func printThreads(_ threadList: MattermostThreadList) {
        guard !writeJSONIfRequested(threadList) else { return }
        print("total: \(threadList.total)")
        print("unread-threads: \(threadList.totalUnreadThreads)")
        print("unread-mentions: \(threadList.totalUnreadMentions)")
        for thread in threadList.threads {
            print("\(thread.id)\treplies:\(thread.replyCount)\tunread:\(thread.unreadReplies)\tmentions:\(thread.unreadMentions)\turgent:\(thread.isUrgent)")
        }
    }

    static func channelSort(_ lhs: MattermostChannel, _ rhs: MattermostChannel) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    static func sidebarCategorySort(
        _ lhs: MattermostSidebarCategory,
        _ rhs: MattermostSidebarCategory
    ) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

}
