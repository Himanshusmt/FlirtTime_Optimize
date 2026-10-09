//
//  MockDataStore.swift
//  FlirttimeNew
//
//  Local stand-in for the user-profile endpoints. Keeps the signed-in user's profile as the
//  same JSON the server returns (persisted to disk) and decodes it with the real models, so
//  replacing a mock view-model method with its API call needs no UI changes.
//

import UIKit

final class MockDataStore {

    static let shared = MockDataStore()

    /// Simulated network latency for mock responses.
    static let responseDelay: TimeInterval = 0.4

    private let fileURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("mock_current_user.json")

    private var user: [String: Any]

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            user = json
            MockDataStore.migrateLegacyGallery(&user)
        } else {
            user = MockDataStore.defaultUser()
        }
    }

    // MARK: - Reads

    func currentUserResponse() -> UserResponse? {
        let payload: [String: Any] = ["status": true, "message": "User details fetched successfully", "data": userWithDerivedFields()]
        return decode(UserResponse.self, from: payload)
    }

    func myMoments() -> [MomentsDatum] {
        let moments: [[String: Any]] = ["mock-me-moment-0", "mock-me-moment-1", "mock-me-moment-2", "mock-me-moment-3"].enumerated().map { index, image in
            [
                "id": 900 + index,
                "user_id": currentUserID,
                "title": "",
                "body": "",
                "images": [image],
                "like_count": 4 + index,
                "comment_count": index,
                "share_count": 0,
                "status": 1,
                "created_at": "2026-09-1\(index) 10:00:00",
                "updated_at": "2026-09-1\(index) 10:00:00"
            ]
        }
        return decode([MomentsDatum].self, from: moments) ?? []
    }

    var currentUserID: Int {
        user["id"] as? Int ?? 1
    }

    // MARK: - Writes

    /// Applies a "save introduction" payload (same keys the API accepts).
    func updateUser(with params: [String: Any]) {
        var info = userInfo
        for (key, value) in params {
            switch key {
            case "phone", "phone_code", "email":
                user[key] = value
            default:
                info[key] = value
            }
        }
        userInfo = info
        persist()
    }

    func setAvatar(_ image: UIImage) -> String? {
        guard let name = LocalImageStore.shared.save(image) else { return nil }
        var info = userInfo
        info["avatar"] = name
        userInfo = info
        persist()
        return name
    }

    func setBanner(_ image: UIImage) -> String? {
        guard let name = LocalImageStore.shared.save(image) else { return nil }
        var info = userInfo
        info["banner"] = name
        userInfo = info
        persist()
        return name
    }

    /// Adds a gallery photo and returns the server-style `image` payload for it.
    func addGalleryImage(_ image: UIImage) -> [String: Any]? {
        guard let name = LocalImageStore.shared.save(image) else { return nil }
        var images = userImages
        let nextID = (images.compactMap { $0["id"] as? Int }.max() ?? 0) + 1
        let entry: [String: Any] = [
            "id": nextID,
            "user_id": currentUserID,
            "filename": name,
            "filetype": "image",
            "filefor": "gallery",
            "is_primary": images.isEmpty,
            "status": 1,
            "created_at": "2026-10-07 10:00:00",
            "updated_at": "2026-10-07 10:00:00"
        ]
        images.append(entry)
        userImages = images
        persist()
        return entry
    }

    func deleteImage(id: Int) -> Bool {
        var images = userImages
        guard let index = images.firstIndex(where: { $0["id"] as? Int == id }) else { return false }
        let wasPrimary = images[index]["is_primary"] as? Bool ?? false
        images.remove(at: index)
        if wasPrimary, !images.isEmpty {
            images[0]["is_primary"] = true
        }
        userImages = images
        persist()
        return true
    }

    func makePrimary(id: Int) -> Bool {
        var images = userImages
        guard images.contains(where: { $0["id"] as? Int == id }) else { return false }
        for index in images.indices {
            images[index]["is_primary"] = (images[index]["id"] as? Int == id)
        }
        userImages = images
        persist()
        return true
    }

    func reset() {
        user = MockDataStore.defaultUser()
        try? FileManager.default.removeItem(at: fileURL)
        VibeUploadViewModel.shared.cancel()
        LocalImageStore.shared.removeAll()
        MockVibeStore.shared.reset()
        MockDiscover.shared.reset()
        MockStore.shared.reset()
        CoinWallet.shared.refresh()
    }

    // MARK: - Helpers

    func decode<T: Decodable>(_ type: T.Type, from json: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("MockDataStore decode \(type) failed:", error)
            return nil
        }
    }

    private var userInfo: [String: Any] {
        get { user["user_info"] as? [String: Any] ?? [:] }
        set { user["user_info"] = newValue }
    }

    private var userImages: [[String: Any]] {
        get { user["user_images"] as? [[String: Any]] ?? [] }
        set { user["user_images"] = newValue }
    }

    /// Keeps avatar / images / completion in sync with the gallery the way the backend does.
    private func userWithDerivedFields() -> [String: Any] {
        var payload = user
        var info = userInfo
        let gallery = userImages.filter { $0["filefor"] as? String == "gallery" }
        let ordered = gallery.sorted { ($0["is_primary"] as? Bool ?? false) && !($1["is_primary"] as? Bool ?? false) }
        if let primary = ordered.first?["filename"] as? String {
            info["avatar"] = primary
        }
        info["images"] = ordered.map { ["image": $0["filename"] ?? "", "type": "gallery", "is_primary": $0["is_primary"] ?? false] }
        info["display_name"] = info["display_name"] ?? UserDataManager.shared.displayName ?? "You"
        payload["user_info"] = info
        payload["profile_complete"] = profileCompletion(info: info, galleryCount: gallery.count)
        return payload
    }

    private func profileCompletion(info: [String: Any], galleryCount: Int) -> Int {
        let attributeKeys = ["sexuality", "height", "weight", "eye_colour", "hair_colour", "living", "children",
                             "smoking", "drinking", "relationship", "religion", "education"]
        let answered = attributeKeys.filter { info[$0] != nil }.count
        let hasAbout = !((info["about_me"] as? String) ?? "").isEmpty
        let hasInterests = !((info["interests"] as? [Int]) ?? []).isEmpty
        let hasBanner = info["banner"] != nil
        let score = 30
            + answered * 3
            + (hasAbout ? 6 : 0)
            + (hasInterests ? 6 : 0)
            + (hasBanner ? 4 : 0)
            + min(galleryCount, 6) * 3
        return min(score, 100)
    }

    private func persist() {
        guard JSONSerialization.isValidJSONObject(user),
              let data = try? JSONSerialization.data(withJSONObject: user) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let defaultGalleryFiles = ["mock-me-0", "mock-me-1", "mock-me-2"]
    private static let legacyGalleryFiles: Set<String> = ["delete-4", "delete-13", "delete-14"]

    /// Swaps the old low-resolution sample photos in a previously saved user for the HD ones.
    private static func migrateLegacyGallery(_ user: inout [String: Any]) {
        guard var images = user["user_images"] as? [[String: Any]] else { return }
        var changed = false
        for index in images.indices {
            if let file = images[index]["filename"] as? String, legacyGalleryFiles.contains(file), index < defaultGalleryFiles.count {
                images[index]["filename"] = defaultGalleryFiles[index]
                changed = true
            }
        }
        if changed { user["user_images"] = images }
    }

    private static func defaultUser() -> [String: Any] {
        let displayName = UserDataManager.shared.displayName ?? "Alex"
        let gallery: [[String: Any]] = defaultGalleryFiles.enumerated().map { index, file in
            [
                "id": index + 1,
                "user_id": 1,
                "filename": file,
                "filetype": "image",
                "filefor": "gallery",
                "is_primary": index == 0,
                "status": 1,
                "created_at": "2026-10-01 10:00:00",
                "updated_at": "2026-10-01 10:00:00"
            ]
        }
        let info: [String: Any] = [
            "id": 1,
            "user_id": 1,
            "fullname": displayName,
            "display_name": displayName,
            "dob": "2000-06-15",
            "gender": 1,
            "sexuality": 4,
            "height": 196,
            "smoking": 101,
            "drinking": 104,
            "religion": 123,
            "education": 147,
            "interests": [134, 135, 136, 137, 138],
            "about_me": "Music lover, foodie and weekend traveller. Looking for someone to share good conversations and better coffee with.",
            "lat": 22.7196,
            "lng": 75.8577,
            "location": "Indore, Madhya Pradesh",
            "banner": "delete-9",
            "is_online": true,
            "gesture_is_verified": false,
            "is_active": true,
            "created_at": "2026-10-01 10:00:00",
            "updated_at": "2026-10-01 10:00:00"
        ]
        return [
            "id": 1,
            "username": displayName,
            "email": "alex@flirttime.love",
            "is_completed": 1,
            "page_redirect": "home",
            "user_images": gallery,
            "user_info": info
        ]
    }
}
