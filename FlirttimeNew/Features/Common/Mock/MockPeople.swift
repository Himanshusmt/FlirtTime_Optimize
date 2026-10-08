//
//  MockPeople.swift
//  FlirttimeNew
//
//  Sample users served by the mock view models until the real APIs are integrated.
//  Photo/banner values are bundled asset names; `ImageLoader` resolves them locally.
//

import Foundation

struct MockPerson {
    let id: Int
    let fullname: String
    let displayName: String
    let dob: String
    let gender: Int
    let photos: [String]
    let banner: String?
    let about: String
    let location: String
    let isOnline: Bool
    let isVerified: Bool
    let attributes: [String: Int]
    let interests: [Int]
}

enum MockPeople {

    static let all: [MockPerson] = [
        MockPerson(id: 101, fullname: "Cindy Morgan", displayName: "Cindy", dob: "2002-03-14", gender: 2,
                   photos: ["delete-8", "delete-24", "delete-25"], banner: "delete-9",
                   about: "Coffee first, adventures later. Looking for someone who can keep up with my playlist and my travel plans.",
                   location: "Indore, Madhya Pradesh", isOnline: true, isVerified: true,
                   attributes: ["sexuality": 4, "height": 192, "smoking": 101, "drinking": 104, "religion": 123, "education": 147, "relationship": 151, "children": 157],
                   interests: [134, 135, 136, 137, 138]),
        MockPerson(id: 102, fullname: "Ally Verma", displayName: "Ally", dob: "2001-07-22", gender: 2,
                   photos: ["delete-23", "delete-26"], banner: "delete-6",
                   about: "Bookworm by day, dancer by night.",
                   location: "Bhopal, Madhya Pradesh", isOnline: false, isVerified: false,
                   attributes: ["sexuality": 4, "drinking": 103, "smoking": 101, "education": 148],
                   interests: [135, 139, 140]),
        MockPerson(id: 103, fullname: "Riya Mathews", displayName: "Riya", dob: "1999-11-02", gender: 2,
                   photos: ["delete-24", "delete-8"], banner: "delete27",
                   about: "Weekend trekker, weekday coder. Let's grab chai and talk about mountains.",
                   location: "Pune, Maharashtra", isOnline: true, isVerified: true,
                   attributes: ["sexuality": 4, "height": 199, "drinking": 104, "living": 120, "religion": 124],
                   interests: [136, 141, 142, 143]),
        MockPerson(id: 104, fullname: "Meera Kapoor", displayName: "Meera", dob: "2000-01-30", gender: 2,
                   photos: ["delete-25", "delete-3"], banner: nil,
                   about: "Plant mom. Amateur chef. Professional overthinker.",
                   location: "Mumbai, Maharashtra", isOnline: false, isVerified: true,
                   attributes: ["sexuality": 4, "smoking": 101, "education": 147, "children": 156],
                   interests: [134, 144]),
        MockPerson(id: 105, fullname: "Sara Khan", displayName: "Sara", dob: "2003-05-09", gender: 2,
                   photos: ["delete-26", "delete-5"], banner: "delete-9",
                   about: "Sunsets, street food and spontaneous road trips.",
                   location: "Jaipur, Rajasthan", isOnline: true, isVerified: false,
                   attributes: ["sexuality": 4, "drinking": 105, "religion": 125],
                   interests: [137, 145, 146]),
        MockPerson(id: 106, fullname: "Nisha Rao", displayName: "Nisha", dob: "1998-09-18", gender: 2,
                   photos: ["delete-7", "delete-22"], banner: "delete-6",
                   about: "Gym in the morning, Netflix at night.",
                   location: "Hyderabad, Telangana", isOnline: false, isVerified: true,
                   attributes: ["sexuality": 6, "height": 190, "smoking": 102],
                   interests: [136, 138, 147]),
        MockPerson(id: 107, fullname: "Tanya Singh", displayName: "Tanya", dob: "2001-12-01", gender: 2,
                   photos: ["delete-3", "delete-23"], banner: nil,
                   about: "Ask me about my dog.",
                   location: "Delhi", isOnline: true, isVerified: true,
                   attributes: ["sexuality": 4, "living": 122],
                   interests: [134, 135]),
        MockPerson(id: 108, fullname: "Priya Nair", displayName: "Priya", dob: "2000-04-25", gender: 2,
                   photos: ["delete-5", "delete-7"], banner: "delete27",
                   about: "Classical music and modern problems.",
                   location: "Kochi, Kerala", isOnline: false, isVerified: false,
                   attributes: ["sexuality": 4, "religion": 126, "education": 148],
                   interests: [137, 139, 140, 141])
    ]

