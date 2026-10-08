//
//  ViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import Foundation
import UIKit

enum StoryboardName: String, StringConvertible {
    case splash = "SplashScreen"
    case login = "Login"
    case signUp = "SignUp"
    case dashboard = "Dashboard"
    case editProfile = "EditProfile"
    case moments = "Moments"
    case aboutYou = "AboutYou"
}

protocol StringConvertible {
    var rawValue: String { get }
}

protocol Instantiable: AnyObject {
    static var storyboardName: StringConvertible { get }
}

extension Instantiable {
    static func instantiateFromStoryboard() -> Self {
        return instantiateFromStoryboardHelper()
    }

    private static func instantiateFromStoryboardHelper<T>() -> T {
        let identifier = String(describing: self)
        let storyboard = UIStoryboard(name: storyboardName.rawValue, bundle: nil)
        guard let viewController = storyboard.instantiateViewController(withIdentifier: identifier) as? T else {
            fatalError("Couldn't instantiate from storyboard")
        }
        return viewController
    }

    static var storyboardName: StringConvertible {
        return StoryboardName.splash
    }
}

extension String: StringConvertible {
    var rawValue: String {
        return self
    }
}
