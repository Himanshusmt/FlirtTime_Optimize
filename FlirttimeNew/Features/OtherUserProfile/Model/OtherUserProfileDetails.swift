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

    var nameAndAge: String {
        age.map { "\(name), \($0)" } ?? name
    }

    /// "More about me" rows, in the order of `Attributes.json`; unanswered ones are skipped.
    func basicInfo(from attributes: [AttributesData]) -> [OtherUserBasicInfo] {
        attributes.compactMap { attribute in
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
}
