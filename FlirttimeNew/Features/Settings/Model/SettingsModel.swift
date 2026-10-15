//
//  SettingsModel.swift
//  FlirttimeNew
//

import Foundation

/// Keys of the `notify_settings` object the profile API returns and accepts.
enum NotificationSettingKey: String, CaseIterable {
    case newMessage = "new_message"
    case newMatches = "new_matches"
    case likesCommentsCalls = "likes_comments_calls"
    case profileVisit = "profile_visit"
    case push
    case email
    case appUpdates = "app_updates"
    case promotion
    case discountAvailable = "discount_available"
    case newServiceAvailable = "new_service_available"
    case newTipsAvailable = "new_tips_available"

    /// Activity alerts are on for new accounts; marketing ones are opt-in.
    var defaultValue: Bool {
        switch self {
        case .newMessage, .newMatches, .likesCommentsCalls, .profileVisit, .push, .appUpdates:
            return true
        case .email, .promotion, .discountAvailable, .newServiceAvailable, .newTipsAvailable:
            return false
        }
    }
}

extension NotifySettings {
    func value(for key: NotificationSettingKey) -> Bool? {
        switch key {
        case .newMessage: return newMessage
        case .newMatches: return newMatches
        case .likesCommentsCalls: return likesCommentsCalls
        case .profileVisit: return profileVisit
        case .push: return push
        case .email: return email
        case .appUpdates: return appUpdates
        case .promotion: return promotion
        case .discountAvailable: return discountAvailable
        case .newServiceAvailable: return newServiceAvailable
        case .newTipsAvailable: return newTipsAvailable
        }
    }
}

/// Profile-visibility flags stored on `user_info`.
enum VisibilitySettingKey: String {
    case ageShow = "age_show"
    case distanceShow = "distance_show"
    case onlineShow = "online_show"
    case enablePublicSearch = "enable_public_search"
}

enum FilteredProfileKind: Int {
    case blocked
    case reported
}

struct FilteredProfile {
    /// The blocked or reported user; `nil` when a report has no target user.
    let userId: String?
    /// Row id: the block id or report id.
    let id: String
    let name: String
    let photo: String?
    let subtitle: String?
    /// Report status: pending | reviewed | dismissed | resolved.
    let status: String?
}

// MARK: - Blocked users / my reports API

struct ListPagination: Codable {
    let total: Int?
    let page: Int?
    let limit: Int?
    let totalPages: Int?

    var hasMore: Bool {
        guard let page, let totalPages else { return false }
        return page < totalPages
    }
}

struct BlockedUsersPage: Codable {
    let blockedUsers: [BlockedUser]
    let pagination: ListPagination?
}

struct BlockedUser: Codable {
    let userId: String
    let name: String?
    let username: String?
    let profilePhoto: String?
    let reason: String?
    let blockedAt: String?

    var profile: FilteredProfile {
        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = [trimmedUsername, trimmedName].first { !$0.isEmpty } ?? "Flirt Time member"
        let subtitle = !trimmedName.isEmpty && trimmedName != title ? trimmedName : "Can't see or message you"
        return FilteredProfile(userId: userId, id: userId, name: title, photo: profilePhoto,
                               subtitle: subtitle, status: nil)
    }
}

struct MyReportsPage: Codable {
    let reports: [UserReport]
    let pagination: ListPagination?
}

struct UserReport: Codable {
    let id: String
    let targetUserId: String?
    /// user | moment
    let targetType: String?
    let targetName: String?
    let targetPhoto: String?
    let momentId: String?
    let momentThumbnail: String?
    /// API code, e.g. "harassment"; `description` is the readable label.
    let reason: String?
    let description: String?
    /// pending | reviewed | dismissed | resolved
    let status: String?
    let createdAt: String?

    var profile: FilteredProfile {
        let name = targetName?.isEmpty == false ? targetName! : "Flirt Time member"
        let reasonText = description?.isEmpty == false
            ? description
            : reason.map { $0.replacingOccurrences(of: "_", with: " ").capitalizingFirstLetter }
        let isMoment = targetType == "moment"
        let subject = isMoment ? "Moment" : "Profile"
        let subtitle = [subject, reasonText].compactMap { $0 }.joined(separator: " · ")
        let thumbnail = momentThumbnail?.isEmpty == false ? momentThumbnail : nil
        let photo = isMoment ? (thumbnail ?? targetPhoto) : targetPhoto
        return FilteredProfile(userId: targetUserId, id: id, name: name, photo: photo,
                               subtitle: subtitle, status: status)
    }
}

private extension String {
    var capitalizingFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

enum FAQCategory: Int, CaseIterable {
    case account
    case matches
    case premium
    case safety

    var title: String {
        switch self {
        case .account: return "Account & profile"
        case .matches: return "Matches & chat"
        case .premium: return "Premium & coins"
        case .safety: return "Safety & privacy"
        }
    }
}

struct FAQItem {
    let category: FAQCategory
    let question: String
    let answer: String
}

// TODO: load the FAQ list from the help-and-support endpoint once it is integrated.
enum FAQCatalog {
    static let items: [FAQItem] = [
        FAQItem(category: .account,
                question: "How do I edit my profile?",
                answer: "Open the Profile tab and tap Edit Profile. You can update your photos, bio, interests and the details people see on your card."),
        FAQItem(category: .account,
                question: "Why should I verify my profile?",
                answer: "Verified profiles get a badge on their card, which tells people your photos really match you. Verified members get noticeably more matches."),
        FAQItem(category: .account,
                question: "Can I change my email address?",
                answer: "Yes. Go to Settings > Privacy & safety > Email. We'll send a code to your new address to confirm it's yours."),
        FAQItem(category: .account,
                question: "How do I delete my account?",
                answer: "Go to Settings > Personal details and tap Delete account. This removes your profile, matches and messages, and can't be undone."),
        FAQItem(category: .matches,
                question: "How does matching work?",
                answer: "When you like someone and they like you back, it's a match. You can then start chatting right away."),
        FAQItem(category: .matches,
                question: "Why can't I message someone?",
                answer: "You can chat with people once you've matched. If a conversation disappears, the other person may have unmatched or blocked you."),
        FAQItem(category: .matches,
                question: "What are Moments?",
                answer: "Moments are photos and videos you share on your profile. People can react, comment and send gifts on them, which is a great way to start a conversation."),
        FAQItem(category: .premium,
                question: "What do I get with Premium?",
                answer: "Premium unlocks unlimited likes, shows you everyone who liked you, lets you read compliments and removes ads."),
        FAQItem(category: .premium,
                question: "How do I cancel my subscription?",
                answer: "Subscriptions are managed by Apple. Open the Settings app on your iPhone, tap your name, then Subscriptions, and choose Flirt Time."),
        FAQItem(category: .premium,
                question: "What are coins used for?",
                answer: "Coins let you send gifts on Moments and unlock extra features. You can top them up anytime from the Coins shop."),
        FAQItem(category: .safety,
                question: "How do I block or report someone?",
                answer: "Open their profile, tap the menu in the top corner and choose Block or Report. Our team reviews every report."),
        FAQItem(category: .safety,
                question: "How do I unblock someone?",
                answer: "Go to Settings > Blocked & reported, find the person under Blocked and tap Unblock."),
        FAQItem(category: .safety,
                question: "Tips for meeting someone in person",
                answer: "Meet in a public place, tell a friend where you're going, arrange your own transport and never send money to someone you haven't met.")
    ]

    static func items(in category: FAQCategory?) -> [FAQItem] {
        guard let category else { return items }
        return items.filter { $0.category == category }
    }
}
