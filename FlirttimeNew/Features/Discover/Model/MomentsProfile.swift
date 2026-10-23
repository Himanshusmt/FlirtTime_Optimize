//
//  MomentsProfile.swift
//  FlirttimeNew
//
//  Discover models. Everything shown on a Discover card comes from real profile
//  data; reasons and shared interests are derived, never invented.
//

import UIKit

// MARK: - Actions

/// UI abstraction over the existing interaction APIs (Super Like, Like, Dislike, Nope).
enum MomentsAction: CaseIterable {
    case superVibe
    case interested
    case notMyVibe
    case nope

    var displayName: String {
        switch self {
        case .superVibe: return "Super Like"
        case .interested: return "Interested"
        case .notMyVibe: return "Not Interested"
        case .nope: return "Nope"
        }
    }

    var symbolName: String {
        switch self {
        case .superVibe: return "sparkles"
        case .interested: return "heart.fill"
        case .notMyVibe: return "xmark"
        case .nope: return "arrow.down"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .superVibe: return UIColor(red: 0.93, green: 0.09, blue: 0.16, alpha: 1)
        case .interested: return AppColor.Punch
        case .notMyVibe: return AppColor.MineShaft
        case .nope: return AppColor.Boulder
        }
    }

    /// Value sent as `interaction_type` to the existing action endpoint.
    var interactionType: String {
        switch self {
        case .superVibe: return Constants.ActionType.favorite
        case .interested: return Constants.ActionType.like
        case .notMyVibe: return Constants.ActionType.dislike
        case .nope: return Constants.ActionType.nope
        }
    }

    /// Value sent as `action` to POST `discovery/actions`.
    var apiAction: String {
        switch self {
        case .superVibe: return "super_like"
        case .interested: return "like"
        case .notMyVibe, .nope: return "nope"
        }
    }

    var sendsConnection: Bool {
        self == .superVibe || self == .interested
    }

    var analyticsEvent: MomentsAnalytics.Event {
        switch self {
        case .superVibe: return .gestureSuperVibe
        case .interested: return .gestureInterested
        case .notMyVibe: return .gestureNotMyVibe
        case .nope: return .gestureNope
        }
    }
}

/// Optional "Connect because…" reasons sent along with an interest.
enum ConnectReason: String, CaseIterable {
    case loveTheirVibe = "Love their profile"
    case sameInterests = "Same interests"
    case likedMoment = "Liked their Moment"
    case greatEnergy = "Great energy"
    case wantToChat = "Want to chat"
}

// MARK: - Profile

struct MomentsInterest: Hashable {
    let id: Int
    let title: String
    let emoji: String

    var chipTitle: String { "\(emoji) \(title)" }
}

struct MomentsVoiceIntro {
    let transcript: String
    let duration: TimeInterval
    /// Remote audio file. `nil` for mock profiles, which read the transcript aloud instead.
    let audioURL: URL?

    var durationText: String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct MomentsStory: Hashable {
    let id: Int
    /// Empty for a text-only Moment, which is shown as its caption on the brand gradient.
    let imagePath: String
    let isVideo: Bool
    var caption: String?
    var postedAt: Date?
    /// Index into `MomentsTheme.storyBackgrounds` for a text Moment.
    var textBackground: Int = 0
    /// Activity on the signed-in user's own Quick Moments; `nil` for other people's.
    var reactionsCount: Int?
    var repliesCount: Int?
    var topReactions: [String] = []
    /// Whether the signed-in visitor has already seen this Quick Moment.
    var hasViewed: Bool = false

    var isText: Bool { imagePath.isEmpty }

    /// "2h ago"
    var postedAgoText: String? {
        guard let postedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: postedAt, relativeTo: Date())
    }
}

