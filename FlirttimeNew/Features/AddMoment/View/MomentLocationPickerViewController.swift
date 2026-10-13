//
//  MomentLocationPickerViewController.swift
//  FlirttimeNew
//
//  "Where are you vibing?" sheet for Add Moment. Nearby date spots, categories and search
//  all come from Apple Maps; "Share my city" tags the user's city, never an exact address.
//

import UIKit
import MapKit
import CoreLocation

struct MomentPlace: Equatable {
    let name: String
    /// Secondary line shown in the picker (area, region, country).
    let detail: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?

    /// Short text saved on the moment and shown in the feed, e.g. "Blue Tokai, Mumbai".
    var displayText: String {
        guard let city, !city.isEmpty, !name.localizedCaseInsensitiveContains(city) else { return name }
        return "\(name), \(city)"
    }
}

/// Quick filters shown under the search field.
private struct DateSpotCategory {
    let title: String
    let symbol: String
    let query: String
    let categories: [MKPointOfInterestCategory]

    static let all: [DateSpotCategory] = [
        DateSpotCategory(title: "Coffee", symbol: "cup.and.saucer.fill", query: "coffee", categories: [.cafe, .bakery]),
        DateSpotCategory(title: "Drinks", symbol: "wineglass.fill", query: "bar", categories: [.nightlife, .brewery, .winery]),
        DateSpotCategory(title: "Dinner", symbol: "fork.knife", query: "restaurant", categories: [.restaurant]),
        DateSpotCategory(title: "Outdoors", symbol: "leaf.fill", query: "park", categories: [.park, .beach, .nationalPark]),
        DateSpotCategory(title: "Movies", symbol: "film.fill", query: "cinema", categories: [.movieTheater]),
        DateSpotCategory(title: "Culture", symbol: "theatermasks.fill", query: "museum", categories: [.museum, .theater])
    ]

    static var everything: [MKPointOfInterestCategory] {
        all.flatMap(\.categories)
    }
}

/// Icon and tint for a place, based on its Apple Maps category.
private enum PlaceStyle {
    static func icon(for category: MKPointOfInterestCategory?) -> (symbol: String, tint: UIColor) {
        switch category {
        case .cafe?, .bakery?: return ("cup.and.saucer.fill", AppColor.Cherrywood)
        case .nightlife?, .brewery?, .winery?: return ("wineglass.fill", AppColor.ElectricViolet)
        case .restaurant?, .foodMarket?: return ("fork.knife", AppColor.Punch)
        case .park?, .nationalPark?: return ("leaf.fill", AppColor.OceanGreen)
        case .beach?: return ("beach.umbrella.fill", AppColor.DodgerBlue)
        case .movieTheater?: return ("film.fill", AppColor.MineShaft)
        case .museum?, .theater?: return ("theatermasks.fill", AppColor.Amaranth)
        case .fitnessCenter?: return ("figure.run", AppColor.OceanGreen)
        case .store?: return ("bag.fill", AppColor.BrightSun)
        default: return ("mappin", AppColor.Punch)
        }
    }
}

final class MomentLocationPickerViewController: BaseViewController {

    var onPick: ((MomentPlace) -> Void)?

    private enum Section {
        case shareCity
        case places
    }

    private enum PlaceItem {
        case completion(MKLocalSearchCompletion)
        case mapItem(MKMapItem)
    }

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let searchField = UISearchTextField()
    private let categoryScroll = UIScrollView()
    private let categoryStack = UIStackView()
    private var categoryChips: [MomentChip] = []
    private let tableView = UITableView(frame: .zero, style: .plain)

    private let completer = MKLocalSearchCompleter()
    private var completions: [MKLocalSearchCompletion] = []
    private var nearbyItems: [MKMapItem] = []
    private var selectedCategory: Int?
    private var userLocation: CLLocation?
    private var nearbySearch: MKLocalSearch?
    private var resolveSearch: MKLocalSearch?
    private var isLoadingNearby = false
    private var isLocating = false
    private var resolvingIndexPath: IndexPath?

