//
//  ManageNotificationViewController.swift
//  FlirttimeNew
//

import UIKit
import Combine
import UserNotifications

final class ManageNotificationViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    @IBOutlet private weak var newMessageSwitch: UISwitch!
    @IBOutlet private weak var newMatchesSwitch: UISwitch!
    @IBOutlet private weak var likesCommentsCallsSwitch: UISwitch!
    @IBOutlet private weak var profileVisitSwitch: UISwitch!
    @IBOutlet private weak var pushSwitch: UISwitch!
    @IBOutlet private weak var emailSwitch: UISwitch!
    @IBOutlet private weak var appUpdatesSwitch: UISwitch!
    @IBOutlet private weak var promotionSwitch: UISwitch!
    @IBOutlet private weak var discountSwitch: UISwitch!
    @IBOutlet private weak var newServiceSwitch: UISwitch!
    @IBOutlet private weak var newTipsSwitch: UISwitch!
    @IBOutlet private weak var pushDisabledBanner: UIView!

    private let viewModel = SettingsViewModel()
    private var cancellables: Set<AnyCancellable> = []

    private var switches: [NotificationSettingKey: UISwitch] {
        [.newMessage: newMessageSwitch,
         .newMatches: newMatchesSwitch,
         .likesCommentsCalls: likesCommentsCallsSwitch,
         .profileVisit: profileVisitSwitch,
         .push: pushSwitch,
         .email: emailSwitch,
         .appUpdates: appUpdatesSwitch,
         .promotion: promotionSwitch,
         .discountAvailable: discountSwitch,
         .newServiceAvailable: newServiceSwitch,
         .newTipsAvailable: newTipsSwitch]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setBinding()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPushPermission),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        viewModel.loadProfile()
        refreshPushPermission()
    }

    private func setBinding() {
        viewModel.$user.receive(on: DispatchQueue.main).sink { [weak self] user in
            guard let self, user != nil else { return }
            let settings = self.viewModel.notifySettings
            for (key, toggle) in self.switches {
                toggle.isOn = settings?.value(for: key) ?? key.defaultValue
            }
        }.store(in: &cancellables)
    }

    @objc private func refreshPushPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.pushDisabledBanner.isHidden = settings.authorizationStatus != .denied
            }
        }
    }

    private func saveSettings() {
        viewModel.updateNotificationSettings(switches.mapValues(\.isOn))
    }

    private func requestPushPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        UIApplication.shared.registerForRemoteNotifications()
                    } else {
                        self.pushSwitch.setOn(false, animated: true)
                        self.saveSettings()
                    }
                    self.refreshPushPermission()
                }
            }
        }
    }

    // MARK: - Actions

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func switchChanged(_ sender: UISwitch) {
        UISelectionFeedbackGenerator().selectionChanged()
        saveSettings()
        if sender === pushSwitch, sender.isOn {
            requestPushPermissionIfNeeded()
        }
    }

    @IBAction private func openSystemSettingsTapped(_ sender: UIButton) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