struct MomentsProfile: Equatable {
    let id: Int
    let displayName: String
    /// `nil` when the user hides their age.
    let age: Int?
    let isVerified: Bool
    /// API gender code: 1 = man, 2 = woman, 3 = non-binary.
    let gender: Int?
    /// `nil` when the user hides their location.
    let city: String?
    /// `nil` when the user hides their distance or it is unknown.
    let distanceKm: Double?
    /// `nil` when the user hides their online status.
    let isOnline: Bool?
    let datingIntent: String?
    let photos: [String]
    let about: String
    let interests: [MomentsInterest]
    let sharedInterests: [MomentsInterest]
    /// API `commonInterestsCount` when provided; otherwise derived from `sharedInterests`.
    var commonInterestsCount: Int? = nil
    let reasons: [String]
    let voiceIntro: MomentsVoiceIntro?
    var moments: [MomentsStory]
    /// Overlap of real interests (plus same city); `nil` when nothing is shared, so no score is shown.
    let vibeScore: Int?
    /// Total moments posted, which can exceed the `moments` preview.
    var momentsCount: Int = 0
    /// Backend user id (UUID) for profiles from `discovery/people`; `id` is a local id derived from it.
    var remoteUserId: String? = nil
    /// "More about me" answers from GET `users/:userId/profile`.
    var aboutAnswers: [OtherUserAboutItem] = []

    static func == (lhs: MomentsProfile, rhs: MomentsProfile) -> Bool {
        lhs.id == rhs.id
    }

    var nameAndAge: String {
        guard let age else { return displayName }
        return "\(displayName), \(age)"
    }

    var distanceText: String? {
        guard let distanceKm else { return nil }
        if distanceKm < 1 { return "Less than 1 km away" }
        return "\(Int(distanceKm.rounded())) km away"
    }

