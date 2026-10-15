//
//  PersonalDetailsViewController.swift
//  FlirttimeNew
//

import UIKit
import Combine
import CoreLocation

final class PersonalDetailsViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    @IBOutlet private weak var fullNameLabel: UILabel!
    @IBOutlet private weak var usernameLabel: UILabel!
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
    private static let usernameLength = 3...30
    private static let minimumAge = 18

    override func viewDidLoad() {
        super.viewDidLoad()
        noteLabel.superview?.superview?.isHidden = true
        makeRowEditable(fullNameLabel, hint: "Edit your full name", action: #selector(editNameTapped))
        makeRowEditable(usernameLabel, hint: "Edit your username", action: #selector(editUsernameTapped))
        makeRowEditable(emailLabel, hint: "Change your email", action: #selector(editEmailTapped))
        makeRowEditable(phoneLabel, hint: "Change your phone number", action: #selector(editPhoneTapped))
        makeRowEditable(dobLabel, hint: "Change your date of birth", action: #selector(editDateOfBirthTapped))
        makeRowEditable(locationLabel, hint: "Change your location", action: #selector(editLocationTapped))
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
            self.usernameLabel.text = Self.valueOrPlaceholder(Self.username(of: user))
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

    /// Saved as `username`; falls back to the nickname.
    private static func username(of user: AppUser) -> String? {
        [user.username, user.nickName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    // MARK: - Editable rows

    /// Adds a pencil to the row holding `label` and calls `action` on tap.
    private func makeRowEditable(_ label: UILabel, hint: String, action: Selector) {
        guard let textStack = label.superview, let row = textStack.superview else { return }

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
        row.accessibilityHint = hint
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: action))
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
        save(["fullName": name], message: "Name updated")
    }

    private func save(_ fields: [String: Any], message: String) {
        setLoading(true)
        viewModel.updateProfile(fields) { [weak self] success in
            guard let self else { return }
            self.setLoading(false)
            if success {
                self.aCustomToastView.show(message: message)
            }
        }
    }

    // MARK: - Username

    @objc private func editUsernameTapped() {
        let current = viewModel.appUser.flatMap(Self.username(of:)) ?? ""
        let alert = UIAlertController(title: "Username", message: "This is the name people see on your profile.", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = current
            field.placeholder = "Your username"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.textContentType = .nickname
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let username = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard username != current else { return }
            guard let error = Self.usernameValidationError(username) else {
                self.save(["username": username], message: "Username updated")
                return
            }
            self.showNewAlertPopUp(Title: "Username", Msg: error, isSuccess: false) { _ in }
        })
        present(alert, animated: true)
    }

    private static func usernameValidationError(_ username: String) -> String? {
        guard usernameLength.contains(username.count) else {
            return "Username must be \(usernameLength.lowerBound) to \(usernameLength.upperBound) characters."
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._"))
        guard username.unicodeScalars.allSatisfy(allowed.contains) else {
            return "Username can only contain letters, numbers, dots and underscores."
        }
        return nil
    }

    // MARK: - Email / phone

    @objc private func editEmailTapped() {
        openChangeContact(.email)
    }

    @objc private func editPhoneTapped() {
        openChangeContact(.phone)
    }

    private func openChangeContact(_ kind: SettingsViewModel.ContactKind) {
        let changeViewController = ChangeEmailViewController.instantiateFromStoryboard()
        changeViewController.kind = kind
        navigationController?.pushViewController(changeViewController, animated: true)
    }

    // MARK: - Date of birth

    @objc private func editDateOfBirthTapped() {
        let calendar = Calendar.current
        let latest = calendar.date(byAdding: .year, value: -Self.minimumAge, to: Date()) ?? Date()
        let current = viewModel.appUser?.dateOfBirth
            .map { String($0.prefix(10)) }
            .flatMap(Self.apiDateFormatter.date(from:))

        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .wheels
        picker.maximumDate = latest
        picker.minimumDate = calendar.date(byAdding: .year, value: -100, to: Date())
        picker.date = min(current ?? latest, latest)

        let sheet = UIViewController()
        sheet.view.backgroundColor = .systemBackground
        let titleLabel = UILabel()
        titleLabel.text = "Date of birth"
        titleLabel.font = UIFont(name: "Fredoka-SemiBold", size: 18) ?? .boldSystemFont(ofSize: 18)
        let note = UILabel()
        note.text = "You must be at least \(Self.minimumAge) to use Flirt Time."
        note.font = UIFont(name: "Fredoka-Regular", size: 14) ?? .systemFont(ofSize: 14)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        let saveButton = UIButton(type: .system)
        saveButton.setTitle("Save", for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.titleLabel?.font = UIFont(name: "Fredoka-SemiBold", size: 17) ?? .boldSystemFont(ofSize: 17)
        saveButton.backgroundColor = AppColor.Punch
        saveButton.layer.cornerRadius = 25
        saveButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        saveButton.addAction(UIAction { [weak self, weak sheet, weak picker] _ in
            guard let self, let picker else { return }
            let chosen = Self.apiDateFormatter.string(from: picker.date)
            sheet?.dismiss(animated: true)
            guard chosen != current.map(Self.apiDateFormatter.string(from:)) else { return }
            self.save(["dateOfBirth": chosen], message: "Date of birth updated")
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, note, picker, saveButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sheet.view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: sheet.view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: sheet.view.trailingAnchor, constant: -20)
        ])

        sheet.sheetPresentationController?.detents = [.medium()]
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        present(sheet, animated: true)
    }

    // MARK: - Location

    @objc private func editLocationTapped() {
        let sheet = UIAlertController(title: "Location", message: "People nearby see you based on this.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Use my current location", style: .default) { [weak self] _ in
            self?.useCurrentLocation()
        })
        sheet.addAction(UIAlertAction(title: "Enter a city", style: .default) { [weak self] _ in
            self?.enterCity()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    private func useCurrentLocation() {
        let service = LocationService.shared
        setLoading(true)
        service.requestLocationPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.setLoading(false)
                self.showNewAlertPopUp(Title: "Location", Msg: "Allow location access in Settings to use your current location.", isSuccess: false) { _ in }
                return
            }
            service.getCurrentLocation { [weak self] location, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard let location else {
                        self.setLoading(false)
                        self.showNewAlertPopUp(Title: "Location", Msg: "Couldn't find your location. Please try again or enter a city.", isSuccess: false) { _ in }
                        return
                    }
                    CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                        DispatchQueue.main.async {
                            self?.setLoading(false)
                            self?.saveLocation(placemarks?.first, fallback: location)
                        }
                    }
                }
            }
        }
    }

    private func enterCity() {
        let alert = UIAlertController(title: "Enter a city", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "e.g. Mumbai"
            field.autocapitalizationType = .words
            field.textContentType = .addressCity
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let city = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard city.count >= 2 else {
                self.showNewAlertPopUp(Title: "Location", Msg: "Please enter a city name.", isSuccess: false) { _ in }
                return
            }
            self.setLoading(true)
            CLGeocoder().geocodeAddressString(city) { [weak self] placemarks, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setLoading(false)
                    guard let placemark = placemarks?.first else {
                        self.showNewAlertPopUp(Title: "Location", Msg: "We couldn't find \"\(city)\". Please check the spelling.", isSuccess: false) { _ in }
                        return
                    }
                    self.saveLocation(placemark, fallback: nil)
                }
            }
        })
        present(alert, animated: true)
    }

    /// Saves "City, State" with its coordinates.
    private func saveLocation(_ placemark: CLPlacemark?, fallback: CLLocation?) {
        guard let coordinate = (placemark?.location ?? fallback)?.coordinate else {
            showNewAlertPopUp(Title: "Location", Msg: "Couldn't find that place. Please try again.", isSuccess: false) { _ in }
            return
        }
        let parts = [placemark?.locality ?? placemark?.subAdministrativeArea, placemark?.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        guard !unique.isEmpty else {
            showNewAlertPopUp(Title: "Location", Msg: "Couldn't find a city for that place. Please enter a city.", isSuccess: false) { _ in }
            return
        }
        save(["location": unique.joined(separator: ", "),
              "latitude": coordinate.latitude,
              "longitude": coordinate.longitude],
             message: "Location updated")
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
