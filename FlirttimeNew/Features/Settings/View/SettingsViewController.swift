//
//  SettingsViewController.swift
//  FlirttimeNew
//
//  The layout (profile card, premium banner, grouped rows) lives in Settings.storyboard;
//  this class only fills it with data and routes the row taps.
//

import UIKit
import Combine

final class SettingsViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    @IBOutlet private weak var avatarImageView: UIImageView!
    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var contactLabel: UILabel!
    @IBOutlet private weak var verifiedImageView: UIImageView!
    @IBOutlet private weak var premiumCardView: UIView!
    @IBOutlet private weak var versionLabel: UILabel!

    private let viewModel = SettingsViewModel()
    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setBinding()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        versionLabel.text = "Flirt Time v\(version) (\(build))"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        updatePremiumCardVisibility()
        viewModel.loadProfile()
    }

    private func setBinding() {
        viewModel.$appUser.combineLatest(viewModel.$myProfile)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user, data in
                guard let self, user != nil || data != nil else { return }
                let profile = data?.profile
                let name = [user?.username, profile?.displayName, user?.fullName]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty } ?? ""
                self.nameLabel.text = name.firstLetterCapitalized
                self.contactLabel.text = [user?.email, user?.phone].compactMap { $0 }.first { !$0.isEmpty }
                self.verifiedImageView.isHidden = (profile?.isVerified ?? user?.isFaceVerified) != true
                let avatar = profile?.avatarURL ?? user?.profilePicture
                self.avatarImageView.loadImage(path: avatar, placeholder: UIImage(named: "ProfileBlur"))
                self.updatePremiumCardVisibility(isSubscribed: data?.isSubscribed ?? user?.isSubscribed)
            }.store(in: &cancellables)

        viewModel.$errorMessage.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self, let error else { return }
            self.showNewAlertPopUp(Title: "Error", Msg: error, isSuccess: false) { _ in }
        }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: .userSubscriptionStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePremiumCardVisibility() }
            .store(in: &cancellables)
    }

    private func updatePremiumCardVisibility(isSubscribed: Bool? = nil) {
        let subscribed = isSubscribed
            ?? UserDataManager.shared.isUserSubscriptionDone
            ?? false
        premiumCardView.isHidden = subscribed
    }

    private func push(_ viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: - Actions

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func editProfileTapped(_ sender: UIButton) {
        push(EditProfileViewController.instantiateFromStoryboard())
    }

    @IBAction private func premiumTapped(_ sender: UIButton) {
        openPremium()
    }

    @IBAction private func personalDetailsTapped(_ sender: UIButton) {
        push(PersonalDetailsViewController.instantiateFromStoryboard())
    }

    @IBAction private func privacySafetyTapped(_ sender: UIButton) {
        push(PrivacySafetyViewController.instantiateFromStoryboard())
    }

    @IBAction private func notificationsTapped(_ sender: UIButton) {
        push(ManageNotificationViewController.instantiateFromStoryboard())
    }

    @IBAction private func filteredProfilesTapped(_ sender: UIButton) {
        push(FilteredProfilesViewController.instantiateFromStoryboard())
    }

    @IBAction private func helpTapped(_ sender: UIButton) {
        push(HelpSupportViewController.instantiateFromStoryboard())
    }

    @IBAction private func shareAppTapped(_ sender: UIButton) {
        let message = "I'm on Flirt Time, come find me! https://flirttime.in"
        let activity = UIActivityViewController(activityItems: [message], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = sender
        present(activity, animated: true)
    }

    @IBAction private func termsTapped(_ sender: UIButton) {
        loadTermsAndConditions()
    }

    @IBAction private func privacyPolicyTapped(_ sender: UIButton) {
        loadPrivacyPolicy()
    }

    @IBAction private func logoutTapped(_ sender: UIButton) {
        aDeleteCustomPopUp.show(message: Constants.logOut.logout, button1Text: Constants.AlertButtons.yes, button2Text: Constants.AlertButtons.No, deleteType: .logout) { [weak self] in
            self?.navigateToLoginScreen()
        }
    }
}