    private let distanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    private var query: String {
        (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let sections: [Section] = [.shareCity, .places]

    private var placeItems: [PlaceItem] {
        query.isEmpty ? nearbyItems.map(PlaceItem.mapItem) : completions.map(PlaceItem.completion)
    }

    /// Presents the picker as a resizable sheet.
    static func present(from presenter: UIViewController, onPick: @escaping (MomentPlace) -> Void) {
        let picker = MomentLocationPickerViewController()
        picker.onPick = onPick
        picker.modalPresentationStyle = .pageSheet
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        presenter.present(picker, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUpHeader()
        setUpSearchField()
        setUpCategories()
        setUpTableView()
        setUpCompleter()
        loadInitialSpots()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        completer.cancel()
        let searches = [nearbySearch, resolveSearch]
        nearbySearch = nil
        resolveSearch = nil
        searches.forEach { $0?.cancel() }
    }

    // MARK: - Setup

    private func setUpHeader() {
        titleLabel.text = "Where are you vibing?"
        titleLabel.font = .fredoka(.bold, size: 22)
        titleLabel.textColor = AppColor.MineShaft

        subtitleLabel.text = "Tag a spot so people nearby can find your moment"
        subtitleLabel.font = .fredoka(.regular, size: 13)
        subtitleLabel.textColor = AppColor.DoveGray
        subtitleLabel.numberOfLines = 0

        closeButton.setImage(UIImage(systemName: "xmark",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
        closeButton.tintColor = AppColor.MineShaft
        closeButton.backgroundColor = AppColor.WildSand
        closeButton.layer.cornerRadius = 16
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        [titleLabel, subtitleLabel, closeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func setUpSearchField() {
        searchField.placeholder = "Search cafés, bars, parks…"
        searchField.font = .fredoka(.regular, size: 15)
        searchField.textColor = AppColor.MineShaft
        searchField.tintColor = AppColor.Punch
        searchField.backgroundColor = AppColor.WildSand
        searchField.layer.cornerRadius = 23
        searchField.clipsToBounds = true
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        if let glass = searchField.leftView as? UIImageView {
            glass.tintColor = AppColor.Punch
        }
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func setUpCategories() {
        categoryScroll.showsHorizontalScrollIndicator = false
        categoryScroll.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        categoryScroll.clipsToBounds = false
        categoryStack.axis = .horizontal
        categoryStack.spacing = 8
        categoryStack.alignment = .center

        for (index, category) in DateSpotCategory.all.enumerated() {
            let chip = MomentChip(title: category.title, symbol: category.symbol, style: .outline, height: 36)
            chip.accessibilityHint = "Double tap to show \(category.title.lowercased()) spots nearby"
            chip.addAction(UIAction { [weak self] _ in self?.categoryTapped(at: index) }, for: .touchUpInside)
            categoryChips.append(chip)
            categoryStack.addArrangedSubview(chip)
        }

        categoryScroll.translatesAutoresizingMaskIntoConstraints = false
        categoryStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(categoryScroll)
        categoryScroll.addSubview(categoryStack)
        NSLayoutConstraint.activate([
            categoryScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            categoryScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryScroll.heightAnchor.constraint(equalToConstant: 40),
            categoryStack.topAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.topAnchor),
            categoryStack.bottomAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.bottomAnchor),
            categoryStack.leadingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.leadingAnchor),
            categoryStack.trailingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.trailingAnchor),
            categoryStack.heightAnchor.constraint(equalTo: categoryScroll.frameLayoutGuide.heightAnchor)
        ])
    }

    private func setUpTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.sectionHeaderTopPadding = 0
        tableView.backgroundColor = AppColor.AppWhite
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        tableView.register(MomentShareCityCell.self, forCellReuseIdentifier: MomentShareCityCell.identifier)
        tableView.register(MomentPlaceCell.self, forCellReuseIdentifier: MomentPlaceCell.identifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: categoryScroll.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setUpCompleter() {
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        if let location = LocationService.shared.currentLocation {
            completer.region = MKCoordinateRegion(center: location.coordinate,
                                                  latitudinalMeters: 50_000,
                                                  longitudinalMeters: 50_000)
        }
    }

    // MARK: - Nearby spots

    /// Shows date spots around the user straight away when location is already allowed.
    private func loadInitialSpots() {
        userLocation = LocationService.shared.currentLocation
        if userLocation != nil {
            loadNearby()
        } else if LocationService.shared.permissionState.canUseLocation {
            isLoadingNearby = true
            fetchUserLocation { [weak self] in self?.loadNearby() }
        }
    }

    private func fetchUserLocation(then completion: @escaping () -> Void) {
        LocationService.shared.getCurrentLocation { [weak self] location, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let location {
                    self.userLocation = location
                    self.completer.region = MKCoordinateRegion(center: location.coordinate,
                                                               latitudinalMeters: 50_000,
                                                               longitudinalMeters: 50_000)
                }
                completion()
            }
        }
    }

    private func loadNearby() {
        let category = selectedCategory.map { DateSpotCategory.all[$0] }
        let search: MKLocalSearch
        if let userLocation {
            let request = MKLocalPointsOfInterestRequest(center: userLocation.coordinate, radius: 5000)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: category?.categories ?? DateSpotCategory.everything)
            search = MKLocalSearch(request: request)
        } else if let category {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = category.query
            request.resultTypes = .pointOfInterest
            search = MKLocalSearch(request: request)
        } else {
            isLoadingNearby = false
            nearbyItems = []
            reloadPlaces()
            return
        }

        nearbySearch?.cancel()
        nearbySearch = search
        isLoadingNearby = true
        nearbyItems = []
        reloadPlaces()
        search.start { [weak self] response, _ in
            guard let self, search === self.nearbySearch else { return }
            self.nearbySearch = nil
            self.isLoadingNearby = false
            var items = response?.mapItems ?? []
            if let userLocation = self.userLocation {
                items.sort { self.distance(to: $0, from: userLocation) < self.distance(to: $1, from: userLocation) }
            }
            self.nearbyItems = Array(items.prefix(30))
            self.reloadPlaces()
        }
    }

    private func distance(to item: MKMapItem, from location: CLLocation) -> CLLocationDistance {
        item.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func queryChanged() {
        if query.isEmpty {
            completer.cancel()
            completions = []
        } else {
            if selectedCategory != nil {
                selectedCategory = nil
                updateCategoryChips()
                loadNearby()
            }
            completer.queryFragment = query
        }
        tableView.reloadData()
    }

    private func categoryTapped(at index: Int) {
        selectedCategory = selectedCategory == index ? nil : index
        updateCategoryChips()
        searchField.text = nil
        searchField.resignFirstResponder()
        completions = []

        let state = LocationService.shared.permissionState
        if userLocation == nil, state != .denied, state != .restricted {
            isLoadingNearby = true
            tableView.reloadData()
            LocationService.shared.requestLocationPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.fetchUserLocation { [weak self] in self?.loadNearby() }
                    } else {
                        self.loadNearby()
                    }
                }
            }
        } else {
            loadNearby()
        }
    }

    private func updateCategoryChips() {
        for (index, chip) in categoryChips.enumerated() {
            chip.style = index == selectedCategory ? .filled : .outline
        }
    }

    private func finish(with place: MomentPlace) {
        onPick?(place)
        dismiss(animated: true)
    }

    private func shareCity() {
        guard !isLocating else { return }
        LocationService.shared.requestLocationPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.showLocationAccessAlert()
                    return
                }
                self.setLocating(true)
                LocationService.shared.getCurrentLocation { [weak self] location, _ in
                    DispatchQueue.main.async {
                        guard let location else {
                            self?.setLocating(false)
                            self?.aCustomToastView.show(message: "Couldn't get your location. Try searching instead.")
                            return
                        }
                        self?.userLocation = location
                        self?.resolveCity(for: location)
                    }
                }
            }
        }
    }

    private func resolveCity(for location: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setLocating(false)
                guard let placemark = placemarks?.first,
                      let name = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.name else {
                    self.aCustomToastView.show(message: "Couldn't find your city. Try searching instead.")
                    return
                }
                let detail = [placemark.administrativeArea, placemark.country]
                    .compactMap { $0 }
                    .filter { $0 != name }
                    .joined(separator: ", ")
                self.finish(with: MomentPlace(name: name,
                                              detail: detail.isEmpty ? nil : detail,
                                              city: nil,
                                              latitude: location.coordinate.latitude,
                                              longitude: location.coordinate.longitude))
            }
        }
    }

    private func select(_ completion: MKLocalSearchCompletion, at indexPath: IndexPath) {
        resolveSearch?.cancel()
        resolvingIndexPath = indexPath
        tableView.reloadRows(at: [indexPath], with: .none)

        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        resolveSearch = search
        search.start { [weak self] response, _ in
            guard let self, search === self.resolveSearch else { return }
            self.resolveSearch = nil
            self.resolvingIndexPath = nil
            let placemark = response?.mapItems.first?.placemark
            let detail = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            self.finish(with: MomentPlace(name: completion.title,
                                          detail: detail.isEmpty ? nil : detail,
                                          city: placemark?.locality,
                                          latitude: placemark?.coordinate.latitude,
                                          longitude: placemark?.coordinate.longitude))
        }
    }

    private func place(from item: MKMapItem) -> MomentPlace {
        let placemark = item.placemark
        let name = item.name ?? placemark.locality ?? "Pinned spot"
        return MomentPlace(name: name,
                           detail: areaText(for: placemark, excluding: name),
                           city: placemark.locality,
                           latitude: placemark.coordinate.latitude,
                           longitude: placemark.coordinate.longitude)
    }

    private func areaText(for placemark: MKPlacemark, excluding name: String) -> String? {
        let parts = [placemark.subLocality, placemark.locality].compactMap { $0 }.filter { $0 != name }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func setLocating(_ locating: Bool) {
        isLocating = locating
        tableView.reloadData()
    }

    private func reloadPlaces() {
        tableView.reloadData()
    }

    private func showLocationAccessAlert() {
        let alert = UIAlertController(title: "Location access is off",
                                      message: "Turn on location access in Settings to share your city, or search for a spot instead.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    private func highlightedTitle(for completion: MKLocalSearchCompletion) -> NSAttributedString {
        let title = NSMutableAttributedString(string: completion.title, attributes: [
            .font: UIFont.fredoka(.regular, size: 15),
            .foregroundColor: AppColor.MineShaft
        ])
        for range in completion.titleHighlightRanges {
            title.addAttribute(.font, value: UIFont.fredoka(.bold, size: 15), range: range.rangeValue)
        }
        return title
    }

    private var placesHeaderTitle: String {
        if !query.isEmpty { return "Results" }
        if let selectedCategory { return "\(DateSpotCategory.all[selectedCategory].title) spots near you" }
        return "Date spots near you"
    }

    private var placesEmptyMessage: String? {
        guard placeItems.isEmpty else { return nil }
        if !query.isEmpty { return "No spots found for “\(query)”" }
        if isLoadingNearby { return nil }
        if userLocation == nil {
            return "Turn on location to see date spots around you, or search above"
        }
        return "No spots found nearby. Try another category or search above."
    }
}

// MARK: - Table

extension MomentLocationPickerViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .shareCity: return 1
        case .places: return placeItems.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .shareCity:
            let cell = tableView.dequeueReusableCell(withIdentifier: MomentShareCityCell.identifier, for: indexPath) as! MomentShareCityCell
            cell.setLoading(isLocating)
            return cell

        case .places:
            let cell = tableView.dequeueReusableCell(withIdentifier: MomentPlaceCell.identifier, for: indexPath) as! MomentPlaceCell
            switch placeItems[indexPath.row] {
            case .completion(let completion):
                cell.configure(title: highlightedTitle(for: completion),
                               subtitle: completion.subtitle.isEmpty ? nil : completion.subtitle,
                               symbol: "mappin",
                               tint: AppColor.Punch,
                               trailing: nil,
                               isLoading: resolvingIndexPath == indexPath)
            case .mapItem(let item):
                let style = PlaceStyle.icon(for: item.pointOfInterestCategory)
                let distance = userLocation.flatMap { location -> String? in
                    let meters = self.distance(to: item, from: location)
                    return meters < .greatestFiniteMagnitude ? distanceFormatter.string(fromDistance: meters) : nil
                }
                cell.configure(title: NSAttributedString(string: item.name ?? "Pinned spot"),
                               subtitle: areaText(for: item.placemark, excluding: item.name ?? ""),
                               symbol: style.symbol,
                               tint: style.tint,
                               trailing: distance,
                               isLoading: false)
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title: String
        switch sections[section] {
        case .shareCity: return nil
        case .places: title = placesHeaderTitle
        }
        return MomentPickerSectionHeader(title: title, isLoading: sections[section] == .places && isLoadingNearby && query.isEmpty)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        sections[section] == .shareCity ? .leastNormalMagnitude : 44
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard sections[section] == .places, let message = placesEmptyMessage else { return nil }
        return MomentPickerEmptyView(message: message)
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        sections[section] == .places && placesEmptyMessage != nil ? UITableView.automaticDimension : .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, estimatedHeightForFooterInSection section: Int) -> CGFloat {
        sections[section] == .places && placesEmptyMessage != nil ? 140 : 0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        searchField.resignFirstResponder()
        switch sections[indexPath.section] {
        case .shareCity:
            shareCity()
        case .places:
            guard placeItems.indices.contains(indexPath.row) else { return }
            switch placeItems[indexPath.row] {
            case .completion(let completion): select(completion, at: indexPath)
            case .mapItem(let item): finish(with: place(from: item))
            }
        }
    }
}

