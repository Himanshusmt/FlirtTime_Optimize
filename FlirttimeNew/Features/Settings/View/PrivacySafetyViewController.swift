//
//  PrivacySafetyViewController.swift
//  FlirttimeNew
//

import UIKit
import Combine

final class PrivacySafetyViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    @IBOutlet private weak var showAgeSwitch: UISwitch!
    @IBOutlet private weak var showDistanceSwitch: UISwitch!
    @IBOutlet private weak var showOnlineSwitch: UISwitch!
    @IBOutlet private weak var publicSearchSwitch: UISwitch!

    private let viewModel = SettingsViewModel()
    private var cancellables: Set<AnyCancellable> = []

    private var switches: [VisibilitySettingKey: UISwitch] {
        [.ageShow: showAgeSwitch,
         .distanceShow: showDistanceSwitch,
         .onlineShow: showOnlineSwitch,
         .enablePublicSearch: publicSearchSwitch]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setBinding()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        viewModel.loadProfile()
    }

    private func setBinding() {
        viewModel.$user.receive(on: DispatchQueue.main).sink { [weak self] user in
            guard let self, let user else { return }
            let info = user.userInfo
            // A missing flag means the member never turned it off.
            self.showAgeSwitch.isOn = info?.ageShow ?? true
            self.showDistanceSwitch.isOn = info?.distanceShow ?? true
            self.showOnlineSwitch.isOn = info?.onlineShow ?? true
            self.publicSearchSwitch.isOn = info?.enablePublicSearch ?? true
        }.store(in: &cancellables)
    }

    // MARK: - Actions

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func visibilityChanged(_ sender: UISwitch) {
        guard let key = switches.first(where: { $0.value === sender })?.key else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        viewModel.updateVisibility(key, isOn: sender.isOn)
    }
}