    /// "Mumbai · 3 km away"
    var locationLine: String? {
        let parts = [city, distanceText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "55 Moments"; `nil` when the user hasn't posted any.
    var momentsCountText: String? {
        switch momentsCount {
        case ..<1: return nil
        case 1: return "1 Moment"
        default: return "\(momentsCount.vibeCountText) Moments"
        }
    }

    var sharedVibesText: String? {
        let count = commonInterestsCount ?? sharedInterests.count
        switch count {
        case ..<1: return nil
        case 1: return "1 Shared Interest"
        default: return "\(count) Shared Interests"
        }
    }

    /// Icon for a "Why This Match?" reason row.
    func emoji(forReason reason: String) -> String {
        let lowered = reason.lowercased()
        if let interest = sharedInterests.first(where: { lowered.contains($0.title.lowercased()) }) {
            return interest.emoji
        }
        if lowered.contains("both in") { return "📍" }
        if lowered.contains("in common") { return "💞" }
        return "✨"
    }

    var accessibilitySummary: String {
        var parts = [nameAndAge]
        if isVerified { parts.append("Verified") }
        if let locationLine { parts.append(locationLine) }
        if let isOnline { parts.append(isOnline ? "Online" : "Offline") }
        if let momentsCountText { parts.append(momentsCountText) }
        if let datingIntent { parts.append("Looking for \(datingIntent)") }
        if !interests.isEmpty { parts.append("Interests: " + interests.map(\.title).joined(separator: ", ")) }
        return parts.joined(separator: ". ")
    }
}

/// A reaction to one specific part of a profile; it travels with the interest as its context.
struct MomentsReaction: Equatable {

    enum Target: Equatable {
        case photo(Int)
        case whyVibe
        case ownWords
        case voice
        case moments
    }

    let target: Target

    /// "Liked your photo", shown to the sender and sent as the connection context.
    var title: String {
        switch target {
        case .photo: return "Liked your photo"
        case .whyVibe: return "Loved why we match"
        case .ownWords: return "Liked your words"
        case .voice: return "Loved your voice intro"
        case .moments: return "Liked your Moments"
        }
    }

    /// "Maya's voice intro"
    func subject(for name: String) -> String {
        switch target {
        case .photo: return "\(name)'s photo"
        case .whyVibe: return "why you match with \(name)"
        case .ownWords: return "\(name)'s words"
        case .voice: return "\(name)'s voice intro"
        case .moments: return "\(name)'s Moments"
        }
    }

    var analyticsValue: String {
        switch target {
        case .photo(let index): return "photo_\(index)"
        case .whyVibe: return "why_vibe"
        case .ownWords: return "own_words"
        case .voice: return "voice"
        case .moments: return "moments"
        }
    }
}

/// Result of a confirmed Discover action.
struct MomentsActionOutcome {
    let action: MomentsAction
    let profile: MomentsProfile
    let isMatch: Bool
    let reaction: MomentsReaction?
}

// MARK: - Theme

enum MomentsTheme {
    static let brandGradient: [UIColor] = [
        UIColor(red: 0.85, green: 0.17, blue: 0.17, alpha: 1),
        UIColor(red: 0.98, green: 0.30, blue: 0.37, alpha: 1),
        UIColor(red: 1.0, green: 0.52, blue: 0.42, alpha: 1)
    ]
    static let nightGradient: [UIColor] = [
        UIColor(red: 0.16, green: 0.07, blue: 0.14, alpha: 1),
        UIColor(red: 0.36, green: 0.10, blue: 0.22, alpha: 1)
    ]
    static let blushGradient: [UIColor] = [
        UIColor(red: 1.0, green: 0.95, blue: 0.95, alpha: 1),
        UIColor(red: 1.0, green: 0.88, blue: 0.90, alpha: 1)
    ]
    static let gold = UIColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1)

    /// Backgrounds a text Quick Moment can use.
    static let storyBackgrounds: [[UIColor]] = [
        brandGradient,
        nightGradient,
        [UIColor(red: 0.36, green: 0.27, blue: 0.93, alpha: 1), UIColor(red: 0.85, green: 0.33, blue: 0.84, alpha: 1)],
        [UIColor(red: 0.07, green: 0.55, blue: 0.62, alpha: 1), UIColor(red: 0.29, green: 0.80, blue: 0.56, alpha: 1)],
        [UIColor(red: 0.98, green: 0.45, blue: 0.20, alpha: 1), UIColor(red: 0.99, green: 0.74, blue: 0.27, alpha: 1)]
    ]

    static func storyBackground(_ index: Int) -> [UIColor] {
        storyBackgrounds[abs(index) % storyBackgrounds.count]
    }
}

enum MomentsActionError: Error {
    case network
    case serverBusy
    /// Super Vibe needs a membership or coins under the existing business rules.
    case membershipRequired
    /// Free user used today's likes.
    case likeLimitReached
    /// Free Super Like used and wallet is below `superLikes.costInCoins`.
    case insufficientCoins
}

// MARK: - Interest catalog

/// Interest names come from the bundled attribute list (alias `interest`); unknown ids are dropped.
enum MomentsInterestCatalog {

    private static let emojiByTitle: [String: String] = [
        "cooking": "🍳", "reading": "📚", "fitness": "💪", "lyrics music": "🎵", "pets": "🐾",
        "party": "🎉", "shopping": "🛍️", "sports": "⚽", "cinema": "🎬", "television": "📺",
        "gaming": "🎮", "travelling": "✈️", "photography": "📷", "extreme": "🪂", "yoga": "🧘",
        "writing": "✍️", "dance": "💃", "planting": "🌱", "drawing": "🎨", "handcraft": "🧶",
        "art": "🎨", "drinks": "🍹", "exercise": "🏋️", "karaoke": "🎤", "music": "🎵",
        "running": "🏃", "swimming": "🏊", "tennis": "🎾", "hiking": "🥾", "coffee": "☕",
        "food": "🍕", "foodie": "🍜", "travel": "✈️", "movies": "🎬", "books": "📚",
        "fashion": "👗", "wine": "🍷", "cycling": "🚴", "football": "⚽", "cricket": "🏏",
        "singing": "🎤", "beach": "🏖️", "meditation": "🧘", "anime": "🍥", "technology": "💻"
    ]

