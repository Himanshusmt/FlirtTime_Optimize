//
//  AppJSON.swift
//  FlirttimeNew
//

import Foundation

/// Lenient lookups into untyped responses. Replace call sites with Codable models
/// once the real response shapes are confirmed.
enum AppJSON {

    /// Looks for the first matching key at the root, in `data`, `data.tokens` and `data.user`.
    static func string(_ json: [String: Any], keys: [String]) -> String? {
        for container in containers(of: json) {
            for key in keys {
                if let value = container[key] as? String, !value.isEmpty {
                    return value
                }
                if let value = container[key] as? NSNumber {
                    return value.stringValue
                }
            }
        }
        return nil
    }

    static func bool(_ json: [String: Any], keys: [String]) -> Bool? {
        for container in containers(of: json) {
            for key in keys {
                if let value = container[key] as? Bool {
                    return value
                }
            }
        }
        return nil
    }

    static func accessToken(in json: [String: Any]) -> String? {
        string(json, keys: ["accessToken", "token", "jwt", "access_token"])
    }

    static func refreshToken(in json: [String: Any]) -> String? {
        string(json, keys: ["refreshToken", "refresh_token"])
    }

    static func verificationId(in json: [String: Any]) -> String? {
        string(json, keys: ["verificationId", "verification_id"])
    }

    private static func containers(of json: [String: Any]) -> [[String: Any]] {
        var result = [json]
        if let data = json["data"] as? [String: Any] {
            result.append(data)
            if let tokens = data["tokens"] as? [String: Any] { result.append(tokens) }
            if let user = data["user"] as? [String: Any] { result.append(user) }
        }
        return result
    }
}
