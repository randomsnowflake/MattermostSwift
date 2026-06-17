import Foundation
@_spi(Testing) import MattermostSwift

extension MattermostSwiftCLI {
    static func printServerInfo(_ serverInfo: MattermostServerInfo) {
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
        for user in users.sorted(by: userSort) {
            print("\(user.id)\t\(user.username)")
        }
    }

    static func printImageDownload(label: String, userID: String, data: Data) {
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
        print("users: \(autocomplete.users.count)")
        print("in-channel: \(autocomplete.inChannel.count)")
        print("out-of-channel: \(autocomplete.outOfChannel.count)")
        printUsers(autocomplete.allUsers)
    }

    static func userSort(_ lhs: MattermostUser, _ rhs: MattermostUser) -> Bool {
        lhs.username.localizedStandardCompare(rhs.username) == .orderedAscending
    }

    static func printStatus(_ status: MattermostUserStatus) {
        print("\(status.userId)\t\(status.status)")
    }

    static func printTeam(_ team: MattermostTeam) {
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
        for team in teams.sorted(by: teamSort) {
            print("\(team.id)\t\(team.name)\t\(team.displayName)")
        }
    }

    static func printTeamMembers(_ members: [MattermostTeamMember]) {
        for member in members.sorted(by: teamMemberSort) {
            print("\(member.teamId)\t\(member.userId)\t\(member.roles ?? "")")
        }
    }

    static func teamSort(_ lhs: MattermostTeam, _ rhs: MattermostTeam) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    static func teamMemberSort(_ lhs: MattermostTeamMember, _ rhs: MattermostTeamMember) -> Bool {
        if lhs.teamId == rhs.teamId {
            return lhs.userId.localizedStandardCompare(rhs.userId) == .orderedAscending
        }
        return lhs.teamId.localizedStandardCompare(rhs.teamId) == .orderedAscending
    }

    static func printCategories(_ categories: [MattermostSidebarCategory]) {
        for category in categories {
            print("\(category.id)\t\(category.type)\t\(category.displayName)\t\(category.channelIds.count) channels")
        }
    }

    static func printPreferences(_ preferences: [MattermostPreference]) {
        for preference in preferences.sorted(by: preferenceSort) {
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
        print("channel: \(member.channelId)")
        print("user: \(member.userId)")
        if let msgCount = member.msgCount {
            print("messages-read: \(msgCount)")
        }
        if let mentionCount = member.mentionCount {
            print("mentions: \(mentionCount)")
        }
        printNotifyProps(member.channelNotifyProps)
    }

    static func printChannelMembers(_ members: [MattermostChannelMember]) {
        for member in members.sorted(by: channelMemberSort) {
            print("\(member.channelId)\t\(member.userId)\t\(member.roles ?? "")")
        }
    }

    static func channelMemberSort(
        _ lhs: MattermostChannelMember,
        _ rhs: MattermostChannelMember
    ) -> Bool {
        if lhs.channelId == rhs.channelId {
            return lhs.userId.localizedStandardCompare(rhs.userId) == .orderedAscending
        }
        return lhs.channelId.localizedStandardCompare(rhs.channelId) == .orderedAscending
    }

    static func printNotifyProps(_ props: MattermostChannelNotifyProps) {
        for (name, value) in props.rawValues.sorted(by: { $0.key < $1.key }) {
            print("notify.\(name): \(value)")
        }
    }

    static func printChannelUnread(_ unread: MattermostChannelUnread) {
        print("channel: \(unread.channelId)")
        if let teamID = unread.teamId, !teamID.isEmpty {
            print("team: \(teamID)")
        }
        print("messages: \(unread.msgCount)")
        print("mentions: \(unread.mentionCount)")
    }

    static func printPosts(_ posts: [MattermostPost]) {
        for post in posts {
            printPost(post)
        }
    }

    static func printSearchResults(_ results: MattermostPostSearchResults) {
        for post in results.orderedPosts.prefix(20) {
            printPost(post)
        }
    }

    static func printPost(_ post: MattermostPost) {
        let message = post.message.replacing("\n", with: " ")
        print("\(post.id)\t\(post.channelId)\t\(post.userId)\t\(message)")
    }

    static func printFileInfo(_ fileInfo: MattermostFileInfo) {
        print("\(fileInfo.id)\t\(fileInfo.name)\t\(fileInfo.size ?? 0)")
    }

    static func printEmoji(_ emoji: [MattermostCustomEmoji]) {
        for item in emoji.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            print("\(item.id)\t\(item.name)")
        }
    }

    static func printLiveEvent(_ event: MattermostLiveEvent) {
        let channelID = event.broadcast?.channelId ?? "-"
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
        for channel in channels.sorted(by: channelSort) {
            let displayName = channel.displayName.isEmpty ? channel.name : channel.displayName
            print("\(channel.id)\t\(channel.type)\t\(displayName)")
        }
    }

    static func printChannel(_ channel: MattermostChannel) {
        print("channel: \(channel.id)")
        if let teamID = channel.teamId, !teamID.isEmpty {
            print("team: \(teamID)")
        }
        print("type: \(channel.type)")
        print("name: \(channel.name)")
        print("display-name: \(channel.displayName)")
    }

    static func printChannelStats(_ stats: MattermostChannelStats) {
        if let channelID = stats.channelId, !channelID.isEmpty {
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
        for timezone in timezones.sorted() {
            print(timezone)
        }
    }

    static func printChannelMemberCounts(_ counts: [String: Int64]) {
        for channelID in counts.keys.sorted() {
            print("\(channelID)\t\(counts[channelID] ?? 0)")
        }
    }

    static func printThreads(_ threadList: MattermostThreadList) {
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