    static func person(id: Int) -> MockPerson? {
        all.first { $0.id == id }
    }

    static let likesYouIDs = [101, 103, 105, 106, 107]
    static let youLikedIDs: [(id: Int, superLike: Bool)] = [(102, false), (104, true), (108, false)]
    static let matchIDs = [101, 103, 107]
    static let complimentSenders: [(id: Int, text: String)] = [
        (104, "Your smile in the second picture is everything!"),
        (106, "Love your vibe, would be great to chat.")
    ]

    // MARK: - JSON builders (mirror the server payloads)

    static func userInfoJSON(_ p: MockPerson) -> [String: Any] {
        var json: [String: Any] = [
            "id": p.id,
            "user_id": p.id,
            "fullname": p.fullname,
            "display_name": p.displayName,
            "dob": p.dob,
            "gender": p.gender,
            "interests": p.interests,
            "about_me": p.about,
            "lat": 22.7196,
            "lng": 75.8577,
            "location": p.location,
            "avatar": p.photos.first ?? "",
            "images": p.photos.enumerated().map { ["image": $1, "type": "gallery", "is_primary": $0 == 0] },
            "is_online": p.isOnline,
            "online_time": "2026-10-07 10:00:00",
            "age_show": true,
            "distance_show": true,
            "location_show": true,
            "online_show": true,
            "bump_into_show": true,
            "enable_public_search": true,
            "dob_is_verified": true,
            "gender_is_verified": true,
            "video_is_verified": p.isVerified,
            "gesture_is_verified": p.isVerified,
            "is_fake": false,
            "is_active": p.isVerified,
            "created_at": "2026-01-01 10:00:00",
            "updated_at": "2026-10-01 10:00:00"
        ]
        if let banner = p.banner {
            json["banner"] = banner
        }
        p.attributes.forEach { json[userInfoKey(forAlias: $0.key)] = $0.value }
        return json
    }

    static func matchedUserJSON(_ p: MockPerson) -> [String: Any] {
        var json = userInfoJSON(p)
        json["matched_user_id"] = p.id
        json["lat"] = "22.7196"
        json["lng"] = "75.8577"
        json["device_type"] = "iOS"
        json["fcm_token"] = ""
        return json
    }

    static func senderProfileJSON(_ p: MockPerson) -> [String: Any] {
        var json = userInfoJSON(p)
        json["device_type"] = "iOS"
        json["fcm_token"] = ""
        json["mother_tongue"] = nil
        return json
    }

    static func momentImagesJSON(_ p: MockPerson) -> [[String: Any]] {
        p.photos.enumerated().map { index, photo in
            [
                "id": p.id * 100 + index,
                "user_id": p.id,
                "title": "",
                "body": "",
                "images": [photo],
                "like_count": 3 + index,
                "comment_count": index,
                "share_count": 0,
                "status": 1,
                "created_at": "2026-09-2\(index) 10:00:00",
                "updated_at": "2026-09-2\(index) 10:00:00",
                "is_like": false,
                "user_info": ["user_id": p.id, "fullname": p.fullname, "display_name": p.displayName, "avatar": p.photos.first ?? ""]
            ]
        }
    }

    /// Attribute aliases (Attributes.json) differ from the user_info keys for a few fields.
    static func userInfoKey(forAlias alias: String) -> String {
        switch alias {
        case Constants.QuestionOption.eye_colour: return "eye_colour"
        case Constants.QuestionOption.hair_colour: return "hair_colour"
        case Constants.QuestionOption.mother_tongue: return "mother_tongue"
        case Constants.QuestionOption.interests: return "interests"
        default: return alias
        }
    }
}
