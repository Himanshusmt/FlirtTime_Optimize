//
//  UserDataManager.swift
//  FlirttimeNew
//

import Foundation

final class UserDataManager {

    let defaults = UserDefaults.standard
    static let shared = UserDataManager()

    var firstTime: Bool? {
        get { defaults.object(forKey: "firstTime") as? Bool }
        set { defaults.set(newValue, forKey: "firstTime") }
    }

    var isOTPVerificationDone: Bool? {
        get { defaults.object(forKey: "isOTPVerificationDone") as? Bool }
        set { defaults.set(newValue, forKey: "isOTPVerificationDone") }
    }

    var isHomePageRedirect: Bool? {
        get { defaults.object(forKey: "isHomePageRedirect") as? Bool }
        set { defaults.set(newValue, forKey: "isHomePageRedirect") }
    }

    var displayName: String? {
        get { defaults.string(forKey: "displayName") }
        set { defaults.set(newValue, forKey: "displayName") }
    }

    var userID: Int? {
        get { defaults.object(forKey: "userID") as? Int }
        set { defaults.set(newValue, forKey: "userID") }
    }

    var userAvtarImage: String? {
        get { defaults.string(forKey: "userAvtarImage") }
        set { defaults.set(newValue, forKey: "userAvtarImage") }
    }

    var isHomeVerificationDone: Bool? {
        get { defaults.object(forKey: "isHomeVerified") as? Bool }
        set { defaults.set(newValue, forKey: "isHomeVerified") }
    }

    var isUserSubscriptionDone: Bool? {
        get { defaults.object(forKey: "subscribe") as? Bool }
        set { defaults.set(newValue, forKey: "subscribe") }
    }

    var ProfileStatus: String? {
        get { defaults.string(forKey: "ProfileStatus") }
        set { defaults.set(newValue, forKey: "ProfileStatus") }
    }

    var AvatarStatus: String? {
        get { defaults.string(forKey: "AvatarStatus") }
        set { defaults.set(newValue, forKey: "AvatarStatus") }
    }

    var OTPAuth: String? {
        get { defaults.string(forKey: "OTPAuth") }
        set { defaults.set(newValue, forKey: "OTPAuth") }
    }

    var saveUserInfo: UserResponse? {
        get {
            guard let data = defaults.data(forKey: "currentUserData") else { return nil }
            return try? JSONDecoder().decode(UserResponse.self, from: data)
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "currentUserData")
        }
    }

    var filterDataModel: FilterModel? {
        get {
            guard let data = defaults.data(forKey: "filterDataModel") else { return nil }
            return try? JSONDecoder().decode(FilterModel.self, from: data)
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "filterDataModel")
        }
    }

    func removeUserData() {
        ["isOTPVerificationDone", "isHomePageRedirect", "displayName", "userID", "userAvtarImage",
         "isHomeVerified", "subscribe", "ProfileStatus", "AvatarStatus", "OTPAuth",
         "currentUserData", "filterDataModel"].forEach {
            defaults.removeObject(forKey: $0)
        }
    }
}
