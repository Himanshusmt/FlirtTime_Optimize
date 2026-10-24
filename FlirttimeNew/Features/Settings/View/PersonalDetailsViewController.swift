//
//  PersonalDetailsViewController.swift
//  FlirttimeNew
//

import UIKit
import Combine
import CoreLocation
import MapKit

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

    /// Email and phone can be added once. After that the pencil stays hidden.
    private var emailEditor: RowEditor?
    private var phoneEditor: RowEditor?

    override func viewDidLoad() {
        super.viewDidLoad()
        noteLabel.superview?.superview?.isHidden = true
        makeRowEditable(fullNameLabel, hint: "Edit your full name", action: #selector(editNameTapped))
        makeRowEditable(usernameLabel, hint: "Edit your username", action: #selector(editUsernameTapped))
        emailEditor = makeOptionalRow(emailLabel, hint: "Add your email", action: #selector(editEmailTapped))
        phoneEditor = makeOptionalRow(phoneLabel, hint: "Add your phone number", action: #selector(editPhoneTapped))
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
            let email = Self.trimmed(user.email)
            let phone = Self.trimmed(user.phone)
            self.emailLabel.text = Self.valueOrPlaceholder(email)
            self.phoneLabel.text = Self.valueOrPlaceholder(phone)
            self.emailEditor?.setEditable(email.isEmpty)
            self.phoneEditor?.setEditable(phone.isEmpty)
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

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func valueOrPlaceholder(_ value: String?) -> String {
        let trimmed = trimmed(value)
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
        makeOptionalRow(label, hint: hint, action: action)?.setEditable(true)
    }

    /// Pencil stays hidden until `setEditable(true)`. Used for email and phone, which can only be added once.
    private func makeOptionalRow(_ label: UILabel, hint: String, action: Selector) -> RowEditor? {
        guard let textStack = label.superview, let row = textStack.superview else { return nil }

        let pencil = UIImageView(image: UIImage(systemName: "pencil"))
        pencil.tintColor = AppColor.Punch
        pencil.contentMode = .scaleAspectFit
        pencil.translatesAutoresizingMaskIntoConstraints = false
        pencil.isHidden = true
        row.addSubview(pencil)

        let lockedTrailing = row.constraints.filter {
            ($0.firstItem === row && $0.secondItem === textStack && $0.firstAttribute == .trailing)
                || ($0.firstItem === textStack && $0.secondItem === row && $0.firstAttribute == .trailing)
        }
        lockedTrailing.forEach { $0.isActive = false }

        let editableTrailing = textStack.trailingAnchor.constraint(equalTo: pencil.leadingAnchor, constant: -10)
        NSLayoutConstraint.activate([
            pencil.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            pencil.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            pencil.widthAnchor.constraint(equalToConstant: 18),
            pencil.heightAnchor.constraint(equalToConstant: 18)
        ])

        let gesture = UITapGestureRecognizer(target: self, action: action)
        gesture.isEnabled = false
        row.addGestureRecognizer(gesture)

        let editor = RowEditor(row: row,
                               pencil: pencil,
                               gesture: gesture,
                               hint: hint,
                               lockedTrailing: lockedTrailing,
                               editableTrailing: editableTrailing)
        editor.setEditable(false)
        return editor
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
            if let error = Self.usernameValidationError(username) {
                self.showNewAlertPopUp(Title: "Username", Msg: error, isSuccess: false) { _ in }
                return
            }
            self.setLoading(true)
            self.viewModel.checkUsernameAvailability(username) { [weak self] available, message in
                guard let self else { return }
                self.setLoading(false)
                if available {
                    self.save(["username": username], message: "Username updated")
                } else {
                    self.showNewAlertPopUp(Title: "Username", Msg: message ?? "This username is already taken", isSuccess: false) { _ in }
                }
            }
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
        guard Self.trimmed(viewModel.appUser?.email).isEmpty else { return }
        openChangeContact(.email)
    }

    @objc private func editPhoneTapped() {
        guard Self.trimmed(viewModel.appUser?.phone).isEmpty else { return }
        openChangeContact(.phone)
    }

    private func openChangeContact(_ kind: SettingsViewModel.ContactKind) {
        let changeViewController = ChangeEmailViewController.instantiateFromStoryboard()
        changeViewController.kind = kind
        navigationController?.pushViewController(changeViewController, animated: true)
    }

    // MARK: - Location

    @objc private func editLocationTapped() {
        let sheet = EditLocationSheetViewController()
        sheet.onUseCurrentLocation = { [weak self, weak sheet] in
            self?.useCurrentLocation(from: sheet)
        }
        sheet.onSaveCity = { [weak self, weak sheet] city in
            self?.saveEnteredCity(city, from: sheet)
        }
        sheet.onSelectPlacemark = { [weak self, weak sheet] placemark in
            sheet?.dismiss(animated: true) {
                self?.saveLocation(placemark, fallback: placemark.location)
            }
        }
        present(sheet, animated: true)
    }

    private func useCurrentLocation(from sheet: EditLocationSheetViewController?) {
        let service = LocationService.shared
        sheet?.setBusy(true)
        service.requestLocationPermission { [weak self, weak sheet] granted in
            guard let self else { return }
            guard granted else {
                sheet?.setBusy(false)
                self.showNewAlertPopUp(Title: "Location", Msg: "Allow location access in Settings to use your current location.", isSuccess: false) { _ in }
                return
            }
            service.getCurrentLocation { [weak self, weak sheet] location, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard let location else {
                        sheet?.setBusy(false)
                        self.showNewAlertPopUp(Title: "Location", Msg: "Couldn't find your location. Please try again or enter a city.", isSuccess: false) { _ in }
                        return
                    }
                    CLGeocoder().reverseGeocodeLocation(location) { [weak self, weak sheet] placemarks, _ in
                        DispatchQueue.main.async {
                            sheet?.setBusy(false)
                            sheet?.dismiss(animated: true) {
                                self?.saveLocation(placemarks?.first, fallback: location)
                            }
                        }
                    }
                }
            }
        }
    }

    private func saveEnteredCity(_ city: String, from sheet: EditLocationSheetViewController?) {
        sheet?.setBusy(true)
        CLGeocoder().geocodeAddressString(city) { [weak self, weak sheet] placemarks, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                sheet?.setBusy(false)
                guard let placemark = placemarks?.first else {
                    self.showNewAlertPopUp(Title: "Location", Msg: "We couldn't find \"\(city)\". Please check the spelling.", isSuccess: false) { _ in }
                    return
                }
                sheet?.dismiss(animated: true) {
                    self.saveLocation(placemark, fallback: nil)
                }
            }
        }
    }

    /// Saves "City, State, Country" with its coordinates.
    private func saveLocation(_ placemark: CLPlacemark?, fallback: CLLocation?) {
        guard let coordinate = (placemark?.location ?? fallback)?.coordinate else {
            showNewAlertPopUp(Title: "Location", Msg: "Couldn't find that place. Please try again.", isSuccess: false) { _ in }
            return
        }
        let parts = [
            placemark?.locality ?? placemark?.subAdministrativeArea,
            placemark?.administrativeArea,
            placemark?.country
        ]
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
            self.viewModel.deleteAccount { [weak self] success in
                guard let self else { return }
                self.setLoading(false)
                guard success else { return }
                self.navigateToLoginScreen()
            }
        }
    }
}

/// Bottom sheet for updating location — current GPS or type a city with live suggestions.
private final class EditLocationSheetViewController: UIViewController, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate, MKLocalSearchCompleterDelegate {

    private static let rowHeight: CGFloat = 58
    private static let maxSuggestionRows = 5

    var onUseCurrentLocation: (() -> Void)?
    var onSaveCity: ((String) -> Void)?
    var onSelectPlacemark: ((CLPlacemark) -> Void)?

    private let cityField = UITextField()
    private let cityFieldWrap = UIView()
    private let saveButton = UIButton(type: .system)
    private let busyOverlay = UIActivityIndicatorView(style: .large)
    private let suggestionsTable = UITableView(frame: .zero, style: .plain)
    private var suggestionsHeightConstraint: NSLayoutConstraint?
    private let contentStack = UIStackView()
    private let scrollView = UIScrollView()

    private let completer = MKLocalSearchCompleter()
    private var completions: [MKLocalSearchCompletion] = []
    private var resolveSearch: MKLocalSearch?

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        buildUI()
        configureCompleter()
        configureSheetDetents()
        updateSaveButton()
        updateSuggestionsUI(animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        completer.delegate = nil
        completer.cancel()
        resolveSearch?.cancel()
    }

    func setBusy(_ busy: Bool) {
        view.isUserInteractionEnabled = !busy
        if busy {
            busyOverlay.startAnimating()
        } else {
            busyOverlay.stopAnimating()
        }
    }

    private func configureCompleter() {
        completer.delegate = self
        completer.resultTypes = .address
    }

    private func configureSheetDetents() {
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = [.large()]
        sheet.selectedDetentIdentifier = .large
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 28
    }

    private func buildUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let iconTile = makeIconTile(systemName: "mappin.and.ellipse",
                                    tint: AppColor.ElectricViolet,
                                    background: UIColor(red: 0.945, green: 0.918, blue: 1, alpha: 1),
                                    size: 56,
                                    cornerRadius: 28,
                                    symbolSize: 22)
        let titleLabel = UILabel()
        titleLabel.text = "Update location"
        titleLabel.font = UIFont(name: "Fredoka-SemiBold", size: 22) ?? .boldSystemFont(ofSize: 22)
        titleLabel.textColor = AppColor.MineShaft
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "People nearby see you based on this."
        subtitleLabel.font = UIFont(name: "Fredoka-Regular", size: 14) ?? .systemFont(ofSize: 14)
        subtitleLabel.textColor = AppColor.Boulder
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let hero = UIStackView(arrangedSubviews: [iconTile, titleLabel, subtitleLabel])
        hero.axis = .vertical
        hero.alignment = .center
        hero.spacing = 10
        contentStack.addArrangedSubview(hero)
        contentStack.addArrangedSubview(makeUseCurrentButton())
        contentStack.addArrangedSubview(makeOrDivider())
        contentStack.addArrangedSubview(makeCitySection())

        saveButton.setTitle("Save city", for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.titleLabel?.font = UIFont(name: "Fredoka-SemiBold", size: 17) ?? .boldSystemFont(ofSize: 17)
        saveButton.backgroundColor = AppColor.Punch
        saveButton.layer.cornerRadius = 25
        saveButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(saveButton)

        busyOverlay.hidesWhenStopped = true
        busyOverlay.translatesAutoresizingMaskIntoConstraints = false
        busyOverlay.color = AppColor.Punch
        view.addSubview(busyOverlay)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),

            busyOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            busyOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func makeCitySection() -> UIView {
        let cityCaption = UILabel()
        cityCaption.text = "Enter a city"
        cityCaption.font = UIFont(name: "Fredoka-Medium", size: 14) ?? .systemFont(ofSize: 14, weight: .medium)
        cityCaption.textColor = AppColor.MineShaft

        cityFieldWrap.backgroundColor = AppColor.AthensGray
        cityFieldWrap.layer.cornerRadius = 16
        cityFieldWrap.layer.borderWidth = 1.5
        cityFieldWrap.layer.borderColor = AppColor.Iron.cgColor
        cityFieldWrap.translatesAutoresizingMaskIntoConstraints = false
        cityFieldWrap.heightAnchor.constraint(equalToConstant: 56).isActive = true

        cityField.placeholder = "e.g. Mumbai, Indore"
        cityField.font = UIFont(name: "Fredoka-Medium", size: 16) ?? .systemFont(ofSize: 16, weight: .medium)
        cityField.textColor = AppColor.MineShaft
        cityField.autocapitalizationType = .words
        cityField.autocorrectionType = .no
        cityField.textContentType = .addressCity
        cityField.clearButtonMode = .whileEditing
        cityField.returnKeyType = .done
        cityField.delegate = self
        cityField.addTarget(self, action: #selector(cityChanged), for: .editingChanged)
        cityField.translatesAutoresizingMaskIntoConstraints = false
        cityFieldWrap.addSubview(cityField)
        NSLayoutConstraint.activate([
            cityField.leadingAnchor.constraint(equalTo: cityFieldWrap.leadingAnchor, constant: 16),
            cityField.trailingAnchor.constraint(equalTo: cityFieldWrap.trailingAnchor, constant: -16),
            cityField.centerYAnchor.constraint(equalTo: cityFieldWrap.centerYAnchor)
        ])

        suggestionsTable.translatesAutoresizingMaskIntoConstraints = false
        suggestionsTable.dataSource = self
        suggestionsTable.delegate = self
        suggestionsTable.backgroundColor = AppColor.AppWhite
        suggestionsTable.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 16)
        suggestionsTable.separatorColor = AppColor.Iron
        suggestionsTable.rowHeight = Self.rowHeight
        suggestionsTable.isScrollEnabled = false
        suggestionsTable.layer.cornerRadius = 16
        suggestionsTable.layer.borderWidth = 1
        suggestionsTable.layer.borderColor = AppColor.Iron.cgColor
        suggestionsTable.clipsToBounds = true
        suggestionsTable.register(UITableViewCell.self, forCellReuseIdentifier: "CitySuggestion")
        let height = suggestionsTable.heightAnchor.constraint(equalToConstant: 0)
        height.isActive = true
        suggestionsHeightConstraint = height

        let stack = UIStackView(arrangedSubviews: [cityCaption, cityFieldWrap, suggestionsTable])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func makeIconTile(systemName: String,
                              tint: UIColor,
                              background: UIColor,
                              size: CGFloat,
                              cornerRadius: CGFloat,
                              symbolSize: CGFloat) -> UIView {
        let tile = UIView()
        tile.backgroundColor = background
        tile.layer.cornerRadius = cornerRadius
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.widthAnchor.constraint(equalToConstant: size).isActive = true
        tile.heightAnchor.constraint(equalToConstant: size).isActive = true

        let image = UIImageView(image: UIImage(systemName: systemName))
        image.tintColor = tint
        image.contentMode = .scaleAspectFit
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
        image.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(image)
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: tile.centerYAnchor)
        ])
        return tile
    }

    private func makeUseCurrentButton() -> UIControl {
        let button = UIControl()
        button.backgroundColor = AppColor.AppWhite
        button.layer.cornerRadius = 18
        button.layer.borderWidth = 1.5
        button.layer.borderColor = AppColor.Iron.cgColor
        button.addTarget(self, action: #selector(useCurrentTapped), for: .touchUpInside)
        button.addTarget(self, action: #selector(currentLocationPressed(_:)), for: [.touchDown, .touchDragEnter])
        button.addTarget(self, action: #selector(currentLocationReleased(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])

        let icon = makeIconTile(systemName: "location.fill",
                                tint: AppColor.BlueRibbon,
                                background: UIColor(red: 0.906, green: 0.941, blue: 1, alpha: 1),
                                size: 40,
                                cornerRadius: 12.8,
                                symbolSize: 16)
        icon.isUserInteractionEnabled = false

        let title = UILabel()
        title.text = "Use my current location"
        title.font = UIFont(name: "Fredoka-Medium", size: 16) ?? .systemFont(ofSize: 16, weight: .medium)
        title.textColor = AppColor.MineShaft

        let subtitle = UILabel()
        subtitle.text = "We'll fill your city from GPS"
        subtitle.font = UIFont(name: "Fredoka-Regular", size: 13) ?? .systemFont(ofSize: 13)
        subtitle.textColor = AppColor.Boulder

        let textStack = UIStackView(arrangedSubviews: [title, subtitle])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.isUserInteractionEnabled = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = AppColor.Silver
        chevron.contentMode = .scaleAspectFit
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(weight: .bold)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.widthAnchor.constraint(equalToConstant: 9).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 15).isActive = true
        chevron.isUserInteractionEnabled = false

        let row = UIStackView(arrangedSubviews: [icon, textStack, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: button.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -14),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 68)
        ])
        return button
    }

    private func makeOrDivider() -> UIView {
        let wrap = UIView()
        let line1 = UIView()
        line1.backgroundColor = AppColor.Iron
        let line2 = UIView()
        line2.backgroundColor = AppColor.Iron
        let label = UILabel()
        label.text = "or"
        label.font = UIFont(name: "Fredoka-Regular", size: 13) ?? .systemFont(ofSize: 13)
        label.textColor = AppColor.Boulder
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [line1, label, line2])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            line1.heightAnchor.constraint(equalToConstant: 1),
            line2.heightAnchor.constraint(equalToConstant: 1),
            line1.widthAnchor.constraint(equalTo: line2.widthAnchor)
        ])
        return wrap
    }

    private var query: String {
        cityField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func updateSaveButton() {
        let enabled = query.count >= 2
        saveButton.isEnabled = enabled
        saveButton.alpha = enabled ? 1 : 0.45
    }

    private func updateSuggestionsUI(animated: Bool) {
        let rows = min(completions.count, Self.maxSuggestionRows)
        let height = CGFloat(rows) * Self.rowHeight
        suggestionsTable.isHidden = rows == 0
        let changes = {
            self.suggestionsHeightConstraint?.constant = height
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }

    @objc private func cityChanged() {
        updateSaveButton()
        let focused = cityField.isFirstResponder
        UIView.animate(withDuration: 0.2) {
            self.cityFieldWrap.layer.borderColor = (focused ? AppColor.Punch : AppColor.Iron).cgColor
        }
        let text = query
        if text.count < 2 {
            completions = []
            suggestionsTable.reloadData()
            updateSuggestionsUI(animated: true)
            completer.cancel()
            return
        }
        completer.queryFragment = text
    }

    @objc private func useCurrentTapped() {
        view.endEditing(true)
        onUseCurrentLocation?()
    }

    @objc private func saveTapped() {
        guard query.count >= 2 else { return }
        view.endEditing(true)
        onSaveCity?(query)
    }

    @objc private func currentLocationPressed(_ sender: UIControl) {
        UIView.animate(withDuration: 0.12) { sender.backgroundColor = AppColor.AthensGray }
    }

    @objc private func currentLocationReleased(_ sender: UIControl) {
        UIView.animate(withDuration: 0.15) { sender.backgroundColor = AppColor.AppWhite }
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let inView = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - inView.minY)
        scrollView.contentInset.bottom = overlap + 12
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        view.endEditing(true)
        cityField.text = completion.title
        updateSaveButton()
        setBusy(true)
        resolveSearch?.cancel()
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        resolveSearch = search
        search.start { [weak self] response, _ in
            guard let self, search === self.resolveSearch else { return }
            self.resolveSearch = nil
            self.setBusy(false)
            if let placemark = response?.mapItems.first?.placemark {
                self.onSelectPlacemark?(placemark)
            } else {
                let fallback = [completion.title, completion.subtitle]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                self.onSaveCity?(fallback.isEmpty ? completion.title : fallback)
            }
        }
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        min(completions.count, Self.maxSuggestionRows)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CitySuggestion", for: indexPath)
        var config = cell.defaultContentConfiguration()
        let item = completions[indexPath.row]
        config.text = item.title
        config.secondaryText = item.subtitle.isEmpty ? nil : item.subtitle
        config.textProperties.font = UIFont(name: "Fredoka-Medium", size: 15) ?? .systemFont(ofSize: 15, weight: .medium)
        config.textProperties.color = AppColor.MineShaft
        config.secondaryTextProperties.font = UIFont(name: "Fredoka-Regular", size: 12) ?? .systemFont(ofSize: 12)
        config.secondaryTextProperties.color = AppColor.Boulder
        config.image = UIImage(systemName: "mappin.circle.fill")
        config.imageProperties.tintColor = AppColor.ElectricViolet
        config.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        cell.contentConfiguration = config
        cell.backgroundColor = AppColor.AppWhite
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard completions.indices.contains(indexPath.row) else { return }
        selectCompletion(completions[indexPath.row])
    }

    // MARK: - Completer

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard query.count >= 2 else { return }
        completions = completer.results
        suggestionsTable.reloadData()
        updateSuggestionsUI(animated: true)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
        suggestionsTable.reloadData()
        updateSuggestionsUI(animated: true)
    }

    // MARK: - Text field

    func textFieldDidBeginEditing(_ textField: UITextField) {
        cityFieldWrap.layer.borderColor = AppColor.Punch.cgColor
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        cityFieldWrap.layer.borderColor = AppColor.Iron.cgColor
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if saveButton.isEnabled { saveTapped() }
        else { textField.resignFirstResponder() }
        return true
    }
}

/// Pencil and tap for a personal-details row that can be locked after a value is saved.
private final class RowEditor {
    let row: UIView
    let pencil: UIImageView
    let gesture: UITapGestureRecognizer
    let hint: String
    let lockedTrailing: [NSLayoutConstraint]
    let editableTrailing: NSLayoutConstraint

    init(row: UIView,
         pencil: UIImageView,
         gesture: UITapGestureRecognizer,
         hint: String,
         lockedTrailing: [NSLayoutConstraint],
         editableTrailing: NSLayoutConstraint) {
        self.row = row
        self.pencil = pencil
        self.gesture = gesture
        self.hint = hint
        self.lockedTrailing = lockedTrailing
        self.editableTrailing = editableTrailing
    }

    func setEditable(_ editable: Bool) {
        pencil.isHidden = !editable
        gesture.isEnabled = editable
        if editable {
            lockedTrailing.forEach { $0.isActive = false }
            editableTrailing.isActive = true
            row.accessibilityTraits.insert(.button)
            row.accessibilityHint = hint
        } else {
            editableTrailing.isActive = false
            lockedTrailing.forEach { $0.isActive = true }
            row.accessibilityTraits.remove(.button)
            row.accessibilityHint = nil
        }
    }
}
