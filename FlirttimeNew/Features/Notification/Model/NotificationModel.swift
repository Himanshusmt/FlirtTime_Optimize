//
//  NotificationModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 23/05/24.
//

import Foundation

// TODO: switch to typed Codable models once a sample `GET notifications` / `counts` response is available.
// Until then the parsers below accept the common key spellings so the screen works against the live API.

// MARK: - Notification

struct AppNotification {
    let id: String
    let type: String?
    let title: String?
    let body: String?
    var isRead: Bool
    let createdAt: Date?
    let image: String?
    /// Extra fields for navigation (`notify_type`, `user_id`, ...), merged with `type`.
    let payload: [AnyHashable: Any]

    init?(json: [String: Any]) {
        guard let id = JSONValue.string(json["id"]) ?? JSONValue.string(json["_id"]) else { return nil }
        let data = json["data"] as? [String: Any] ?? json["metadata"] as? [String: Any] ?? [:]
        let actor = json["actor"] as? [String: Any] ?? json["sender"] as? [String: Any] ?? json["fromUser"] as? [String: Any]

        self.id = id
        type = JSONValue.string(json["type"]) ?? JSONValue.string(data["notify_type"]) ?? JSONValue.string(data["type"])
        title = JSONValue.string(json["title"])
        body = JSONValue.string(json["body"]) ?? JSONValue.string(json["message"])
        isRead = JSONValue.bool(json["isRead"]) ?? JSONValue.bool(json["is_read"])
            ?? ((json["readAt"] ?? json["read_at"]).map { !($0 is NSNull) } ?? false)
        createdAt = JSONValue.date(json["createdAt"] ?? json["created_at"])
        let imageCandidates: [Any?] = [
            json["image"], json["imageUrl"],
            actor?["profilePhotoUrl"], actor?["profilePhoto"], actor?["profilePicture"], actor?["avatar"], actor?["image"],
            data["image"], data["imageUrl"]
        ]
        image = imageCandidates.lazy.compactMap(JSONValue.string).first

        var payload: [AnyHashable: Any] = data
        let navigation = json["navigation"] as? [String: Any] ?? data["navigation"] as? [String: Any]
        if let navigation {
            payload["navigation"] = navigation
            payload["target_id"] = JSONValue.string(navigation["targetId"])
            if let navType = JSONValue.string(navigation["type"]) {
                payload["navType"] = navType
            }
        }
        if let type {
            if payload["type"] == nil { payload["type"] = type }
            if payload["notify_type"] == nil { payload["notify_type"] = type }
        }
        if payload["user_id"] == nil, let actorId = JSONValue.string(actor?["id"]) ?? JSONValue.string(actor?["_id"]) {
            payload["user_id"] = actorId
        }
        self.payload = payload
    }

    var notificationType: NotificationType {
        NotificationType(from: payload)
    }
}

// MARK: - Feed

struct NotificationSection {
    let title: String
    var items: [AppNotification]
}

struct NotificationFeed {
    let sections: [NotificationSection]
    let nextCursor: String?
    let hasMore: Bool

    private static let bucketKeys: [(key: String, title: String)] = [
        ("today", "Today"), ("yesterday", "Yesterday"), ("thisWeek", "This week"),
        ("this_week", "This week"), ("earlier", "Earlier"), ("older", "Earlier")
    ]

    init(json: [String: Any]) {
        let data = json["data"] as? [String: Any] ?? json
        let pagination = data["pagination"] as? [String: Any] ?? data["meta"] as? [String: Any] ?? data

        nextCursor = JSONValue.string(pagination["nextCursor"]) ?? JSONValue.string(pagination["next_cursor"])
        hasMore = JSONValue.bool(pagination["hasMore"]) ?? JSONValue.bool(pagination["has_more"]) ?? (nextCursor != nil)

        if let rawSections = data["sections"] as? [[String: Any]] {
            sections = rawSections.compactMap { section in
                let items = Self.items(section["items"] ?? section["notifications"] ?? section["data"])
                guard !items.isEmpty else { return nil }
                let title = JSONValue.string(section["title"]) ?? JSONValue.string(section["label"])
                    ?? Self.title(forKey: JSONValue.string(section["key"]) ?? "")
                return NotificationSection(title: title, items: items)
            }
        } else if let buckets = data["sections"] as? [String: Any] ?? (Self.hasBuckets(data) ? data : nil) {
            var merged: [NotificationSection] = []
            for bucket in Self.bucketKeys {
                let items = Self.items(buckets[bucket.key])
                guard !items.isEmpty else { continue }
                if let index = merged.firstIndex(where: { $0.title == bucket.title }) {
                    merged[index].items += items
                } else {
                    merged.append(NotificationSection(title: bucket.title, items: items))
                }
            }
            sections = merged
        } else {
            let flat = Self.items(data["items"] ?? data["notifications"] ?? json["data"])
            sections = Self.groupByDay(flat)
        }
    }

    private static func hasBuckets(_ data: [String: Any]) -> Bool {
        bucketKeys.contains { data[$0.key] is [[String: Any]] }
    }

    private static func items(_ value: Any?) -> [AppNotification] {
        (value as? [[String: Any]])?.compactMap(AppNotification.init(json:)) ?? []
    }

    private static func title(forKey key: String) -> String {
        bucketKeys.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.title ?? key.capitalized
    }

    static func groupByDay(_ notifications: [AppNotification]) -> [NotificationSection] {
        let calendar = Calendar.current
        let sorted = notifications.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        var today: [AppNotification] = []
        var yesterday: [AppNotification] = []
        var earlier: [AppNotification] = []
        for notification in sorted {
            guard let date = notification.createdAt else {
                earlier.append(notification)
                continue
            }
            if calendar.isDateInToday(date) {
                today.append(notification)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(notification)
            } else {
                earlier.append(notification)
            }
        }
        return [NotificationSection(title: "Today", items: today),
                NotificationSection(title: "Yesterday", items: yesterday),
                NotificationSection(title: "Earlier", items: earlier)]
            .filter { !$0.items.isEmpty }
    }
}

// MARK: - Counts

struct NotificationCounts {
    let unread: Int

    init(json: [String: Any]) {
        unread = Self.unread(from: json) ?? 0
    }

    /// Unread total from REST or `notification:count`. `nil` when no count key is present.
    static func unread(from json: [String: Any]) -> Int? {
        let nested = json["data"] as? [String: Any]
        let counts = json["counts"] as? [String: Any]
        for dict in [json, nested, counts].compactMap({ $0 }) {
            if let value = JSONValue.int(dict["unreadCount"])
                ?? JSONValue.int(dict["unread"])
                ?? JSONValue.int(dict["count"])
                ?? JSONValue.int(dict["total"])
                ?? JSONValue.int(dict["notificationCount"])
                ?? JSONValue.int(dict["unread_count"]) {
                return value
            }
        }
        return nil
    }
}

// MARK: - Lenient JSON values

private enum JSONValue {
    static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string.isEmpty ? nil : string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String: return ["true", "1"].contains(string.lowercased())
        default: return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso = ISO8601DateFormatter()

    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let seconds = number.doubleValue
            return Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000 : seconds)
        }
        guard let string = value as? String else { return nil }
        return isoFractional.date(from: string) ?? iso.date(from: string)
    }
}
