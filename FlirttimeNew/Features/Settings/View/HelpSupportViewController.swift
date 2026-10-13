//
//  HelpSupportViewController.swift
//  FlirttimeNew
//

import UIKit
import MessageUI

final class HelpSupportViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    private static let supportEmail = "support@flirttime.in"

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
    }

    private func openFAQ(category: FAQCategory?) {
        let faqViewController: FAQViewController = FAQViewController.instantiateFromStoryboard()
        faqViewController.category = category
        navigationController?.pushViewController(faqViewController, animated: true)
    }

    // MARK: - Actions

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func faqTapped(_ sender: UIButton) {
        openFAQ(category: nil)
    }

    /// Topic rows carry their `FAQCategory` raw value in the storyboard `tag`.
    @IBAction private func topicTapped(_ sender: UIButton) {
        openFAQ(category: FAQCategory(rawValue: sender.tag))
    }

    @IBAction private func emailSupportTapped(_ sender: UIButton) {
        let subject = "Flirt Time support"
        if MFMailComposeViewController.canSendMail() {
            let composer = MFMailComposeViewController()
            composer.mailComposeDelegate = self
            composer.setToRecipients([Self.supportEmail])
            composer.setSubject(subject)
            present(composer, animated: true)
        } else if let url = URL(string: "mailto:\(Self.supportEmail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url) { [weak self] opened in
                if !opened { self?.copySupportEmail() }
            }
        } else {
            copySupportEmail()
        }
    }

    private func copySupportEmail() {
        UIPasteboard.general.string = Self.supportEmail
        aCustomToastView.show(message: "Support email copied: \(Self.supportEmail)")
    }
}

extension HelpSupportViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true) { [weak self] in
            if result == .sent {
                self?.aCustomToastView.show(message: "Thanks! We'll get back to you soon.")
            }
        }
    }
}
