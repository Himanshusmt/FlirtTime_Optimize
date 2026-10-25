//
//  AppLogger.swift
//  FlirttimeNew
//
//  Created by Awais on 25/09/2025.
//
import Foundation
import os.log

public enum AppLogger {
    private static let killCallOSLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.onevibe.live",
        category: "KillCall"
    )

    private static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    public static func debug(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        guard !isSocketConsoleLog(text) else { return }
        print(text)
    }

    /// Socket transport / event traces stay out of the Xcode console; API logs still print.
    private static func isSocketConsoleLog(_ text: String) -> Bool {
        text.hasPrefix("[SOCKET")
            || text.hasPrefix("[Socket")
            || text.hasPrefix("[MomentsSocket]")
            || text.hasPrefix("ChatSocketService")
            || text.hasPrefix("ChatListSocketService")
    }

    /// Always-on kill-state / CallKit diagnostics (Xcode + Console.app when app is killed).
    public static func killCall(_ message: @autoclosure () -> String) {
        let text = message()
        print("[KillCall] \(text)")
        os_log("%{public}@", log: killCallOSLog, type: .info, text)
    }
}
