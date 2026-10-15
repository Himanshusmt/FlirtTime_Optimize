//
//  OtherUserProfileDetails.swift
//  FlirttimeNew
//
//  Everything the other-user profile screen shows, built from whichever model the
//  presenting screen has (Explore / Chat `UserDetailInfo`, Matches `MatchedUser`).
//

import Foundation

struct OtherUserProfileDetails {
    let userID: Int
    let name: String
    let age: Int?
    let location: String?
    let about: String?
    let avatar: String?
    let banner: String?
    let photos: [Images]
    let interestIDs: [Int]
    let isVerified: Bool
    let isOnline: Bool
    /// Attribute alias (`height`, `smoking`, ...) → selected option id.
    let attributeValues: [String: Int]
    /// Backend UUID, for profiles loaded from `users/:userId/profile`.
    var remoteUserID: String? = nil
    /// Interests by name from the API; when empty, `interestIDs` are used.
    var interests: [MomentsInterest] = []
    /// Interests this user has in common with the signed-in user; `nil` when the API didn't send them.
    var sharedInterests: [MomentsInterest]? = nil
    /// "More about me" answers from the API as display text, keyed by attribute alias.
    var aboutAnswers: [OtherUserAboutItem] = []

    var nameAndAge: String {
        age.map { "\(name), \($0)" } ?? name
    }

    /// "More about me" rows, in the order of `Attributes.json`; unanswered ones are skipped.
    func basicInfo(from attributes: [AttributesData]) -> [OtherUserBasicInfo] {
        if !aboutAnswers.isEmpty {
            return Self.basicInfo(answers: aboutAnswers, attributes: attributes)
        }
        return attributes.compactMap { attribute in
            guard let alias = attribute.alias,
                  let optionID = attributeValues[alias],
                  let option = attribute.aOptions?.first(where: { $0.id == optionID }),
                  let value = option.title?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return OtherUserBasicInfo(title: attribute.title ?? alias.firstLetterCapitalized, value: value, iconPath: attribute.photo)
        }
    }

    /// Primary photo first, then gallery photos; falls back to the avatar.
    private static func orderedPhotos(_ images: [Images], avatar: String?) -> [Images] {
        let usable = images.filter { !($0.image ?? "").isEmpty }
        let primary = usable.filter { $0.is_primary == true }
        let gallery = usable.filter { $0.is_primary != true && $0.type == "gallery" }
        let photos = primary + gallery
        if photos.isEmpty, let avatar, !avatar.isEmpty {
            return [Images(image: avatar, type: "gallery", is_primary: true)]
        }
        return photos
    }

    /// Known aliases take their title and icon from `Attributes.json` and keep its order; unknown keys follow, A to Z.
    private static func basicInfo(answers: [OtherUserAboutItem], attributes: [AttributesData]) -> [OtherUserBasicInfo] {
        let rows = answers.map { answer -> (rank: Int, info: OtherUserBasicInfo) in
            let key = answer.key.lowercased()
            let index = attributes.firstIndex { $0.alias?.lowercased() == key || $0.title?.lowercased() == key }
            let attribute = index.map { attributes[$0] }
            let info = OtherUserBasicInfo(title: attribute?.title ?? readableTitle(answer.key),
                                          value: answer.value,
                                          iconPath: attribute?.photo)
            return (index ?? Int.max, info)
        }
        return rows.sorted { ($0.rank, $0.info.title) < ($1.rank, $1.info.title) }.map(\.info)
    }

    /// "lookingFor" / "looking_for" → "Looking for"
    private static func readableTitle(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.lowercased().firstLetterCapitalized
    }
}

struct OtherUserBasicInfo {
    let title: String
    let value: String
    let iconPath: String?
}

extension OtherUserProfileDetails {

