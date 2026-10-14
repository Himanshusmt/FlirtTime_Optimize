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
    @IBOutlet private weak var noteLabel: UILabel!

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

    private static let nameMaxLength = 50

    override func viewDidLoad() {
        super.viewDidLoad()
        noteLabel.text = "Date of birth and location can't be changed. Email and phone changes are coming soon."
        makeNameRowEditable()
        setBinding()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        viewModel.loadProfile()
    }

    private func setBinding() {
        viewModel.$appUser.receive(on: DispatchQueue.main).sink { [weak self] user in
            guard let self, let user else { return }
            self.fullNameLabel.text = Self.valueOrPlaceholder(Self.fullName(of: user))
            self.emailLabel.text = Self.valueOrPlaceholder(user.email)
            self.phoneLabel.text = Self.valueOrPlaceholder(user.phone)
            self.dobLabel.text = Self.valueOrPlaceholder(user.dateOfBirth
                .map { String($0.prefix(10)) }
                .flatMap(Self.apiDateFormatter.date(from:))
                .map(Self.displayDateFormatter.string(from:)))
            self.locationLabel.text = Self.valueOrPlaceholder(user.city)
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

    private static func fullName(of user: AppUser) -> String? {
        if let fullName = user.fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty {
            return fullName
        }
        let parts = [user.firstName, user.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Name

    /// Adds a pencil to the Full name row and opens the editor on tap.
    private func makeNameRowEditable() {
        guard let textStack = fullNameLabel.superview, let row = textStack.superview else { return }

        let pencil = UIImageView(image: UIImage(systemName: "pencil"))
        pencil.tintColor = AppColor.Punch
        pencil.contentMode = .scaleAspectFit
        pencil.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(pencil)

        row.constraints
            .filter { ($0.firstItem === row && $0.secondItem === textStack && $0.firstAttribute == .trailing)
                || ($0.firstItem === textStack && $0.secondItem === row && $0.firstAttribute == .trailing) }
            .forEach { $0.isActive = false }

        NSLayoutConstraint.activate([
            pencil.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            pencil.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            pencil.widthAnchor.constraint(equalToConstant: 18),
            pencil.heightAnchor.constraint(equalToConstant: 18),
            textStack.trailingAnchor.constraint(equalTo: pencil.leadingAnchor, constant: -10)
        ])

        row.isUserInteractionEnabled = true
        row.accessibilityTraits.insert(.button)
        row.accessibilityHint = "Edit your full name"
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(editNameTapped)))
    }

    @objc private func editNameTapped() {
        let current = viewModel.appUser.flatMap(Self.fullName(of:)) ?? ""
        let alert = UIAlertController(title: "Full name", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = current
            field.placeholder = "Your full name"
            field.autocapitalizationType = .words
            field.textContentType = .name
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard name != current else { return }
            guard let error = Self.nameValidationError(name) else {
                self.saveName(name)
                return
            }
            self.showNewAlertPopUp(Title: "Full name", Msg: error, isSuccess: false) { _ in }
        })
        present(alert, animated: true)
    }

    private static func nameValidationError(_ name: String) -> String? {
        guard name.count >= 2 else { return "Please enter at least 2 characters." }
        guard name.count <= nameMaxLength else { return "Name can be at most \(nameMaxLength) characters." }
        let allowed = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: ".'-"))
        guard name.unicodeScalars.allSatisfy(allowed.contains) else {
            return "Name can only contain letters, spaces, dots, apostrophes and hyphens."
        }
        return nil
    }

    private func saveName(_ name: String) {
        setLoading(true)
        viewModel.updateFullName(name) { [weak self] success in
            guard let self else { return }
            self.setLoading(false)
            if success {
                self.aCustomToastView.show(message: "Name updated")
            }
        }
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
