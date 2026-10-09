//
//  FilterModel+Vibe.swift
//  FlirttimeNew
//
//  Typed access to the saved Discover/Explore filters.
//

import Foundation

extension FilterModel {

    enum ShowMe: String, CaseIterable {
        case women = "2"
        case men = "1"
        case nonBinary = "3"
        case everyone = "0"

        var title: String {
            switch self {
            case .women: return "Women"
            case .men: return "Men"
            case .nonBinary: return "Non-binary"
            case .everyone: return "Everyone"
            }
        }

        var emoji: String {
            switch self {
            case .women: return "👩"
            case .men: return "👨"
            case .nonBinary: return "🧑"
            case .everyone: return "🌈"
            }
        }
    }

    static let ageBounds = 18...70
    /// The top of the distance slider means "Anywhere".
    static let distanceBounds = 1...150
    static let datingIntents: [(title: String, emoji: String)] = [
        ("Long-term", "💍"), ("Something casual", "🥂"), ("Not sure yet", "🤔")
    ]

    static var standard: FilterModel {
        FilterModel(gender: ShowMe.everyone.rawValue,
                    minAge: "\(ageBounds.lowerBound)", maxAge: "\(ageBounds.upperBound)",
                    distance: "\(distanceBounds.upperBound)",
                    isVerified: "0", isOnline: "0", interests: [], intents: [])
    }

    static var saved: FilterModel { UserDataManager.shared.filterDataModel ?? .standard }

    var showMe: ShowMe {
        get { gender.flatMap(ShowMe.init(rawValue:)) ?? .everyone }
        set { gender = newValue.rawValue }
    }

    var ageRange: ClosedRange<Int> {
        get {
            let bounds = Self.ageBounds
            let low = min(max(Int(minAge ?? "") ?? bounds.lowerBound, bounds.lowerBound), bounds.upperBound)
            let high = min(max(Int(maxAge ?? "") ?? bounds.upperBound, low), bounds.upperBound)
            return low...high
        }
        set {
            minAge = "\(newValue.lowerBound)"
            maxAge = "\(newValue.upperBound)"
        }
    }

    /// `nil` = anywhere.
    var maxDistanceKm: Int? {
        get {
            guard let value = Int(distance ?? ""), value < Self.distanceBounds.upperBound else { return nil }
            return max(value, Self.distanceBounds.lowerBound)
        }
        set { distance = "\(newValue ?? Self.distanceBounds.upperBound)" }
    }

    var verifiedOnly: Bool {
        get { isVerified == "1" }
        set { isVerified = newValue ? "1" : "0" }
    }

    var onlineOnly: Bool {
        get { isOnline == "1" }
        set { isOnline = newValue ? "1" : "0" }
    }

    var ageText: String {
        let range = ageRange
        let upper = range.upperBound == Self.ageBounds.upperBound ? "\(range.upperBound)+" : "\(range.upperBound)"
        return "\(range.lowerBound) – \(upper)"
    }

    var distanceText: String {
        maxDistanceKm.map { "Up to \($0) km" } ?? "Anywhere"
    }

    var activeCount: Int {
        [showMe != .everyone,
         ageRange != Self.ageBounds,
         maxDistanceKm != nil,
         !(intents ?? []).isEmpty,
         !(interests ?? []).isEmpty,
         verifiedOnly,
         onlineOnly].filter { $0 }.count
    }

    /// Hidden fields (age, distance, online status) never exclude anyone.
    func matches(_ profile: VibeProfile) -> Bool {
        if showMe != .everyone, let gender = profile.gender, "\(gender)" != showMe.rawValue { return false }
        if let age = profile.age {
            let range = ageRange
            if age < range.lowerBound { return false }
            if range.upperBound < Self.ageBounds.upperBound && age > range.upperBound { return false }
        }
        if let limit = maxDistanceKm, let distance = profile.distanceKm, distance > Double(limit) { return false }
        if verifiedOnly && !profile.isVerified { return false }
        if onlineOnly && profile.isOnline == false { return false }
        if let intents, !intents.isEmpty {
            guard let intent = profile.datingIntent, intents.contains(intent) else { return false }
        }
        if let interests, !interests.isEmpty {
            guard profile.interests.contains(where: { interests.contains($0.id) }) else { return false }
        }
        return true
    }
}
