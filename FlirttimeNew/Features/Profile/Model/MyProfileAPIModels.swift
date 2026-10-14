//
//  MyProfileAPIModels.swift
//  FlirttimeNew
//

import Foundation

/// The `data` of GET `users/profile`.
struct MyProfileData: Codable {
    let profile: MyProfileInfo?
    let interests: [MyProfileInterest]
    let voiceIntro: MyProfileVoiceIntro?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        profile = c.first(MyProfileInfo.self, "profile")
        interests = c.first([MyProfileInterest].self, "interests") ?? []
        voiceIntro = c.first(MyProfileVoiceIntro.self, "voiceIntro")
    }

    /// Interests in the user's chosen order.
    var vibeInterests: [MomentsInterest] {
        interests.sorted { ($0.displayOrder ?? .max) < ($1.displayOrder ?? .max) }.compactMap(\.vibeInterest)
    }
}

struct MyProfileInfo: Codable {
    let id: String?
    let displayName: String?
    let age: Int?
    let bio: String?
    let city: String?
    let state: String?
    let profilePhoto: MyProfilePhoto?
    let coverPhoto: MyProfilePhoto?
    let photos: [MyProfilePhoto]
    let isVerified: Bool?
    let completionPercentage: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        id = c.string("id", "userId")
        displayName = c.string("displayName", "nickName", "name")
        age = c.int("age")
        bio = c.string("bio", "about")
        if let location = c.first(MyProfileLocation.self, "location") {
            city = location.city
            state = location.state
        } else {
            city = c.string("location", "city")
            state = nil
        }
        profilePhoto = c.first(MyProfilePhoto.self, "profilePhoto")
        coverPhoto = c.first(MyProfilePhoto.self, "coverPhoto")
        photos = c.first([MyProfilePhoto].self, "photos") ?? []
        isVerified = c.bool("isVerified", "isFaceVerified")
        completionPercentage = c.int("completionPercentage", "profileCompletion")
    }

    /// "City, State", skipping whichever part is missing.
    var locationText: String {
        [city, state]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Gallery URLs, primary first.
    var photoURLs: [String] {
        photos.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isPrimary != rhs.element.isPrimary { return lhs.element.isPrimary }
                return (lhs.element.displayOrder ?? lhs.offset) < (rhs.element.displayOrder ?? rhs.offset)
            }
            .compactMap { $0.element.bestURL }
    }

    /// The main gallery photo set in Edit Profile; `profilePhoto` can still be the verification selfie.
    var avatarURL: String? { photoURLs.first ?? profilePhoto?.bestURL }
}

private struct MyProfileLocation: Codable {
    let city: String?
    let state: String?
}

/// A photo as `{ "url", "thumbnailUrl" }` or a plain URL string.
struct MyProfilePhoto: Codable {
    let url: String?
    let thumbnailUrl: String?
    let isPrimary: Bool
    let displayOrder: Int?

    init(from decoder: Decoder) throws {
        if let url = try? decoder.singleValueContainer().decode(String.self) {
            self.url = url
            thumbnailUrl = nil
            isPrimary = false
            displayOrder = nil
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        url = c.string("url", "imageUrl", "mediaUrl")
        thumbnailUrl = c.string("thumbnailUrl")
        isPrimary = c.bool("isPrimary") ?? false
        displayOrder = c.int("displayOrder")
    }

    /// Full-size image, or the thumbnail when that's all there is.
    var bestURL: String? { url ?? thumbnailUrl }
}

struct MyProfileInterest: Codable {
    let name: String?
    let icon: String?
    let displayOrder: Int?

    init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            self.name = name
            icon = nil
            displayOrder = nil
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        name = c.string("name", "title")
        icon = c.string("icon", "emoji")
        displayOrder = c.int("displayOrder")
    }

    var vibeInterest: MomentsInterest? {
        name.flatMap { MomentsInterestCatalog.interest(named: $0, emoji: icon) }
    }
}

struct MyProfileVoiceIntro: Codable {
    let playbackUrl: String?
    let duration: Double?
    /// "ready" once the audio is processed.
    let status: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        playbackUrl = c.string("playbackUrl", "audioUrl", "url")
        duration = c.first(Double.self, "duration")
        status = c.string("status")
    }

    /// `nil` until the audio is ready to play.
    var userVoiceIntro: UserVoiceIntro? {
        guard let url = playbackUrl, !url.isEmpty else { return nil }
        if let status, status.lowercased() != "ready" { return nil }
        return UserVoiceIntro(audioURL: url, duration: duration, updatedAt: nil)
    }
}
