//
//  VibeProfile.swift
//  FlirttimeNew
//
//  Discover ("Vibe Discovery") models. Everything shown on a Vibe Card comes from real profile
//  data; reasons and shared interests are derived, never invented.
//

import UIKit

// MARK: - Actions

/// UI abstraction over the existing interaction APIs (Super Like, Like, Dislike, Nope).
enum VibeAction: CaseIterable {
    case superVibe
    case interested
    case notMyVibe
    case nope

    var overlayTitle: String {
        switch self {
        case .superVibe: return "SUPER VIBE"
        case .interested: return "INTERESTED"
        case .notMyVibe: return "NOT MY VIBE"
        case .nope: return "NOPE"
        }
    }

    var displayName: String {
        switch self {
        case .superVibe: return "Super Vibe"
        case .interested: return "Interested"
        case .notMyVibe: return "Not My Vibe"
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
        case .superVibe: return UIColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1)
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

    var sendsConnection: Bool {
        self == .superVibe || self == .interested
    }

    var analyticsEvent: VibeAnalytics.Event {
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
    case loveTheirVibe = "Love their vibe"
    case sameInterests = "Same interests"
    case likedMoment = "Liked their Moment"
    case greatEnergy = "Great energy"
    case wantToChat = "Want to chat"
}

// MARK: - Profile

struct VibeInterest: Hashable {
    let id: Int
    let title: String
    let emoji: String

    var chipTitle: String { "\(emoji) \(title)" }
}

struct VibeVoiceIntro {
    let transcript: String
    let duration: TimeInterval
    /// Remote audio file. `nil` for mock profiles, which read the transcript aloud instead.
    let audioURL: URL?

    var durationText: String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct VibeMoment: Hashable {
    let id: Int
    let imagePath: String
    let isVideo: Bool
    var caption: String?
    var postedAt: Date?

    /// "2h ago"
    var postedAgoText: String? {
        guard let postedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: postedAt, relativeTo: Date())
    }
}

struct VibeProfile: Equatable {
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
    let interests: [VibeInterest]
    let sharedInterests: [VibeInterest]
    let reasons: [String]
    let voiceIntro: VibeVoiceIntro?
    let moments: [VibeMoment]
    /// Overlap of real interests (plus same city); `nil` when nothing is shared, so no score is shown.
    let vibeScore: Int?

    static func == (lhs: VibeProfile, rhs: VibeProfile) -> Bool {
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

    var sharedVibesText: String? {
        switch sharedInterests.count {
        case 0: return nil
        case 1: return "1 Shared Vibe"
        default: return "\(sharedInterests.count) Shared Vibes"
        }
    }

    /// Icon for a "Why This Vibe?" reason row.
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
        if let datingIntent { parts.append("Looking for \(datingIntent)") }
        if !interests.isEmpty { parts.append("Interests: " + interests.map(\.title).joined(separator: ", ")) }
        return parts.joined(separator: ". ")
    }
}

/// A reaction to one specific part of a profile; it travels with the interest as its context.
struct VibeReaction: Equatable {

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
        case .whyVibe: return "Loved your vibe"
        case .ownWords: return "Liked your words"
        case .voice: return "Loved your voice intro"
        case .moments: return "Liked your Moments"
        }
    }

    /// "Maya's voice intro"
    func subject(for name: String) -> String {
        switch target {
        case .photo: return "\(name)'s photo"
        case .whyVibe: return "your shared vibe with \(name)"
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
struct VibeActionOutcome {
    let action: VibeAction
    let profile: VibeProfile
    let isMatch: Bool
    let reaction: VibeReaction?
}

// MARK: - Theme

enum VibeTheme {
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
}

enum VibeActionError: Error {
    case network
    /// Super Vibe needs a membership or coins under the existing business rules.
    case membershipRequired
}

// MARK: - Interest catalog

/// Interest names come from the bundled attribute list (alias `interest`); unknown ids are dropped.
enum VibeInterestCatalog {

    private static let emojiByTitle: [String: String] = [
        "cooking": "🍳", "reading": "📚", "fitness": "💪", "lyrics music": "🎵", "pets": "🐾",
        "party": "🎉", "shopping": "🛍️", "sports": "⚽", "cinema": "🎬", "television": "📺",
        "gaming": "🎮", "travelling": "✈️", "photography": "📷", "extreme": "🪂", "yoga": "🧘",
        "writing": "✍️", "dance": "💃", "planting": "🌱", "drawing": "🎨", "handcraft": "🧶"
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

    static let all: [Int: VibeInterest] = {
        guard let url = Bundle.main.url(forResource: "Attributes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let model = try? JSONDecoder().decode(AttributesModel.self, from: data),
              let options = model.data?.first(where: { $0.alias == "interest" })?.aOptions else { return [:] }
        var interests: [Int: VibeInterest] = [:]
        for option in options {
            guard let id = option.id else { continue }
            let title = (option.title ?? "").trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            interests[id] = VibeInterest(id: id, title: title, emoji: emojiByTitle[title.lowercased()] ?? "✨")
        }
        return interests
    }()

    static func interests(for ids: [Int]) -> [VibeInterest] {
        var seen = Set<Int>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return all[id]
        }
    }

    static func conversationStarter(for interest: VibeInterest) -> String? {
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

    static func symbol(for interest: VibeInterest) -> String {
        symbolByTitle[interest.title.lowercased()] ?? "sparkles"
    }

    static func color(for interest: VibeInterest) -> UIColor {
        palette[abs(interest.id) % palette.count]
    }
}
