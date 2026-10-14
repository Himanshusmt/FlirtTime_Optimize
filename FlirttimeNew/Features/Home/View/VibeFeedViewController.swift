//
//  VibeFeedViewController.swift
//  FlirttimeNew
//
//  Moments tab: vibe feed with FlirtTime's moment filter chips, like / comment / gift / share actions.
//

import UIKit
import Combine

final class VibeFeedViewController: BaseViewController {

    enum Scope: Equatable {
        /// The Moments tab feed.
        case everyone
        /// "My Moments", pushed from Profile: only the signed-in user's vibes.
        case currentUser
        /// Another user's moments, pushed from their profile.
        case user(id: String, name: String)

        var isPushed: Bool { self != .everyone }
    }

    private let scope: Scope
    private let viewModel: VibeFeedViewModel
    private let uploadViewModel = VibeUploadViewModel.shared
    private var cancellables: Set<AnyCancellable> = []

    private static let uploadingBarHeight: CGFloat = 55
    private var uploadingBarHeightConstraint: NSLayoutConstraint?

    /// FlirtTime's "Moment uploading" bar from the Moments tab.
    private let uploadingBarView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.949, green: 0.957, blue: 0.969, alpha: 1)
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()

    private let uploadingTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Vibe uploading"
        label.font = UIFont.fredoka(.regular, size: 14)
        label.textColor = AppColor.MineShaft
        return label
    }()

    private let uploadingPercentageLabel: UILabel = {
        let label = UILabel()
        label.text = "0%"
        label.font = UIFont.fredoka(.regular, size: 12)
        label.textColor = AppColor.MineShaft
        label.textAlignment = .right
        return label
    }()

    private let uploadProgressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = UIColor(named: "#F04349") ?? AppColor.Punch
        progressView.trackTintColor = AppColor.Iron
        return progressView
    }()

    /// The tab bar's centre button rises above the bar and would cover the last row's actions.
    private static let centerTabButtonOverlap: CGFloat = 44

    private let topBarView = UIView()

    private let logoImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "FlirtTimeTitle"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var newVibeButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "PlusIcon"), for: .normal)
        button.accessibilityLabel = "New vibe"
        button.addTarget(self, action: #selector(newVibeTapped), for: .touchUpInside)
        return button
    }()

    private lazy var notificationButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "Notification"), for: .normal)
        button.accessibilityLabel = "Notifications"
        button.addTarget(self, action: #selector(notificationTapped), for: .touchUpInside)
        return button
    }()

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        button.tintColor = AppColor.MineShaft
        button.accessibilityLabel = "Back"
        button.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        return button
    }()

    private let titleLabel: UILabel = {
        let label = UILabel.vibeLabel(.bold, 20, style: .headline, color: AppColor.AppBlack)
        label.text = "My Moments"
        label.accessibilityTraits = .header
        return label
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 160
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(VibeTableViewCell.self, forCellReuseIdentifier: VibeTableViewCell.identifier)
        let bottomInset = scope.isPushed ? 0 : VibeFeedViewController.centerTabButtonOverlap
        tableView.contentInset.bottom = bottomInset
        tableView.verticalScrollIndicatorInsets.bottom = bottomInset
        return tableView
    }()

    private let refreshControl = UIRefreshControl()

    /// FlirtTime's Moments filter row. Only "Add new moment" acts; the distance chips just select.
    private enum FeedFilter: CaseIterable {
        case addMoment
        case nearBy
        case within25Km

        var title: String {
            switch self {
            case .addMoment: return "Add new moment"
            case .nearBy: return "Near by"
            case .within25Km: return "Less than 25km"
            }
        }
    }

    private var selectedFilter: FeedFilter = .addMoment
    private var filterChips: [(filter: FeedFilter, chip: VibeFilterChip)] = []

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        switch scope {
        case .everyone:
            label.text = "No vibes yet.\nBe the first to share what's on your mind!"
        case .currentUser:
            label.text = "You haven't shared any moments yet.\nTap + to post your first one!"
        case .user(_, let name):
            label.text = "\(name) hasn't shared any moments yet."
        }
        label.font = UIFont.fredoka(.regular, size: 16)
        label.textColor = AppColor.DoveGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private let footerSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = AppColor.Punch
        spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 50)
        return spinner
    }()

    /// Scrolled to once after the first page loads.
    private var focusVibeID: String?

    init(scope: Scope, focusVibeID: String? = nil) {
        self.scope = scope
        self.focusVibeID = focusVibeID
        switch scope {
        case .everyone: self.viewModel = VibeFeedViewModel()
        case .currentUser: self.viewModel = VibeFeedViewModel(onlyCurrentUser: true)
        case .user(let id, _): self.viewModel = VibeFeedViewModel(authorID: id)
        }
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = scope.isPushed
    }

    required init?(coder: NSCoder) {
        self.scope = .everyone
        self.viewModel = VibeFeedViewModel()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addBlushBackground()
        setUI()
        setUploadBinding()
        loadFeed(showLoader: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: scope.isPushed)
    }

    // MARK: - UI

    private func setUI() {
        [logoImageView, notificationButton, newVibeButton, backButton, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            topBarView.addSubview($0)
        }
        logoImageView.isHidden = scope.isPushed
        notificationButton.isHidden = scope.isPushed
        backButton.isHidden = !scope.isPushed
        titleLabel.isHidden = !scope.isPushed
        if case .user(_, let name) = scope {
            titleLabel.text = "\(name)'s Moments"
            newVibeButton.isHidden = true
        }
        [topBarView, uploadingBarView, tableView, emptyStateLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        setUploadingBarUI()

        NSLayoutConstraint.activate([
            topBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBarView.heightAnchor.constraint(equalToConstant: 52),

            logoImageView.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor, constant: 16),
            logoImageView.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            logoImageView.heightAnchor.constraint(equalToConstant: 24),
            logoImageView.widthAnchor.constraint(equalToConstant: 100),

            backButton.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor, constant: 6),
            backButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            titleLabel.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: newVibeButton.leadingAnchor, constant: -8),

            newVibeButton.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor, constant: -6),
            newVibeButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            newVibeButton.widthAnchor.constraint(equalToConstant: 44),
            newVibeButton.heightAnchor.constraint(equalToConstant: 44),

            notificationButton.trailingAnchor.constraint(equalTo: newVibeButton.leadingAnchor, constant: 8),
            notificationButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            notificationButton.widthAnchor.constraint(equalToConstant: 44),
            notificationButton.heightAnchor.constraint(equalToConstant: 44),

            uploadingBarView.topAnchor.constraint(equalTo: topBarView.bottomAnchor),
            uploadingBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            uploadingBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: uploadingBarView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            emptyStateLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        refreshControl.tintColor = AppColor.Punch
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        if scope == .everyone {
            tableView.tableHeaderView = makeFilterHeader()
        }
    }

    private var isOtherUserScope: Bool {
        if case .user = scope { return true }
        return false
    }

    private func setUploadingBarUI() {
        let fileImageView = UIImageView(image: UIImage(named: "file-image"))
        fileImageView.contentMode = .scaleAspectFit

        let titleRow = UIStackView(arrangedSubviews: [uploadingTitleLabel, uploadingPercentageLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 5

        let textStack = UIStackView(arrangedSubviews: [titleRow, uploadProgressView])
        textStack.axis = .vertical
        textStack.spacing = 12

        [fileImageView, textStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            uploadingBarView.addSubview($0)
        }

        let heightConstraint = uploadingBarView.heightAnchor.constraint(equalToConstant: 0)
        uploadingBarHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            heightConstraint,

            fileImageView.leadingAnchor.constraint(equalTo: uploadingBarView.leadingAnchor, constant: 14),
            fileImageView.topAnchor.constraint(equalTo: uploadingBarView.topAnchor, constant: 12.5),
            fileImageView.widthAnchor.constraint(equalToConstant: 30),
            fileImageView.heightAnchor.constraint(equalToConstant: 30),

            textStack.leadingAnchor.constraint(equalTo: fileImageView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: uploadingBarView.trailingAnchor, constant: -16),
            textStack.centerYAnchor.constraint(equalTo: fileImageView.centerYAnchor),

            uploadingPercentageLabel.widthAnchor.constraint(equalToConstant: 60)
        ])
    }

    /// "Add new moment / Near by / Less than 25km" chip row from FlirtTime's Moments tab.
    private func makeFilterHeader() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 59))

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true

        let chipStack = UIStackView()
        chipStack.axis = .horizontal
        chipStack.spacing = 10

        filterChips = FeedFilter.allCases.map { filter in
            let icon = filter == .addMoment ? UIImage(named: "addIcon") : nil
            let chip = VibeFilterChip(title: filter.title, icon: icon)
            chip.isSelected = filter == selectedFilter
            chip.addAction(UIAction { [weak self] _ in self?.filterTapped(filter) }, for: .touchUpInside)
            chipStack.addArrangedSubview(chip)
            return (filter, chip)
        }

        let separator = UIView()
        separator.backgroundColor = AppColor.Iron

        [scrollView, separator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(chipStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            scrollView.heightAnchor.constraint(equalToConstant: VibeFilterChip.height),

            chipStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            chipStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            chipStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            chipStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            chipStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        return header
    }

    private func filterTapped(_ filter: FeedFilter) {
        selectedFilter = filter
        filterChips.forEach { $0.chip.isSelected = $0.filter == filter }
        if filter == .addMoment {
            newVibeTapped()
        }
    }

    private func updateEmptyState() {
        emptyStateLabel.isHidden = !viewModel.vibes.isEmpty
    }

    // MARK: - Upload progress

    private func setUploadBinding() {
        guard !isOtherUserScope else { return }
        uploadViewModel.$uploadProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                if let progress {
                    self.showUploadingBar(progress: progress)
                } else {
                    self.hideUploadingBar()
                }
            }
            .store(in: &cancellables)

        uploadViewModel.uploadFinished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let vibe):
                    if vibe.media?.isEmpty == false {
                        self.viewModel.prepend(vibe)
                        self.tableView.reloadData()
                        self.updateEmptyState()
                    } else {
                        self.loadFeed(showLoader: false)
                    }
                    self.aCustomToastView.show(message: "Your vibe is live")
                case .failure(let error):
                    self.aCustomToastView.show(message: error.message)
                }
            }
            .store(in: &cancellables)
    }

    private func showUploadingBar(progress: Float) {
        if uploadingBarView.isHidden {
            uploadProgressView.progress = 0
            uploadingBarView.alpha = 0
            uploadingBarView.isHidden = false
            uploadingBarHeightConstraint?.constant = VibeFeedViewController.uploadingBarHeight
            UIView.animate(withDuration: 0.75) {
                self.uploadingBarView.alpha = 1
                self.view.layoutIfNeeded()
            }
        }
        uploadProgressView.setProgress(progress, animated: false)
        uploadingPercentageLabel.text = "\(Int(progress * 100))%"
    }

    private func hideUploadingBar() {
        guard !uploadingBarView.isHidden else { return }
        uploadingBarHeightConstraint?.constant = 0
        UIView.animate(withDuration: 0.75, animations: {
            self.uploadingBarView.alpha = 0
            self.view.layoutIfNeeded()
        }, completion: { _ in
            if self.uploadingBarHeightConstraint?.constant == 0 {
                self.uploadingBarView.isHidden = true
            }
        })
    }

    // MARK: - Data

    private func loadFeed(showLoader: Bool) {
        if showLoader {
            aActivityIndicator.show()
        }
        viewModel.loadFirstPage { [weak self] result in
            guard let self else { return }
            self.aActivityIndicator.hide()
            self.refreshControl.endRefreshing()
            if case .failure(let error) = result {
                self.aCustomToastView.show(message: error.message)
            }
            self.tableView.reloadData()
            self.updateEmptyState()
            if let id = self.focusVibeID, let row = self.viewModel.index(of: id) {
                self.focusVibeID = nil
                self.tableView.layoutIfNeeded()
                self.tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: false)
            }
        }
    }

    private func loadNextPage() {
        guard viewModel.hasMore, !viewModel.isLoading else { return }
        footerSpinner.startAnimating()
        tableView.tableFooterView = footerSpinner
        viewModel.loadNextPage { [weak self] result in
            guard let self else { return }
            self.footerSpinner.stopAnimating()
            self.tableView.tableFooterView = nil
            if case .failure(let error) = result {
                self.aCustomToastView.show(message: error.message)
            }
            self.tableView.reloadData()
        }
    }

    @objc private func handleRefresh() {
        loadFeed(showLoader: false)
    }

    private func refreshCounts(at row: Int?) {
        guard let row, viewModel.vibes.indices.contains(row),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? VibeTableViewCell else { return }
        cell.updateCounts(with: viewModel.vibes[row])
    }

    // MARK: - Navigation

    @objc private func newVibeTapped() {
        guard !uploadViewModel.isUploading else {
            aCustomToastView.show(message: "Please wait, your last vibe is still uploading")
            return
        }
        let aAddMomentViewController: AddMomentViewController = AddMomentViewController.instantiateFromStoryboard()
        aAddMomentViewController.callBackAction = { [weak self] in
            guard let self else { return }
            self.tableView.setContentOffset(CGPoint(x: 0, y: -self.tableView.adjustedContentInset.top), animated: false)
        }
        navigationController?.pushViewController(aAddMomentViewController, animated: true)
    }

    @objc private func notificationTapped() {
        let aNotificationViewController: NotificationViewController = NotificationViewController.instantiateFromStoryboard()
        navigationController?.pushViewController(aNotificationViewController, animated: true)
    }
    private func presentAsSheet(_ viewController: UIViewController, detents: [UISheetPresentationController.Detent]) {
        viewController.modalPresentationStyle = .pageSheet
        if let sheet = viewController.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(viewController, animated: true)
    }
}

