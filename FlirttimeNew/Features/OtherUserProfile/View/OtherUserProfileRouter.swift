//
//  OtherUserProfileRouter.swift
//  FlirttimeNew
//
//  One place to open another user's profile from any list (e.g. Moments).
//

import UIKit

enum OtherUserProfileRouter {

    /// What the tapping screen already knows about the user.
    struct Seed {
        let userID: String?
        let name: String?
        var avatar: String? = nil
        var about: String? = nil
        var location: String? = nil
        var age: Int? = nil
        var isVerified = false
        var isOnline = false
        /// Already-loaded photo from the tapping cell, shown immediately so the profile does not flash a placeholder.
        var previewImage: UIImage? = nil
    }

    /// The seed is shown straight away; backend (UUID) users then load the full profile from `users/:userId/profile`.
    static func open(_ seed: Seed, from presenter: UIViewController) {
        guard let info = userInfo(for: seed) else { return }
        let profileVC: OtherUserProfileViewController = OtherUserProfileViewController.instantiateFromStoryboard()
        profileVC.userDetailInfo = info
        profileVC.remoteUserID = remoteID(for: seed.userID)
        profileVC.previewImage = seed.previewImage
        presenter.navigationController?.pushViewController(profileVC, animated: true)
    }

    /// Mock people have numeric ids; real users have UUIDs.
    static func remoteID(for userID: String?) -> String? {
        guard let id = userID?.trimmingCharacters(in: .whitespaces), !id.isEmpty, Int(id) == nil else { return nil }
        return id
    }

    private static func userInfo(for seed: Seed) -> UserDetailInfo? {
        let numericID = seed.userID.flatMap { Int($0) }
        let payload: [String: Any]
        if let numericID, let person = MockPeople.person(id: numericID) {
            payload = MockPeople.userInfoJSON(person)
        } else {
            payload = basicPayload(for: seed, numericID: numericID)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return try? JSONDecoder().decode(UserDetailInfo.self, from: data)
    }

    private static func basicPayload(for seed: Seed, numericID: Int?) -> [String: Any] {
        var payload: [String: Any] = [
            "is_active": seed.isVerified,
            "is_online": seed.isOnline
        ]
        if let numericID {
            payload["user_id"] = numericID
            payload["id"] = numericID
        }
        if let name = seed.name, !name.isEmpty {
            payload["display_name"] = name
            payload["fullname"] = name
        }
        if let avatar = seed.avatar, !avatar.isEmpty { payload["avatar"] = avatar }
        if let about = seed.about, !about.isEmpty { payload["about_me"] = about }
        if let location = seed.location, !location.isEmpty { payload["location"] = location }
        if let age = seed.age {
            let year = Calendar.current.component(.year, from: Date()) - age
            payload["dob"] = "\(year)-01-01"
        }
        return payload
    }
}
