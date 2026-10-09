//
//  DiscoverResponse.swift
//  FlirttimeNew
//
//  Response models for the Discover recommendations endpoint.
//

import Foundation

struct DiscoverResponse: Decodable {
    let status: Bool?
    let message: String?
    let data: [DiscoverUser]?
}

struct DiscoverUser: Decodable {
    let userInfo: UserDetailInfo?
    let distance: Double?
    let datingIntent: String?
    let voiceIntro: DiscoverVoiceIntro?
    let moments: [DiscoverMoment]?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case distance
        case datingIntent = "dating_intent"
        case voiceIntro = "voice_intro"
        case moments
    }
}

struct DiscoverVoiceIntro: Decodable {
    let transcript: String?
    let duration: Double?
    let audioURL: String?

    enum CodingKeys: String, CodingKey {
        case transcript, duration
        case audioURL = "audio_url"
    }
}

struct DiscoverMoment: Decodable {
    let id: Int?
    let image: String?
    let type: String?
    let caption: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, image, type, caption
        case createdAt = "created_at"
    }
}
