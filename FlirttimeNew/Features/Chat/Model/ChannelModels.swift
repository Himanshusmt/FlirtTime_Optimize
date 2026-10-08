//
//  ChannelModels.swift
//  FlirttimeNew
//
//  Created by Awais on 27/11/25.
//

import Foundation

struct ChannelSummary: Identifiable, Codable {
    struct UserRef: Codable {
        let userId: String
        let userName: String?
    }
    struct MemberRef: Codable, Identifiable {
        let userId: String
        let userName: String?
        let id: String
    }
    let id: String
    let name: String
    let description: String?
    let createdBy: UserRef
    let admins: [MemberRef]
    let followers: [MemberRef]
    let createdAt: String?
    let updatedAt: String?
    var hasFollowed: Bool?
    var isOwner: Bool?
    var isAdmin: Bool?
    var shareLink: String?
    var icon: String?
    var followersCount: Int?
    var isPublic: Bool?
    var inviteSlug: String?
    var myRole: String?
    var unreadCount: Int?
    var lastMessagePreview: String?
    var lastMessageType: String?
    var lastMessageSenderId: String?

    /// Uses server-provided count when available, otherwise falls back to followers array
    var resolvedFollowersCount: Int {
        followersCount ?? followers.count
    }

    init(id: String,
         name: String,
         description: String?,
         createdBy: UserRef,
         admins: [MemberRef],
         followers: [MemberRef],
         createdAt: String?,
         updatedAt: String?,
         hasFollowed: Bool?,
         isOwner: Bool?,
         isAdmin: Bool?,
         shareLink: String? = nil,
         icon: String? = nil,
         followersCount: Int? = nil,
         isPublic: Bool? = nil,
         inviteSlug: String? = nil,
         myRole: String? = nil,
         unreadCount: Int? = nil,
         lastMessagePreview: String? = nil,
         lastMessageType: String? = nil,
         lastMessageSenderId: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.createdBy = createdBy
        self.admins = admins
        self.followers = followers
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.hasFollowed = hasFollowed
        self.isOwner = isOwner
        self.isAdmin = isAdmin
        self.shareLink = shareLink
        self.icon = icon
        self.followersCount = followersCount
        self.isPublic = isPublic
        self.inviteSlug = inviteSlug
        self.myRole = myRole
        self.unreadCount = unreadCount
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageType = lastMessageType
        self.lastMessageSenderId = lastMessageSenderId
    }

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String ?? dictionary["_id"] as? String,
              let name = dictionary["name"] as? String else { return nil }

        let description = dictionary["description"] as? String

        // createdBy
        var createdBy: UserRef = UserRef(userId: "", userName: nil)
        if let createdByDict = dictionary["createdBy"] as? [String: Any] {
            let uid = createdByDict["userId"] as? String ?? createdByDict["id"] as? String ?? ""
            let uname = createdByDict["userName"] as? String ?? createdByDict["username"] as? String
            createdBy = UserRef(userId: uid, userName: uname)
        }

        // admins / members with admin role
        var admins: [MemberRef] = []
        if let adminsArr = dictionary["admins"] as? [[String: Any]] {
            admins = adminsArr.compactMap { dict in
                let uid = dict["userId"] as? String ?? dict["id"] as? String ?? ""
                let uname = dict["userName"] as? String ?? dict["username"] as? String
                let mid = dict["id"] as? String ?? uid
                return MemberRef(userId: uid, userName: uname, id: mid)
            }
        } else if let membersArr = dictionary["members"] as? [[String: Any]] {
            admins = membersArr.compactMap { dict in
                let role = (dict["role"] as? String)?.lowercased() ?? ""
                guard role == "admin" || role == "owner" else { return nil }
                let uid = dict["userId"] as? String ?? dict["id"] as? String ?? ""
                let uname = dict["userName"] as? String ?? dict["username"] as? String
                let mid = dict["id"] as? String ?? uid
                return MemberRef(userId: uid, userName: uname, id: mid)
            }
        }

