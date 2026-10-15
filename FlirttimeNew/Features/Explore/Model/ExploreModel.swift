//
//  ExploreModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 21/05/24.
//

import Foundation
import UIKit

struct ExploreModel{
    var image:UIImage?
    var name:String?
    var isVerifiedUser:Bool?
}

struct FilterModel:Codable {
    var gender:String?
    var minAge:String?
    var maxAge:String?
    var distance:String?
    var isVerified:String?
    var isOnline:String?
    var interests:[Int]?
    var intents:[String]?
    /// Interest UUIDs from `discovery/filters/options`.
    var interestIds:[String]?
}

// MARK: - People search (GET users/search)

/// The `data` of GET `users/search`: `{ users, pagination }` or a bare array of users.
struct UserSearchPage: Codable {
    let users: [UserSearchResult]
    let page: Int?
    let hasMore: Bool?

    init(from decoder: Decoder) throws {
        if let users = try? decoder.singleValueContainer().decode([UserSearchResult].self) {
            self.users = users
            page = nil
            hasMore = nil
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        let pagination = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("pagination"))
        users = c.first([UserSearchResult].self, "users", "results", "profiles", "items") ?? []
        page = pagination?.int("page", "currentPage") ?? c.int("page")
        let totalPages = pagination?.int("totalPages") ?? c.int("totalPages")
        if let hasMore = pagination?.bool("hasMore", "hasNextPage") ?? c.bool("hasMore", "hasNextPage") {
            self.hasMore = hasMore
        } else if let page, let totalPages {
            hasMore = page < totalPages
        } else {
            hasMore = nil
        }
    }
}

struct UserSearchResult: Codable {
    let userId: String?
    let name: String?
    let username: String?
    let age: Int?
    let city: String?
    /// Full URL or relative S3 key.
    let profilePhoto: String?
    let isVerified: Bool?
    let isOnline: Bool?
    let distanceKm: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        let location = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("location"))
        let photo = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("profilePhoto"))
        userId = c.string("userId", "id")
        name = c.string("name", "fullName", "displayName")
        username = c.string("username", "userName")
        age = c.int("age") ?? DiscoverViewModel.age(from: c.string("dob", "dateOfBirth"))
        city = c.string("city", "location") ?? location?.string("city", "label", "name")
        profilePhoto = c.string("profilePhoto", "primaryPhotoUrl", "avatar", "photo")
            ?? photo?.string("url", "thumbnailUrl")
        isVerified = c.bool("isVerified", "isFaceVerified")
        isOnline = c.bool("isOnline")
        distanceKm = c.first(Double.self, "distanceKm", "distance")
    }

    var displayName: String {
        DiscoverViewModel.displayName(username: username, name: name)
    }
}