// MARK: - Search

extension MomentLocationPickerViewController: MKLocalSearchCompleterDelegate, UITextFieldDelegate {

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard !query.isEmpty else { return }
        completions = completer.results
        tableView.reloadData()
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
        tableView.reloadData()
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        guard let sheet = sheetPresentationController, sheet.selectedDetentIdentifier != .large else { return }
        sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Cells

/// "Share my city" card at the top of the picker.
private final class MomentShareCityCell: UITableViewCell {

    static let identifier = "MomentShareCityCell"

    private let card = UIView()
    private let iconBackground = UIView()
    private let gradientLayer = CAGradientLayer()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let arrowView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        card.backgroundColor = AppColor.Serenade
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous

        iconBackground.layer.cornerRadius = 22
        iconBackground.clipsToBounds = true
        gradientLayer.colors = [AppColor.Punch.cgColor, AppColor.Carnation.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        iconBackground.layer.addSublayer(gradientLayer)

        let icon = UIImageView(image: UIImage(systemName: "location.fill",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
        icon.tintColor = AppColor.AppWhite

        let titleLabel = UILabel()
        titleLabel.text = "Share my city"
        titleLabel.font = .fredoka(.medium, size: 16)
        titleLabel.textColor = AppColor.MineShaft

        let shield = UIImageView(image: UIImage(systemName: "lock.shield.fill",
                                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))
        shield.tintColor = AppColor.OceanGreen
        shield.setContentHuggingPriority(.required, for: .horizontal)
        let privacyLabel = UILabel()
        privacyLabel.text = "Only your city is shown, never your exact spot"
        privacyLabel.font = .fredoka(.regular, size: 12)
        privacyLabel.textColor = AppColor.DoveGray
        privacyLabel.numberOfLines = 0
        let privacyRow = UIStackView(arrangedSubviews: [shield, privacyLabel])
        privacyRow.spacing = 4
        privacyRow.alignment = .center

        let labels = UIStackView(arrangedSubviews: [titleLabel, privacyRow])
        labels.axis = .vertical
        labels.spacing = 3

        arrowView.image = UIImage(systemName: "chevron.right",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        arrowView.tintColor = AppColor.Punch
        spinner.color = AppColor.Punch
        spinner.hidesWhenStopped = true

        [card, iconBackground, icon, labels, arrowView, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        contentView.addSubview(card)
        [iconBackground, labels, arrowView, spinner].forEach(card.addSubview)
        iconBackground.addSubview(icon)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            iconBackground.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconBackground.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 44),
            iconBackground.heightAnchor.constraint(equalToConstant: 44),
            icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),

            labels.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: arrowView.leadingAnchor, constant: -10),
            labels.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            labels.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),

            arrowView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            arrowView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: arrowView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: arrowView.centerYAnchor)
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Share my city. Only your city is shown, never your exact spot"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = iconBackground.bounds
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        UIView.animate(withDuration: 0.15) {
            self.card.transform = highlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
        }
    }

