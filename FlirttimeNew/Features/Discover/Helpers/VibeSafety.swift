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

enum VibeSafety {

    static let reportReasons = [
        "Fake profile",
        "Inappropriate photos",
        "Harassment or hate speech",
        "Scam or spam",
        "Underage user",
        "Something else"
    ]

    // TODO: send the report to the report-user endpoint once it is integrated.
    static func presentReportReasons(for profile: VibeProfile,
                                     from viewController: UIViewController,
                                     sourceView: UIView,
                                     completion: @escaping () -> Void) {
        let sheet = UIAlertController(title: "Report \(profile.displayName)",
                                      message: "Why are you reporting this profile?",
                                      preferredStyle: .actionSheet)
        reportReasons.forEach { reason in
            sheet.addAction(UIAlertAction(title: reason, style: .default) { _ in completion() })
        }
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        viewController.present(sheet, animated: true)
    }
}
