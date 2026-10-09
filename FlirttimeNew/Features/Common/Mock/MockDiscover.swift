//
//  MockDiscover.swift
//  FlirttimeNew
//
//  Local stand-in for the Discover recommendations and interaction endpoints. Responses use the
//  server JSON shape and are decoded with the real models.
//  Launch with `-VibeSimulateFailures` to make every other action fail (network-failure testing).
//

import Foundation

final class MockDiscover {

    static let shared = MockDiscover()

    private struct Extras {
        let distanceKm: Double?
        let datingIntent: String?
        let voiceTranscript: String?
    }

    private let extras: [Int: Extras] = [
        101: Extras(distanceKm: 3, datingIntent: "Long-term", voiceTranscript: "My perfect Sunday is coffee, music and a long walk with my playlist on."),
        102: Extras(distanceKm: 12, datingIntent: "Something casual", voiceTranscript: nil),
        103: Extras(distanceKm: 0.6, datingIntent: "Long-term", voiceTranscript: "Give me a mountain trail on Saturday and a chai on Sunday and I'm happy."),
        104: Extras(distanceKm: 7, datingIntent: nil, voiceTranscript: "I'll cook for you if you bring the playlist."),
        105: Extras(distanceKm: 25, datingIntent: "Not sure yet", voiceTranscript: "Sunsets, street food and a spontaneous road trip. You in?"),
        106: Extras(distanceKm: nil, datingIntent: "Long-term", voiceTranscript: nil),
        107: Extras(distanceKm: 4, datingIntent: "Something casual", voiceTranscript: "Fair warning, my dog has to approve of you first."),
        108: Extras(distanceKm: 18, datingIntent: nil, voiceTranscript: nil)
    ]

    private static let momentCaptions = [
        "Best sunsets are always better with good company 🌅",
        "Coffee first, everything else later ☕",
        "Weekend mode: on 🎶",
        "Found my happy place 🌿",
        "Chasing light and good vibes ✨",
        "Little moments, big smiles 😊"
    ]

    private let seenKey = "mock_discover_seen_ids"
    private let blockedKey = "mock_discover_blocked_ids"
    private var actionCount = 0

    private var simulatesFailures: Bool {
        ProcessInfo.processInfo.arguments.contains("-VibeSimulateFailures")
    }

    private init() {}

    // MARK: - Endpoints

    func recommendationsJSON() -> [String: Any] {
        let hidden = seenIDs.union(blockedIDs)
        let users: [[String: Any]] = MockPeople.all
            .filter { !hidden.contains($0.id) }
            .map(userJSON)
        return ["status": true, "message": "", "img_base_url": ApiName.imgBaseURL, "data": users]
    }

    /// `nil` simulates a network failure.
    func actionJSON(interactionType: String, userID: Int) -> [String: Any]? {
        actionCount += 1
        if simulatesFailures && actionCount % 2 == 0 {
            return nil
        }
        markSeen(userID)
        let sendsInterest = interactionType == Constants.ActionType.like || interactionType == Constants.ActionType.favorite
        let isMatch = sendsInterest && MockPeople.likesYouIDs.contains(userID)
        let person = MockPeople.person(id: userID)
        var data: [String: Any] = ["membership_required": false, "coin_required": false, "is_match": isMatch]
        if isMatch, let person {
            data["match_user_id"] = person.id
            data["match_display_name"] = person.displayName
            data["match_image"] = person.photos.first ?? ""
        }
        return ["status": true, "message": "", "data": data]
    }

    func block(userID: Int) {
        var ids = blockedIDs
        ids.insert(userID)
        UserDefaults.standard.set(Array(ids), forKey: blockedKey)
    }

    func markSeen(_ userID: Int) {
        var ids = seenIDs
        ids.insert(userID)
        UserDefaults.standard.set(Array(ids), forKey: seenKey)
    }

    func unmarkSeen(_ userID: Int) {
        var ids = seenIDs
        ids.remove(userID)
        UserDefaults.standard.set(Array(ids), forKey: seenKey)
    }

    /// "Explore Again": previously swiped profiles become available again (blocked ones stay hidden).
    func resetSeen() {
        UserDefaults.standard.removeObject(forKey: seenKey)
    }

    func reset() {
        resetSeen()
        UserDefaults.standard.removeObject(forKey: blockedKey)
    }

    // MARK: - Helpers

    private var seenIDs: Set<Int> {
        Set(UserDefaults.standard.array(forKey: seenKey) as? [Int] ?? [])
    }

    private var blockedIDs: Set<Int> {
        Set(UserDefaults.standard.array(forKey: blockedKey) as? [Int] ?? [])
    }

    private func userJSON(_ person: MockPerson) -> [String: Any] {
        let extra = extras[person.id]
        var json: [String: Any] = [
            "user_info": MockPeople.userInfoJSON(person),
            "moments": person.moments.enumerated().map { index, photo in
                let caption = MockDiscover.momentCaptions[(person.id + index) % MockDiscover.momentCaptions.count]
                let postedAt = Date().addingTimeInterval(-Double((index + 1) * (person.id % 7 + 1)) * 3600)
                return ["id": person.id * 100 + index, "image": photo, "type": "image",
                        "caption": caption, "created_at": ISO8601DateFormatter().string(from: postedAt)]
            }
        ]
        if let distance = extra?.distanceKm {
            json["distance"] = distance
        }
        if let intent = extra?.datingIntent {
            json["dating_intent"] = intent
        }
        if let transcript = extra?.voiceTranscript {
            let words = transcript.split(separator: " ").count
            json["voice_intro"] = ["transcript": transcript, "duration": max(4, Double(words) / 2.5)]
        }
        return json
    }
}
