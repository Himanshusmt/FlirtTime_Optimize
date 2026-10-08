//
//  LocationModels.swift
//  FlirttimeNew
//
//  Created by Awais on 08/09/25.
//

import Foundation
import CoreLocation

enum LocationMessageType: String, Codable {
    case staticLocation = "static_location"
    case liveLocation = "live_location"
}

struct LocationData: Codable {
    let id: String?
    let type: LocationMessageType
    let latitude: Double
    let longitude: Double
    let address: String?
    let timestamp: String
    
    let duration: Int?
    let expiresAt: String?
    let isActive: Bool?
    let lastUpdate: String?
    
    enum CodingKeys: String, CodingKey {
        case id, type, latitude, longitude, address, timestamp, duration
        case expiresAt = "expires_at"
        case isActive = "is_active"
        case lastUpdate = "last_update"
    }
}

struct LiveLocationSession: Codable {
    let id: String
    let conversationId: String
    let userId: String
    let duration: Int // minutes
    let startTime: Date
    let expiresAt: Date
    let isActive: Bool
    var lastLocation: CLLocationCoordinate2D?
    var lastUpdate: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, conversationId, userId, duration, startTime, expiresAt, isActive, lastUpdate
        case lastLocationLatitude = "last_location_latitude"
        case lastLocationLongitude = "last_location_longitude"
    }
    
    init(conversationId: String, userId: String, duration: Int) {
        self.id = UUID().uuidString
        self.conversationId = conversationId
        self.userId = userId
        self.duration = duration
        self.startTime = Date()
        self.expiresAt = Date().addingTimeInterval(TimeInterval(duration * 60))
        self.isActive = true
        self.lastLocation = nil
        self.lastUpdate = nil
    }
    
    init(id: String, conversationId: String, userId: String, duration: Int, startTime: Date, expiresAt: Date, isActive: Bool, lastLocation: CLLocationCoordinate2D?, lastUpdate: Date?) {
        self.id = id
        self.conversationId = conversationId
        self.userId = userId
        self.duration = duration
        self.startTime = startTime
        self.expiresAt = expiresAt
        self.isActive = isActive
        self.lastLocation = lastLocation
        self.lastUpdate = lastUpdate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        userId = try container.decode(String.self, forKey: .userId)
        duration = try container.decode(Int.self, forKey: .duration)
        startTime = try container.decode(Date.self, forKey: .startTime)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        lastUpdate = try container.decodeIfPresent(Date.self, forKey: .lastUpdate)
        
        // Handle CLLocationCoordinate2D
        if let latitude = try container.decodeIfPresent(Double.self, forKey: .lastLocationLatitude),
           let longitude = try container.decodeIfPresent(Double.self, forKey: .lastLocationLongitude) {
            lastLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            lastLocation = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(userId, forKey: .userId)
        try container.encode(duration, forKey: .duration)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(lastUpdate, forKey: .lastUpdate)
        
        if let lastLocation = lastLocation {
            try container.encode(lastLocation.latitude, forKey: .lastLocationLatitude)
            try container.encode(lastLocation.longitude, forKey: .lastLocationLongitude)
        }
    }
    
    var isExpired: Bool {
        return Date() > expiresAt || !isActive
    }
    
    var remainingTime: TimeInterval {
        return max(0, expiresAt.timeIntervalSinceNow)
    }
    
    var remainingTimeString: String {
        let remaining = remainingTime
        let hours = Int(remaining) / 3600
        let minutes = Int(remaining.truncatingRemainder(dividingBy: 3600)) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct SendLocationRequest: Codable {
    let conversationId: String
    let type: LocationMessageType
    let latitude: Double
    let longitude: Double
    let address: String?
    let duration: Int?
    let comment: String?
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case type, latitude, longitude, address, duration, comment
    }
}

struct LocationDurationOption {
    let title: String
    let minutes: Int // -1 for indefinite/always
    let isSelected: Bool

    static let defaultOptions = [
        LocationDurationOption(title: "30 minutes", minutes: 30, isSelected: true),
        LocationDurationOption(title: "2 hours", minutes: 120, isSelected: false),
        LocationDurationOption(title: "24 hours", minutes: 1440, isSelected: false),
        LocationDurationOption(title: "Always", minutes: -1, isSelected: false) // -1 = indefinite
    ]

    var isIndefinite: Bool {
        return minutes == -1
    }
}

// MARK: - Live Location Request/Response Models

struct StartLiveLocationRequest: Codable {
    let conversationId: String
    let latitude: Double
    let longitude: Double
    let address: String?
    let duration: Int // -1 for always/indefinite
    let type: String = "live_location"

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case latitude, longitude, address, duration, type
    }
}

struct LiveLocationUpdate: Codable {
    let sessionId: String
    let messageId: String
    let conversationId: String
    let latitude: Double
    let longitude: Double
    let timestamp: String
    let address: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case latitude, longitude, timestamp, address
    }
}

struct StopLiveLocationRequest: Codable {
    let sessionId: String
    let messageId: String
    let conversationId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case messageId = "message_id"
        case conversationId = "conversation_id"
    }
}

enum LocationPermissionState {
    case notDetermined
    case denied
    case restricted
    case authorizedWhenInUse
    case authorizedAlways
    case unknown
    
    init(from clAuthorizationStatus: CLAuthorizationStatus) {
        switch clAuthorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .authorizedWhenInUse:
            self = .authorizedWhenInUse
        case .authorizedAlways:
            self = .authorizedAlways
        @unknown default:
            self = .unknown
        }
    }
    
    var canUseLocation: Bool {
        return self == .authorizedWhenInUse || self == .authorizedAlways
    }
}

extension ConversationMessage {
    var locationData: LocationData? {
        // 1) Prefer full JSON string in metadata["location"]
          if let metadata = metadata,
              let locationDataString = metadata["location"]?.value as? String,
              let locationData = locationDataString.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(LocationData.self, from: locationData) {
            return parsed
        }

        // 2) Fallback to discrete lat/lon entries in metadata
          if let metadata = metadata,
              let latString = metadata["latitude"]?.value as? String,
              let lonString = metadata["longitude"]?.value as? String,
              let lat = Double(latString),
              let lon = Double(lonString) {
                let typeString = (metadata["locationType"]?.value as? String) ?? "static_location"
            let type = LocationMessageType(rawValue: typeString) ?? .staticLocation
            return LocationData(
                id: id,
                type: type,
                latitude: lat,
                longitude: lon,
                address: metadata["address"]?.value as? String,
                timestamp: createdAt ?? "",
                duration: Int((metadata["duration"]?.value as? String) ?? "0"),
                expiresAt: metadata["expiresAt"]?.value as? String,
                isActive: (metadata["isActive"]?.value as? Bool) ?? false,
                lastUpdate: metadata["lastUpdate"]?.value as? String
            )
        }

        // 3) Fallback to top-level server `location` object if provided
        if let loc = serverLocation,
           let lat = loc.lat,
           let lon = loc.lng {
            return LocationData(
                id: id,
                type: .staticLocation,
                latitude: lat,
                longitude: lon,
                address: (loc.address?.isEmpty == false ? loc.address : nil),
                timestamp: createdAt ?? "",
                duration: nil,
                expiresAt: nil,
                isActive: nil,
                lastUpdate: nil
            )
        }

        return nil
    }
}