        // followers
        var followers: [MemberRef] = []
        if let followersArr = dictionary["followers"] as? [[String: Any]] {
            followers = followersArr.compactMap { dict in
                let uid = dict["userId"] as? String ?? dict["id"] as? String ?? ""
                let uname = dict["userName"] as? String ?? dict["username"] as? String
                let mid = dict["id"] as? String ?? uid
                return MemberRef(userId: uid, userName: uname, id: mid)
            }
        }

        let createdAt = dictionary["createdAt"] as? String
        let updatedAt = dictionary["updatedAt"] as? String

        func parseBool(_ key: String) -> Bool? {
            if let b = dictionary[key] as? Bool {
                return b
            } else if let n = dictionary[key] as? NSNumber {
                return n.boolValue
            } else if let s = dictionary[key] as? String {
                let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true","1","yes"].contains(lower) { return true }
                else if ["false","0","no"].contains(lower) { return false }
            }
            return nil
        }

        let myRole = dictionary["myRole"] as? String
        let roleLower = myRole?.lowercased()
        let hasFollowed = parseBool("hasFollowed") ?? parseBool("isFollowing")
            ?? (roleLower == "follower" || roleLower == "admin" || roleLower == "owner" ? true : nil)
        let isOwner = parseBool("isOwner") ?? (roleLower == "owner")
        let isAdmin = parseBool("isAdmin") ?? (roleLower == "admin" || roleLower == "owner")
        let inviteSlug = dictionary["inviteSlug"] as? String
        let shareLink = dictionary["shareLink"] as? String
            ?? inviteSlug.map { "https://\(ChatConfig.publicWebHost)/channels/\($0)" }
        let icon = dictionary["avatarPath"] as? String ?? dictionary["icon"] as? String
        let followersCount = dictionary["followersCount"] as? Int ?? dictionary["followerCount"] as? Int
        let isPublic = parseBool("isPublic")
        let settings = dictionary["settings"] as? [String: Any]
        let unreadCount = dictionary["unreadCount"] as? Int
            ?? settings?["unreadCount"] as? Int
            ?? (dictionary["unreadCount"] as? NSNumber)?.intValue
            ?? (settings?["unreadCount"] as? NSNumber)?.intValue

        let lastMessageDict = dictionary["lastMessage"] as? [String: Any]
        let lastMessagePreview = dictionary["lastMessagePreview"] as? String
            ?? lastMessageDict?["contentPreview"] as? String
            ?? lastMessageDict?["body"] as? String
            ?? lastMessageDict?["content"] as? String
        let lastMessageType = dictionary["lastMessageType"] as? String
            ?? lastMessageDict?["messageType"] as? String
            ?? lastMessageDict?["type"] as? String
        let lastMessageSenderId = dictionary["lastMessageSenderId"] as? String
            ?? lastMessageDict?["senderId"] as? String
            ?? (lastMessageDict?["sender"] as? [String: Any])?["id"] as? String
            ?? (lastMessageDict?["sender"] as? [String: Any])?["userId"] as? String

