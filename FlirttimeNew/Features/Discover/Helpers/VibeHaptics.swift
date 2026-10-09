//
//  VibeHaptics.swift
//  FlirttimeNew
//

import UIKit

enum VibeHaptics {

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        light.prepare()
        heavy.prepare()
    }

    /// Drag crossed the commit threshold.
    static func threshold() {
        light.impactOccurred()
        light.prepare()
    }

    static func superVibe() {
        heavy.impactOccurred()
    }

    static func connected() {
        notification.notificationOccurred(.success)
    }

    static func failed() {
        notification.notificationOccurred(.error)
    }
}