    func setLoading(_ loading: Bool) {
        arrowView.isHidden = loading
        loading ? spinner.startAnimating() : spinner.stopAnimating()
    }
}

/// A place row: tinted category icon, name, area and distance.
private final class MomentPlaceCell: UITableViewCell {

    static let identifier = "MomentPlaceCell"

    private let iconBackground = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let trailingLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let highlight = UIView()
        highlight.backgroundColor = AppColor.WildSand
        selectedBackgroundView = highlight

        iconBackground.layer.cornerRadius = 14
        iconBackground.layer.cornerCurve = .continuous
        iconView.contentMode = .scaleAspectFit

        titleLabel.font = .fredoka(.regular, size: 15)
        titleLabel.textColor = AppColor.MineShaft
        subtitleLabel.font = .fredoka(.regular, size: 12)
        subtitleLabel.textColor = AppColor.DoveGray

        trailingLabel.font = .fredoka(.medium, size: 12)
        trailingLabel.textColor = AppColor.DoveGray
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        spinner.color = AppColor.Punch
        spinner.hidesWhenStopped = true

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 2

        [iconBackground, iconView, labels, trailingLabel, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconBackground.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 44),
            iconBackground.heightAnchor.constraint(equalToConstant: 44),
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),

            labels.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: trailingLabel.leadingAnchor, constant: -10),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),

            trailingLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            trailingLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 66)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: NSAttributedString, subtitle: String?, symbol: String, tint: UIColor,
                   trailing: String?, isLoading: Bool) {
        titleLabel.attributedText = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty
        iconView.image = UIImage(systemName: symbol,
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        iconView.tintColor = tint
        iconBackground.backgroundColor = tint.withAlphaComponent(0.12)
        trailingLabel.text = trailing
        trailingLabel.isHidden = isLoading || trailing == nil
        isLoading ? spinner.startAnimating() : spinner.stopAnimating()
        accessibilityLabel = [title.string, subtitle, trailing].compactMap { $0 }.joined(separator: ", ")
    }
}

private final class MomentPickerSectionHeader: UIView {

    init(title: String, isLoading: Bool) {
        super.init(frame: .zero)
        backgroundColor = AppColor.AppWhite

        let label = UILabel()
        label.text = title
        label.font = .fredoka(.medium, size: 15)
        label.textColor = AppColor.MineShaft
        label.accessibilityTraits = .header

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = AppColor.Punch
        spinner.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        if isLoading { spinner.startAnimating() }

        let row = UIStackView(arrangedSubviews: [label, spinner])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
        spinner.isHidden = !isLoading
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class MomentPickerEmptyView: UIView {

    init(message: String) {
        super.init(frame: .zero)

        let icon = UIImageView(image: UIImage(systemName: "map",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)))
        icon.tintColor = AppColor.SeaPink

        let label = UILabel()
        label.text = message
        label.font = .fredoka(.regular, size: 13)
        label.textColor = AppColor.SilverChalice
        label.textAlignment = .center
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
