//
//  VibeSafety.swift
//  FlirttimeNew
//
//  Verification explanation and report flow shared by the Vibe Card, full profile and Moments.
//

import UIKit

enum VibeVerificationInfo {
    static func present(for profile: VibeProfile, from viewController: UIViewController) {
        let alert = UIAlertController(
            title: "Verified profile",
            message: "\(profile.displayName) completed Flirt Time's selfie verification, so the photos on this profile match the person behind it.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Constants.AlertButtons.ok, style: .default))
        viewController.present(alert, animated: true)
    }
}

/// Report reasons accepted by POST `users/:userId/report`; `rawValue` is the API code.
enum VibeReportReason: String, CaseIterable {
    case fakeProfile = "fake_profile"
    case inappropriateContent = "inappropriate_content"
    case harassment
    case spam
    case scam
    case underage
    case other

    var title: String {
        switch self {
        case .fakeProfile: return "Fake profile"
        case .inappropriateContent: return "Inappropriate photos or content"
        case .harassment: return "Harassment or hate speech"
        case .spam: return "Spam"
        case .scam: return "Scam"
        case .underage: return "Underage user"
        case .other: return "Something else"
        }
    }
}

/// What the user chose from the safety menu on Vibe Details.
enum VibeSafetyAction {
    case report(VibeReportReason)
    case block
}

enum VibeSafety {

    static func presentReportReasons(for profile: VibeProfile,
                                     from viewController: UIViewController,
                                     sourceView: UIView,
                                     completion: @escaping (VibeReportReason) -> Void) {
        let sheet = UIAlertController(title: "Report \(profile.displayName)",
                                      message: "Why are you reporting this profile?",
                                      preferredStyle: .actionSheet)
        VibeReportReason.allCases.forEach { reason in
            sheet.addAction(UIAlertAction(title: reason.title, style: .default) { _ in completion(reason) })
        }
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        viewController.present(sheet, animated: true)
    }
}
