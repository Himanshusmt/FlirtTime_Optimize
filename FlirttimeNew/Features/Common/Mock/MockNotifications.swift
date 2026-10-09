//
//  MockNotifications.swift
//  FlirttimeNew
//
//  Sample notification list served by `NotificationViewModel` until the notifications API is integrated.
//  Timestamps are relative to launch so the Today / Yesterday / Earlier grouping stays meaningful.
//

import Foundation

enum MockNotifications {

    private struct Entry {
        let id: Int
        let type: NotificationType
        let personID: Int?
        let title: String
        let body: String
        let minutesAgo: Int
    }

    private static let entries: [Entry] = [
        Entry(id: 901, type: .match, personID: 101, title: "It's a match!",
              body: "You and Cindy liked each other. Say hi!", minutesAgo: 12),
        Entry(id: 902, type: .like, personID: 105, title: "Sara liked you",
              body: "Check out her profile and like back to match.", minutesAgo: 95),
        Entry(id: 903, type: .compliment, personID: 104, title: "Meera sent a compliment",
              body: "\u{201C}Your smile in the second picture is everything!\u{201D}", minutesAgo: 60 * 5),
        Entry(id: 904, type: .favorite, personID: 106, title: "Nisha super liked you",
              body: "You stood out! See who's into you.", minutesAgo: 60 * 26),
        Entry(id: 905, type: .message, personID: 103, title: "Riya",
              body: "Sent you a new message.", minutesAgo: 60 * 30),
        Entry(id: 906, type: .profileImageVerified, personID: nil, title: "Profile verified",
              body: "Your profile photo has been verified. You now have the blue tick!", minutesAgo: 60 * 24 * 3),
        Entry(id: 907, type: .imageUnverified, personID: nil, title: "Photo not approved",
              body: "One of your photos didn't meet our guidelines. Tap to replace it.", minutesAgo: 60 * 24 * 4),
        Entry(id: 908, type: .membershipUpgrade, personID: nil, title: "Go Premium",
              body: "Unlock unlimited likes and see who likes you.", minutesAgo: 60 * 24 * 6)
    ]

    private static var readIDs: Set<Int> = [906, 908]

    private static let createdAt = Date()

    static func markRead(id: Int) -> [String: Any]? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        readIDs.insert(id)
        var json = notificationJSON(entry)
        json["data"] = nil
        return json
    }

    static func markAllRead() {
        readIDs.formUnion(entries.map(\.id))
    }

    static var listJSON: [[String: Any]] {
        entries.map(notificationJSON)
    }

    private static func notificationJSON(_ entry: Entry) -> [String: Any] {
        var detail: [String: Any] = ["notify_type": entry.type.rawValue]
        if let personID = entry.personID {
            detail["user_id"] = "\(personID)"
            detail["image"] = MockPeople.person(id: personID)?.photos.first
        }
        let timestamp = NotificationData.dateFormatter.string(from: createdAt.addingTimeInterval(TimeInterval(-entry.minutesAgo * 60)))
        return [
            "id": entry.id,
            "user_id": MockDataStore.shared.currentUserID,
            "title": entry.title,
            "body": entry.body,
            "type": entry.type.rawValue,
            "is_read": readIDs.contains(entry.id),
            "created_at": timestamp,
            "updated_at": timestamp,
            "data": detail
        ]
    }
}