// MARK: - UITableView
extension VibeFeedViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.vibes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: VibeTableViewCell.identifier, for: indexPath) as? VibeTableViewCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.vibes[indexPath.row])
        cell.delegate = self
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= viewModel.vibes.count - 3 {
            loadNextPage()
        }
    }
}

// MARK: - Like / Comment / Gift / Share
extension VibeFeedViewController: VibeTableViewCellDelegate {

    func vibeCellDidTapLike(_ cell: VibeTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibeId = viewModel.vibes[indexPath.row].id
        viewModel.toggleLike(vibeId: vibeId) { [weak self] row in
            self?.refreshCounts(at: row)
        }
        cell.updateCounts(with: viewModel.vibes[indexPath.row])
    }

    func vibeCellDidDoubleTapLike(_ cell: VibeTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        guard viewModel.vibes[indexPath.row].hasLiked != true else { return }
        let vibeId = viewModel.vibes[indexPath.row].id
        viewModel.toggleLike(vibeId: vibeId) { [weak self] row in
            self?.refreshCounts(at: row)
        }
        cell.updateCounts(with: viewModel.vibes[indexPath.row])
    }

    func vibeCellDidLongPressLike(_ cell: VibeTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]
        guard (vibe.likesCount ?? 0) > 0 else {
            aCustomToastView.show(message: "No likes yet")
            return
        }
        presentAsSheet(MomentLikesViewController(momentId: vibe.id), detents: [.medium(), .large()])
    }

    func vibeCellDidTapComment(_ cell: VibeTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]
        let commentViewController = VibeCommentViewController(vibe: vibe)
        commentViewController.onCommentsCountChanged = { [weak self] count in
            guard let self else { return }
            let row = self.viewModel.updateVibe(id: vibe.id) { $0.commentsCount = count }
            self.refreshCounts(at: row)
        }
        presentAsSheet(commentViewController, detents: [.medium(), .large()])
    }

    func vibeCellDidTapGift(_ cell: VibeTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]

        if viewModel.isOwnVibe(vibe) {
            presentAsSheet(VibeReceivedGiftsViewController(vibe: vibe), detents: [.medium(), .large()])
            return
        }

        let giftViewController = VibeGiftViewController(vibe: vibe)
        giftViewController.onGiftsSent = { [weak self] sentCount in
            guard let self else { return }
            let row = self.viewModel.updateVibe(id: vibe.id) { $0.giftCount = ($0.giftCount ?? 0) + sentCount }
            self.refreshCounts(at: row)
            self.aCustomToastView.show(message: sentCount > 1 ? "\(sentCount) gifts sent 🎉" : "Gift sent 🎉")
        }
        let height = VibeGiftViewController.preferredSheetHeight
        presentAsSheet(giftViewController, detents: [.custom(identifier: .init("vibeGift")) { _ in height }, .large()])
    }

    func vibeCellDidTapShare(_ cell: VibeTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]
        let activity = UIActivityViewController(activityItems: [shareText(for: vibe)], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = cell
        activity.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            guard completed, let self else { return }
            self.viewModel.recordShare(vibeId: vibe.id) { row in
                self.refreshCounts(at: row)
            }
        }
        present(activity, animated: true)
    }

    private func shareText(for vibe: Vibe) -> String {
        let name = vibe.author?.displayName ?? "Someone"
        let caption = (vibe.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if caption.isEmpty { return "Check out \(name)'s vibe on FlirtTime" }
        return "\(name) on FlirtTime: \(caption)"
    }

    func vibeCellDidTapProfile(_ cell: VibeTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]
        if viewModel.isOwnVibe(vibe) {
            openOwnProfile()
            return
        }
        if isOtherUserScope {
            navigationController?.popViewController(animated: true)
            return
        }
        let author = vibe.author
        let seed = OtherUserProfileRouter.Seed(
            userID: author?.userId ?? vibe.userId,
            name: author?.displayName,
            avatar: author?.profilePicture,
            location: author?.location,
            isVerified: author?.verified ?? false
        )
        OtherUserProfileRouter.open(seed, from: self)
    }

    /// "My Moments" was pushed from Profile, so go back to it; otherwise switch to the Profile tab.
    private func openOwnProfile() {
        if scope == .currentUser {
            navigationController?.popViewController(animated: true)
            return
        }
        guard let tabBar = tabBarController,
              let index = tabBar.viewControllers?.firstIndex(where: { tab in
                  let root = (tab as? UINavigationController)?.viewControllers.first ?? tab
                  return root is ProfileViewController
              }) else { return }
        (tabBar.viewControllers?[index] as? UINavigationController)?.popToRootViewController(animated: false)
        tabBar.selectedIndex = index
    }

    func vibeCellDidTapMore(_ cell: VibeTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if viewModel.isOwnVibe(vibe) {
            sheet.addAction(UIAlertAction(title: "Delete moment", style: .destructive) { [weak self] _ in
                self?.confirmDelete(vibe)
            })
        } else {
            sheet.addAction(UIAlertAction(title: "Report vibe", style: .destructive) { [weak self] _ in
                self?.showReportReasons(for: vibe, sourceView: cell)
            })
        }
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = cell
        present(sheet, animated: true)
    }
}

