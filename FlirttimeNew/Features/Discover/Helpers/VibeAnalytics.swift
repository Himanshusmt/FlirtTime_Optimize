//
//  VibeAnalytics.swift
//  FlirttimeNew
//

import Foundation

// TODO: forward events to the analytics provider once one is integrated.
enum VibeAnalytics {

    enum Event: String {
        case discoverProfileImpression = "discover_profile_impression"
        case vibeCardOpened = "vibe_card_opened"
        case vibeVoicePlayed = "vibe_voice_played"
        case vibeMomentOpened = "vibe_moment_opened"
        case vibeMomentReacted = "vibe_moment_reacted"
        case vibeMomentReplied = "vibe_moment_replied"
        case discoverFiltersApplied = "discover_filters_applied"
        case whyVibeOpened = "why_vibe_opened"
        case vibeChapterViewed = "vibe_chapter_viewed"
        case vibeReactionSent = "vibe_reaction_sent"
        case gestureStarted = "gesture_started"
        case gestureCancelled = "gesture_cancelled"
        case gestureSuperVibe = "gesture_super_vibe"
        case gestureInterested = "gesture_interested"
        case gestureNotMyVibe = "gesture_not_my_vibe"
        case gestureNope = "gesture_nope"
        case connectionRequestSent = "connection_request_sent"
        case connectionCreated = "connection_created"
        case conversationStarted = "conversation_started"
    }

    static func track(_ event: Event, profileID: Int? = nil, properties: [String: Any] = [:]) {
        var payload = properties
        if let profileID {
            payload["profile_id"] = profileID
        }
        #if DEBUG
        print("[Analytics]", event.rawValue, payload)
        #endif
    }
}
