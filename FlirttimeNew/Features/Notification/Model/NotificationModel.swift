//
//  NotificationModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 23/05/24.
//

import Foundation

// MARK: - Root Model
struct NotificationModel: Codable {
    let status: Bool?
    let imgBaseURL: String?
    let data: [NotificationData]
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case imgBaseURL = "img_base_url"
        case data
        case message
    }
}

// MARK: - Notification Data
struct NotificationData: Codable {
    let userID: Int?
    let createdAt: String?
    let data: NotificationDetailData?
    let type: String?
    let updatedAt: String?
    var isRead: Bool?
    let body: String?
    let title: String?
    let id: Int?
    let actionURL: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case createdAt = "created_at"
        case data
        case type
        case updatedAt = "updated_at"
        case isRead = "is_read"
        case body, title, id
        case actionURL = "action_url"
    }

    // "data" is either a dictionary or an empty-array string ("[]")
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decodeIfPresent(Int.self, forKey: .userID)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        actionURL = try container.decodeIfPresent(String.self, forKey: .actionURL)
        data = try? container.decode(NotificationDetailData.self, forKey: .data)
    }
}

extension NotificationData {
    /// Server timestamps look like "2024-05-23T10:15:00.000000Z".
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var createdDate: Date? {
        createdAt.flatMap(NotificationData.dateFormatter.date(from:))
    }

    var notificationType: NotificationType {
        NotificationType(rawValue: data?.notifyType ?? type ?? NotificationType.unknown.rawValue)
    }
}

// MARK: - Notification Detail Data
struct NotificationDetailData: Codable {
    let notifyType: String?
    let image: String?
    let userID: String?

    enum CodingKeys: String, CodingKey {
        case notifyType = "notify_type"
        case image
        case userID = "user_id"
    }
}

extension NotificationDetailData {
    func toDictionary() -> [AnyHashable: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any] else {
            return nil
        }
        return dict
    }
}

// MARK: - Read Notification
struct ReadNotificationModel: Codable {
    let status: Bool?
    let message: String?
    let data: DataReadNotificationModel?
    let imgBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case status, message, data
        case imgBaseURL = "img_base_url"
    }
}

struct DataReadNotificationModel: Codable {
    let id: Int?
    let userID: Int?
    let title, body: String?
    let isRead: Bool?
    let createdAt, updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title, body
        case isRead = "is_read"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