    init(info: UserDetailInfo) {
        let attributes: [(String, Int?)] = [
            ("sexuality", info.sexuality), ("height", info.height), ("weight", info.weight),
            ("smoking", info.smoking), ("drinking", info.drinking), ("eyecolor", info.eyeColour),
            ("haircolor", info.hairColour), ("living", info.living), ("religion", info.religion),
            ("education", info.education), ("relationship", info.relationship), ("children", info.children)
        ]
        self.init(userID: info.userID ?? info.id ?? 0,
                  name: (info.displayName ?? info.fullname ?? "").firstLetterCapitalized,
                  age: info.ageShow == false ? nil : DiscoverViewModel.age(from: info.dob),
                  location: info.locationShow == false ? nil : info.location,
                  about: info.aboutMe,
                  avatar: info.avatar,
                  banner: info.banner,
                  photos: Self.orderedPhotos(info.images ?? [], avatar: info.avatar),
                  interestIDs: info.interests ?? [],
                  isVerified: info.isActive == true,
                  isOnline: info.isOnline == true && info.onlineShow != false,
                  attributeValues: attributes.reduce(into: [:]) { $0[$1.0] = $1.1 })
    }

    init(match: MatchedUser) {
        let attributes: [(String, Int?)] = [
            ("sexuality", match.sexuality), ("height", match.height), ("weight", match.weight),
            ("smoking", match.smoking), ("drinking", match.drinking), ("eyecolor", match.eyeColour),
            ("haircolor", match.hairColour), ("living", match.living), ("religion", match.religion),
            ("education", match.education), ("relationship", match.relationship), ("children", match.children)
        ]
        self.init(userID: match.userID ?? match.id ?? 0,
                  name: (match.displayName ?? match.fullname ?? "").firstLetterCapitalized,
                  age: match.ageShow == false ? nil : DiscoverViewModel.age(from: match.dob),
                  location: match.locationShow == false ? nil : match.location,
                  about: match.aboutMe,
                  avatar: match.avatar,
                  banner: match.banner,
                  photos: Self.orderedPhotos(match.images, avatar: match.avatar),
                  interestIDs: match.interests,
                  isVerified: match.isActive == true,
                  isOnline: match.isOnline == true && match.onlineShow != false,
                  attributeValues: attributes.reduce(into: [:]) { $0[$1.0] = $1.1 })
    }

    /// Full profile from `users/:userId/profile`; anything the API leaves empty keeps `fallback`'s value.
    init(profile: OtherUserProfile, remoteUserID: String, fallback: OtherUserProfileDetails?) {
        let id = profile.userId ?? remoteUserID
        let apiName = DiscoverViewModel.displayName(username: profile.username, name: profile.name ?? profile.fullName)
        let avatar = profile.profilePhoto ?? fallback?.avatar
        let city = profile.city?.trimmingCharacters(in: .whitespaces) ?? ""
        let distance = profile.distance ?? profile.distanceKm.map { String(format: "%.1f km away", $0) }
        let location = [city.isEmpty ? fallback?.location : city, distance]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let interests = (profile.interests ?? []).compactMap { MomentsInterestCatalog.interest(named: $0.name, emoji: $0.emoji) }
        let apiPhotos = (profile.photos ?? []).map { Images(image: $0.url, type: "gallery", is_primary: $0.isPrimary) }
        let photos: [Images]
        if !apiPhotos.isEmpty {
            photos = apiPhotos
        } else {
            photos = profile.profilePhoto == nil ? (fallback?.photos ?? []) : Self.orderedPhotos([], avatar: avatar)
        }

        self.init(userID: id.stableID,
                  name: apiName.isEmpty ? (fallback?.name ?? "") : apiName,
                  age: profile.age ?? fallback?.age,
                  location: location.isEmpty ? nil : location,
                  about: profile.bio ?? fallback?.about,
                  avatar: avatar,
                  banner: profile.coverPhoto ?? fallback?.banner,
                  photos: photos,
                  interestIDs: interests.isEmpty ? (fallback?.interestIDs ?? []) : [],
                  isVerified: profile.isVerified ?? fallback?.isVerified ?? false,
                  isOnline: profile.isOnline ?? fallback?.isOnline ?? false,
                  attributeValues: fallback?.attributeValues ?? [:],
                  remoteUserID: id,
                  interests: interests.isEmpty ? (fallback?.interests ?? []) : interests,
                  sharedInterests: profile.sharedInterests.map { tags in
                      tags.compactMap { MomentsInterestCatalog.interest(named: $0.name, emoji: $0.emoji) }
                  } ?? fallback?.sharedInterests,
                  aboutAnswers: profile.moreAboutMe ?? fallback?.aboutAnswers ?? [])
    }
}
