//
//  PersonalDetailsViewController.swift
//  FlirttimeNew
//

import UIKit
import Combine

final class PersonalDetailsViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    @IBOutlet private weak var fullNameLabel: UILabel!
    @IBOutlet private weak var emailLabel: UILabel!
    @IBOutlet private weak var phoneLabel: UILabel!
    @IBOutlet private weak var dobLabel: UILabel!
    @IBOutlet private weak var locationLabel: UILabel!

    private let viewModel = SettingsViewModel()
    private var cancellables: Set<AnyCancellable> = []

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()

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
            self.fullNameLabel.text = Self.valueOrPlaceholder(info?.fullname?.firstLetterCapitalized)
            self.emailLabel.text = Self.valueOrPlaceholder(user.email)
            self.phoneLabel.text = Self.valueOrPlaceholder(user.phone.map { "+\(user.phoneCode ?? "") \($0)" })
            self.dobLabel.text = Self.valueOrPlaceholder(info?.dob
                .flatMap(Self.apiDateFormatter.date(from:))
                .map(Self.displayDateFormatter.string(from:)))
            self.locationLabel.text = Self.valueOrPlaceholder(info?.location)
        }.store(in: &cancellables)

        viewModel.$errorMessage.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self, let error else { return }
            self.showNewAlertPopUp(Title: "Error", Msg: error, isSuccess: false) { _ in }
        }.store(in: &cancellables)
    }

    private static func valueOrPlaceholder(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not added" : trimmed
    }

    // MARK: - Actions

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func logoutTapped(_ sender: UIButton) {
        aDeleteCustomPopUp.show(message: Constants.logOut.logout, button1Text: Constants.AlertButtons.yes, button2Text: Constants.AlertButtons.No, deleteType: .logout) { [weak self] in
            self?.navigateToLoginScreen()
        }
    }

    @IBAction private func deleteAccountTapped(_ sender: UIButton) {
        aDeleteCustomPopUp.show(message: Constants.deleteAccount.delete, button1Text: Constants.AlertButtons.yes, button2Text: Constants.AlertButtons.No, deleteType: .logout) { [weak self] in
            guard let self else { return }
            self.setLoading(true)
            self.viewModel.deleteAccount { [weak self] in
                self?.setLoading(false)
                self?.navigateToLoginScreen()
            }
        }
    }
}