// MARK: - Report
private extension VibeFeedViewController {

    func showReportReasons(for vibe: Vibe, sourceView: UIView) {
        let sheet = UIAlertController(title: "Report vibe", message: "Why are you reporting this vibe?", preferredStyle: .actionSheet)
        VibeFeedViewModel.reportReasons.forEach { reason in
            sheet.addAction(UIAlertAction(title: reason, style: .default) { [weak self] _ in
                guard let self else { return }
                self.aActivityIndicator.show()
                self.viewModel.reportVibe(vibeId: vibe.id, reason: reason) { [weak self] result in
                    self?.handleRemoval(result, successMessage: "Thanks for reporting. We'll review this vibe.")
                }
            })
        }
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        present(sheet, animated: true)
    }

    func confirmDelete(_ vibe: Vibe) {
        let alert = UIAlertController(title: "Delete this moment?",
                                      message: "It will be removed for everyone. This can't be undone.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.aActivityIndicator.show()
            self.viewModel.deleteVibe(vibeId: vibe.id) { [weak self] result in
                self?.handleRemoval(result, successMessage: "Moment deleted")
            }
        })
        present(alert, animated: true)
    }

    func handleRemoval(_ result: Result<Int?, VibeError>, successMessage: String) {
        aActivityIndicator.hide()
        switch result {
        case .success(let row):
            if let row {
                tableView.deleteRows(at: [IndexPath(row: row, section: 0)], with: .fade)
            }
            updateEmptyState()
            aCustomToastView.show(message: successMessage)
        case .failure(let error):
            aCustomToastView.show(message: error.message)
        }
    }
}

/// Pill from FlirtTime's Moments filter row: filled red when selected, white with a grey border otherwise.
private final class VibeFilterChip: UIControl {

    static let height: CGFloat = 35

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 15)
        return label
    }()

    init(title: String, icon: UIImage?) {
        super.init(frame: .zero)
        layer.cornerRadius = VibeFilterChip.height / 2
        layer.borderColor = AppColor.Gallery.cgColor
        iconImageView.image = icon?.withRenderingMode(.alwaysTemplate)
        iconImageView.isHidden = icon == nil
        titleLabel.text = title
        isAccessibilityElement = true
        accessibilityLabel = title

        let stackView = UIStackView(arrangedSubviews: [iconImageView, titleLabel])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.isUserInteractionEnabled = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: VibeFilterChip.height),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 15),
            iconImageView.heightAnchor.constraint(equalToConstant: 15)
        ])
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet { applyStyle() }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    private func applyStyle() {
        let foreground = isSelected ? AppColor.AppWhite : AppColor.DoveGray
        backgroundColor = isSelected ? AppColor.Punch : AppColor.AppWhite
        layer.borderWidth = isSelected ? 0 : 1
        titleLabel.textColor = foreground
        iconImageView.tintColor = foreground
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