        self.init(id: id,
                  name: name,
                  description: description,
                  createdBy: createdBy,
                  admins: admins,
                  followers: followers,
                  createdAt: createdAt,
                  updatedAt: updatedAt,
                  hasFollowed: hasFollowed,
                  isOwner: isOwner,
                  isAdmin: isAdmin,
                  shareLink: shareLink,
                  icon: icon,
                  followersCount: followersCount,
                  isPublic: isPublic,
                  inviteSlug: inviteSlug,
                  myRole: myRole,
                  unreadCount: unreadCount,
                  lastMessagePreview: lastMessagePreview,
                  lastMessageType: lastMessageType,
                  lastMessageSenderId: lastMessageSenderId)
    }

    init(fromBrowse item: ChannelBrowseItemAPI) {
        let slug = item.inviteSlug
        self.init(
            id: item.id,
            name: item.name,
            description: item.description,
            createdBy: UserRef(userId: "", userName: nil),
            admins: [],
            followers: [],
            createdAt: item.createdAt,
            updatedAt: nil,
            hasFollowed: item.resolvedIsFollowing,
            isOwner: false,
            isAdmin: false,
            shareLink: slug.map { "https://\(ChatConfig.publicWebHost)/channels/\($0)" },
            icon: item.resolvedAvatarPath,
            followersCount: item.resolvedFollowersCount,
            isPublic: item.isPublic,
            inviteSlug: slug,
            myRole: item.resolvedIsFollowing ? "follower" : nil
        )
    }

    init(fromDetail detail: ChannelDetailAPI) {
        let role = detail.myRole?.lowercased()
        let members = detail.members ?? []
        let admins = members.compactMap { m -> MemberRef? in
            let r = (m.role ?? "").lowercased()
            guard r == "admin" || r == "owner" else { return nil }
            let uid = m.id ?? ""
            return MemberRef(userId: uid, userName: m.userName ?? m.username, id: uid)
        }
        let owner = members.first { ($0.role ?? "").lowercased() == "owner" }
        let slug = detail.inviteSlug
        let isFollowerRole = role == "follower" || role == "admin" || role == "owner"
        self.init(
            id: detail.id,
            name: detail.name,
            description: detail.description,
            createdBy: UserRef(
                userId: owner?.id ?? "",
                userName: owner?.userName ?? owner?.username
            ),
            admins: admins,
            followers: [],
            createdAt: detail.createdAt,
            updatedAt: detail.updatedAt ?? detail.lastMessageAt,
            hasFollowed: detail.resolvedIsFollowing || isFollowerRole,
            isOwner: role == "owner",
            isAdmin: role == "admin" || role == "owner",
            shareLink: slug.map { "https://\(ChatConfig.publicWebHost)/channels/\($0)" } ?? detail.inviteSlug,
            icon: detail.resolvedAvatarPath,
            followersCount: detail.resolvedFollowersCount,
            isPublic: detail.isPublic,
            inviteSlug: slug,
            myRole: detail.myRole,
            unreadCount: detail.settings?.unreadCount,
            lastMessagePreview: detail.resolvedLastMessagePreview,
            lastMessageType: detail.resolvedLastMessageType,
            lastMessageSenderId: detail.lastMessageSenderId ?? detail.lastMessage?.senderId
        )
    }

    var resolvedLastMessagePreview: String {
        ChannelSummary.displayPreview(content: lastMessagePreview, type: lastMessageType)
    }

    static func displayPreview(content: String?, type: String?) -> String {
        let rawType = (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text = (content ?? "")
            .htmlToString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if rawType.isEmpty || rawType == "text" || rawType == "system" {
            return text
        }
        if rawType == "call" || rawType.contains("call") {
            return ConversationMessage.callPreviewText(content: content, messageType: rawType)
        }
        let typeName = ConversationMessage.messageTypeDisplayName(rawType)
        if typeName.isEmpty || typeName == ChatStrings.chat_message.localizedString() {
            return text
        }
        return typeName
    }

    var resolvedShareURL: URL? {
        guard let link = ChannelShareLinkBuilder.resolve(shareLink: shareLink, inviteSlug: inviteSlug) else {
            return nil
        }
        return URL(string: link)
    }
}

enum ChannelShareLinkBuilder {
    static func resolve(shareLink: String?, inviteSlug: String?) -> String? {
        let trimmedLink = shareLink?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedLink, !trimmedLink.isEmpty, URL(string: trimmedLink) != nil {
            return trimmedLink
        }
        return nil
    }

    /// Universal link path segment after `/channels/` — e.g. `qa_summit`.
    static func inviteSlug(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(where: { $0.caseInsensitiveCompare("channels") == .orderedSame }),
              index + 1 < parts.count else {
            return nil
        }
        let slug = parts[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return slug.isEmpty ? nil : slug
    }

    /// Legacy channel id link: `.../chat/channel/{channelId}`.
    static func channelId(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(where: { $0.caseInsensitiveCompare("channel") == .orderedSame }),
              index + 1 < parts.count else {
            return nil
        }
        let channelId = parts[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return channelId.isEmpty ? nil : channelId
    }
}

extension Notification.Name {
    static let channelFollowStateChanged = Notification.Name("ChannelFollowStateChanged")
    static let channelDeleted = Notification.Name("ChannelDeleted")
    static let channelUnreadCountUpdated = Notification.Name("ChannelUnreadCountUpdated")
    static let channelLastMessageUpdated = Notification.Name("ChannelLastMessageUpdated")
}