    private static let conversationStarters: [String: String] = [
        "cooking": "What's the one dish you could cook to impress anyone?",
        "reading": "What's a book you'd recommend to everyone?",
        "fitness": "What does your favourite workout look like?",
        "lyrics music": "What was the best concert you've ever attended?",
        "pets": "Tell me about the pet who runs your life.",
        "party": "What makes a night out unforgettable for you?",
        "shopping": "What's the best thing you've found on a shopping spree?",
        "sports": "Which team or player do you never miss?",
        "cinema": "What's a movie you could watch again and again?",
        "television": "Which show are you binge-watching right now?",
        "gaming": "What game have you sunk way too many hours into?",
        "travelling": "What's the best trip you've ever taken?",
        "photography": "What's your favourite thing to photograph?",
        "extreme": "What's the most adventurous thing you've ever done?",
        "yoga": "How did you get into yoga?",
        "writing": "What do you love writing about?",
        "dance": "What song gets you on the dance floor instantly?",
        "planting": "Which plant are you proudest of keeping alive?",
        "drawing": "What do you love to draw the most?",
        "handcraft": "What's the last thing you made by hand?"
    ]

    static let all: [Int: MomentsInterest] = {
        guard let url = Bundle.main.url(forResource: "Attributes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let model = try? JSONDecoder().decode(AttributesModel.self, from: data),
              let options = model.data?.first(where: { $0.alias == "interest" })?.aOptions else { return [:] }
        var interests: [Int: MomentsInterest] = [:]
        for option in options {
            guard let id = option.id else { continue }
            let title = (option.title ?? "").trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            interests[id] = MomentsInterest(id: id, title: title, emoji: emojiByTitle[title.lowercased()] ?? "✨")
        }
        return interests
    }()

    static func interests(for ids: [Int]) -> [MomentsInterest] {
        var seen = Set<Int>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return all[id]
        }
    }

    /// Interest from the API by name: the catalog entry when the title is known, otherwise a new one with a stable id.
    static func interest(named name: String, emoji: String? = nil) -> MomentsInterest? {
        let title = name.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        let key = title.lowercased()
        if let known = all.values.first(where: { $0.title.lowercased() == key }) {
            return known
        }
        let icon = (emoji?.isEmpty == false ? emoji : nil) ?? emojiByTitle[key] ?? "✨"
        return MomentsInterest(id: key.stableID, title: title, emoji: icon)
    }

    static func conversationStarter(for interest: MomentsInterest) -> String? {
        conversationStarters[interest.title.lowercased()]
    }

    private static let symbolByTitle: [String: String] = [
        "cooking": "fork.knife", "reading": "book.fill", "fitness": "dumbbell.fill", "lyrics music": "music.note",
        "pets": "pawprint.fill", "party": "party.popper.fill", "shopping": "bag.fill", "sports": "sportscourt.fill",
        "cinema": "film.fill", "television": "tv.fill", "gaming": "gamecontroller.fill", "travelling": "airplane",
        "photography": "camera.fill", "extreme": "figure.climbing", "yoga": "figure.yoga", "writing": "pencil.line",
        "dance": "figure.dance", "planting": "leaf.fill", "drawing": "paintbrush.pointed.fill", "handcraft": "scissors"
    ]

    private static let palette: [UIColor] = [
        UIColor(red: 0.93, green: 0.27, blue: 0.47, alpha: 1),
        UIColor(red: 0.25, green: 0.52, blue: 0.96, alpha: 1),
        UIColor(red: 0.98, green: 0.55, blue: 0.16, alpha: 1),
        UIColor(red: 0.16, green: 0.70, blue: 0.48, alpha: 1),
        UIColor(red: 0.58, green: 0.36, blue: 0.93, alpha: 1),
        UIColor(red: 0.90, green: 0.22, blue: 0.22, alpha: 1)
    ]

    static func symbol(for interest: MomentsInterest) -> String {
        symbolByTitle[interest.title.lowercased()] ?? "sparkles"
    }

    static func color(for interest: MomentsInterest) -> UIColor {
        palette[abs(interest.id) % palette.count]
    }
}
