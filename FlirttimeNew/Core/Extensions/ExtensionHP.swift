//
//  Untitled.swift
//  FlirtTime
//
//  Created by himanshu pal on 09/06/25.
//

import Foundation
import UIKit

extension Data {
    func decode<T: Decodable>(to type: T.Type) -> T? {
        if self.isEmpty {
            print("❌ No data to decode.")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let decodedObject = try decoder.decode(T.self, from: self)
            return decodedObject

        } catch DecodingError.typeMismatch(let type, let context) {
            print("❌ Type mismatch:")
            print(" - Expected type: \(type)")
            print(" - Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            print(" - Debug description: \(context.debugDescription)")

        } catch DecodingError.valueNotFound(let type, let context) {
            print("❌ Value not found:")
            print(" - Missing type: \(type)")
            print(" - Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            print(" - Debug description: \(context.debugDescription)")

        } catch DecodingError.keyNotFound(let key, let context) {
            print("❌ Key not found:")
            print(" - Missing key: \(key.stringValue)")
            print(" - Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            print(" - Debug description: \(context.debugDescription)")

        } catch DecodingError.dataCorrupted(let context) {
            print("❌ Data corrupted:")
            print(" - Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            print(" - Debug description: \(context.debugDescription)")

        } catch {
            print("❌ Unknown error: \(error.localizedDescription)")
        }

        return nil
    }
}

//use
//if let model: BlockedUserListModel = data.decode(to: BlockedUserListModel.self) {
//print("✅ Successfully decoded model: \(model)")
//} else {
//print("❌ Failed to decode.")
//}

enum ColorManager {
    static var fwhite: UIColor {
        return UIColor(named: "fwhite") ?? .white
    }
    static var fred: UIColor {
        return UIColor(named: "fred") ?? .red
    }
    static var fgreySeperator: UIColor {
        return UIColor(named: "fgreySeperator") ?? .lightGray
    }
    static var fgreyLight: UIColor {
        return UIColor(named: "fgreyLight") ?? .lightGray
    }
    static var fgreyDark: UIColor {
        return UIColor(named: "fgreyDark") ?? .white
    }
    static var fblack: UIColor {
        return UIColor(named: "fblack") ?? .white
    }
}

