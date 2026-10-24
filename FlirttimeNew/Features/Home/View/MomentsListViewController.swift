//
//  MomentsListViewController.swift
//  FlirttimeNew
//
//  Moments tab: moment feed with like / comment / gift / share actions.
//

import UIKit
import Combine

final class MomentsListViewController: BaseViewController, Instantiable {

    enum Scope: Equatable {
        /// The Moments tab feed.
        case everyone
        /// "My Moments", pushed from Profile: only the signed-in user's moments.
        case currentUser
        /// Another user's moments, pushed from their profile.
        case user(id: String, name: String)

        var isPushed: Bool { self != .everyone }
    }

    static var storyboardName: StringConvertible {
        return StoryboardName.dashboard
    }

    // MARK: - Outlets

    @IBOutlet private weak var headerContainerView: UIView!
    @IBOutlet private weak var logoImageView: UIImageView!
    @IBOutlet private weak var addMomentButton: UIButton!
    @IBOutlet private weak var notificationButton: UIButton!
    @IBOutlet private weak var backButton: UIButton!
    @IBOutlet private weak var titleLabel: UILabel!

    @IBOutlet private weak var uploadingBarView: UIView!
    @IBOutlet private weak var uploadingBarHeightConstraint: NSLayoutConstraint!
    @IBOutlet private weak var uploadingPercentageLabel: UILabel!
    @IBOutlet private weak var uploadProgressView: UIProgressView!

    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var emptyStateLabel: UILabel!

    @IBOutlet private weak var scrollToTopButton: UIButton!
    @IBOutlet private weak var scrollToTopBottomConstraint: NSLayoutConstraint!

    // MARK: - State

    /// Called with the moment ID after a moment is reported and removed from this list.
    var onVibeRemoved: ((String) -> Void)?

    private var scope: Scope = .everyone
    /// Scrolled to once after the first page loads.
    private var focusVibeID: String?
    /// One-shot: only the notification-driven first page includes `momentId` in the feed request.
    private var pendingFeedMomentId: String?
    /// After the focused moment loads, open comments or the received-gift list.
    private var pendingNotificationSheet: NotificationSheet?

    enum NotificationSheet {
        case comments
        case receivedGifts
    }
    private lazy var viewModel: MomentsListViewModel = {
        switch scope {
        case .everyone: return MomentsListViewModel()
        case .currentUser: return MomentsListViewModel(onlyCurrentUser: true)
        case .user(let id, let name): return MomentsListViewModel(authorID: id, authorName: name)
        }
    }()
    /// Moments whose long caption the user expanded with "more".
    private var expandedCaptionIDs = Set<String>()
    private let uploadViewModel = MomentsUploadViewModel.shared
    private var cancellables: Set<AnyCancellable> = []
    private let refreshControl = UIRefreshControl()

    private static let uploadingBarHeight: CGFloat = 55
    private static let uploadingBarAnimationDuration: TimeInterval = 0.75
    /// The tab bar's centre button rises above the bar and would cover the last row's actions.
    private static let centerTabButtonOverlap: CGFloat = 44

    /// FlirtTime showed the scroll-to-top button once the fourth moment came on screen.
    private static let scrollToTopRevealRow = 3

    private var isScrollToTopVisible = false
    private var pendingFeedLoader: DispatchWorkItem?
    private var isFeedLoaderVisible = false
    private static let feedLoaderDelay: TimeInterval = 0.3

    private let footerSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = AppColor.Punch
        spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 50)
        return spinner
    }()

    /// Pushed feeds ("My Moments", another user's moments) come from the same storyboard scene as the tab.
    static func make(scope: Scope, focusVibeID: String? = nil) -> MomentsListViewController {
        let viewController = instantiateFromStoryboard()
        viewController.scope = scope
        viewController.focusVibeID = focusVibeID
        viewController.hidesBottomBarWhenPushed = scope.isPushed
        return viewController
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addBlushBackground()
        setUI()
        setUploadBinding()
        setSocketBinding()
        notificationButton.clipsToBounds = false
        notificationButton.superview?.clipsToBounds = false
        headerContainerView.clipsToBounds = false
        notificationButton.bindNotificationBadge(inset: 6)
        loadFeed(showLoader: true)
    }

    /// Opens the feed on a specific moment from an FCM / in-app notification tap.
    func openFromNotification(momentId: String, sheet: NotificationSheet? = nil) {
        focusVibeID = momentId
        pendingFeedMomentId = momentId
        pendingNotificationSheet = sheet
        presentedViewController?.dismiss(animated: false)
        guard isViewLoaded else { return }
        loadFeed(showLoader: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: scope.isPushed)
        if !scope.isPushed {
            NotificationBadgeStore.shared.refresh()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableTopInset()
    }

    // MARK: - UI

    /// Reserves room for the floating header; it only changes when the uploading bar opens or closes.
    private func updateTableTopInset() {
        let headerHeight = headerContainerView.bounds.height
        let oldInset = tableView.contentInset.top
        guard oldInset != headerHeight else { return }
        let wasAtTop = tableView.contentOffset.y <= -tableView.adjustedContentInset.top
        tableView.contentInset.top = headerHeight
        tableView.verticalScrollIndicatorInsets.top = headerHeight
        if wasAtTop, !refreshControl.isRefreshing {
            tableView.contentOffset.y = -tableView.adjustedContentInset.top
        }
    }

    private func setUI() {
        logoImageView.isHidden = scope.isPushed
        addMomentButton.isHidden = scope.isPushed
        notificationButton.isHidden = scope.isPushed
        backButton.isHidden = !scope.isPushed
        titleLabel.isHidden = !scope.isPushed
        titleLabel.font = MomentsFont.scaled(.bold, 20, style: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        switch scope {
        case .everyone:
            emptyStateLabel.text = "No moments yet.\nBe the first to share what's on your mind!"
        case .currentUser:
            emptyStateLabel.text = "You haven't shared any moments yet."
        case .user(_, let name):
            titleLabel.text = "\(name)'s Moments"
            emptyStateLabel.text = "\(name) hasn't shared any moments yet."
        }

        tableView.register(MomentsTableViewCell.self, forCellReuseIdentifier: MomentsTableViewCell.identifier)
        let bottomInset = scope.isPushed ? 0 : MomentsListViewController.centerTabButtonOverlap
        tableView.contentInset.bottom = bottomInset
        tableView.verticalScrollIndicatorInsets.bottom = bottomInset
        refreshControl.tintColor = AppColor.Punch
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        tableView.tableHeaderView = nil
    }

    private var isOtherUserScope: Bool {
        if case .user = scope { return true }
        return false
    }

    @IBAction private func addMomentTapped(_ sender: UIButton) {
        newVibeTapped()
    }

    private func updateEmptyState() {
        emptyStateLabel.isHidden = !viewModel.vibes.isEmpty
    }

    // MARK: - Scroll-to-top

    private func updateScrollToTopButton() {
        let isPastRevealRow = tableView.indexPathsForVisibleRows?.contains { $0.row >= MomentsListViewController.scrollToTopRevealRow } ?? false
        guard isPastRevealRow != isScrollToTopVisible else { return }
        isScrollToTopVisible = isPastRevealRow

        if isPastRevealRow {
            scrollToTopButton.alpha = 0
            scrollToTopButton.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            scrollToTopButton.isHidden = false
        }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
            self.scrollToTopButton.alpha = isPastRevealRow ? 1 : 0
            self.scrollToTopButton.transform = isPastRevealRow ? .identity : CGAffineTransform(scaleX: 0.6, y: 0.6)
        }, completion: { _ in
            if !self.isScrollToTopVisible {
                self.scrollToTopButton.isHidden = true
            }
        })
    }

    @IBAction private func scrollToTopTapped(_ sender: UIButton) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: true)
    }

    // MARK: - Upload progress

    private func setSocketBinding() {
        MomentsSocketService.shared.setupSocketListeners()
        MomentsSocketService.shared.updates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.applySocket(update)
            }
            .store(in: &cancellables)
    }

    private func applySocket(_ update: MomentSocketUpdate) {
        let change = viewModel.applySocket(update)
        switch change {
        case .counts(let row):
            refreshCounts(at: row)
        case .inserted(let row):
            applyRowChange(inserted: true, row: row)
        case .removed(let row):
            dismissComments(for: update.momentId)
            applyRowChange(inserted: false, row: row)
            onVibeRemoved?(update.momentId)
        case .none:
            break
        }
    }

    private func applyRowChange(inserted: Bool, row: Int) {
        let tableCount = tableView.numberOfSections > 0 ? tableView.numberOfRows(inSection: 0) : 0
        let modelCount = viewModel.vibes.count
        let expected = inserted ? tableCount + 1 : tableCount - 1
        if expected == modelCount, row < modelCount || !inserted {
            let path = IndexPath(row: inserted ? row : min(row, max(tableCount - 1, 0)), section: 0)
            tableView.performBatchUpdates {
                if inserted {
                    tableView.insertRows(at: [path], with: .fade)
                } else {
                    tableView.deleteRows(at: [path], with: .fade)
                }
            }
        } else {
            tableView.reloadData()
        }
        updateEmptyState()
    }

    private func dismissComments(for vibeId: String) {
        let comments = presentedViewController as? MomentsCommentViewController
            ?? presentedViewController?.presentedViewController as? MomentsCommentViewController
        guard comments?.vibeId == vibeId else { return }
        comments?.dismiss(animated: true)
    }

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
                        self.viewModel.markLocalEdit(id: vibe.id)
                        self.viewModel.prepend(vibe)
                        self.tableView.reloadData()
                        self.updateEmptyState()
                    } else {
                        self.loadFeed(showLoader: false)
                    }
                    self.aCustomToastView.show(message: "Your moment is live")
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
            uploadingBarHeightConstraint.constant = MomentsListViewController.uploadingBarHeight
            UIView.animate(withDuration: MomentsListViewController.uploadingBarAnimationDuration) {
                self.uploadingBarView.alpha = 1
                self.view.layoutIfNeeded()
            }
        }
        uploadProgressView.setProgress(progress, animated: false)
        uploadingPercentageLabel.text = "\(Int(progress * 100))%"
    }

    private func hideUploadingBar() {
        guard !uploadingBarView.isHidden else { return }
        uploadingBarHeightConstraint.constant = 0
        UIView.animate(withDuration: MomentsListViewController.uploadingBarAnimationDuration, animations: {
            self.uploadingBarView.alpha = 0
            self.view.layoutIfNeeded()
        }, completion: { _ in
            if self.uploadingBarHeightConstraint.constant == 0 {
                self.uploadingBarView.isHidden = true
            }
        })
    }

    // MARK: - Data

    private func loadFeed(showLoader: Bool) {
        pendingFeedLoader?.cancel()
        isFeedLoaderVisible = false
        if showLoader {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.isFeedLoaderVisible = true
                self.aActivityIndicator.show()
            }
            pendingFeedLoader = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.feedLoaderDelay, execute: work)
        }
        let momentId = pendingFeedMomentId
        pendingFeedMomentId = nil
        viewModel.loadFirstPage(momentId: momentId) { [weak self] result in
            guard let self else { return }
            self.pendingFeedLoader?.cancel()
            self.pendingFeedLoader = nil
            if self.isFeedLoaderVisible {
                self.aActivityIndicator.hide()
                self.isFeedLoaderVisible = false
            }
            self.refreshControl.endRefreshing()
            if case .failure(let error) = result {
                self.aCustomToastView.show(message: error.message)
            }
            self.tableView.reloadData()
            self.updateEmptyState()
            let focusedId = self.focusVibeID ?? momentId
            if let id = self.focusVibeID, let row = self.viewModel.index(of: id) {
                self.focusVibeID = nil
                self.tableView.layoutIfNeeded()
                self.tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: false)
            }
            self.presentPendingNotificationSheet(momentId: focusedId)
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
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? MomentsTableViewCell else { return }
        cell.updateCounts(with: viewModel.vibes[row])
    }

    // MARK: - Navigation

    private func newVibeTapped() {
        guard !uploadViewModel.isUploading else {
            aCustomToastView.show(message: "Please wait, your last moment is still uploading")
            return
        }
        let aAddMomentViewController: AddMomentViewController = AddMomentViewController.instantiateFromStoryboard()
        aAddMomentViewController.callBackAction = { [weak self] in
            guard let self else { return }
            self.tableView.setContentOffset(CGPoint(x: 0, y: -self.tableView.adjustedContentInset.top), animated: false)
        }
        navigationController?.pushViewController(aAddMomentViewController, animated: true)
    }

    @IBAction private func notificationTapped(_ sender: UIButton) {
        let aNotificationViewController: NotificationViewController = NotificationViewController.instantiateFromStoryboard()
        navigationController?.pushViewController(aNotificationViewController, animated: true)
    }

    @IBAction private func backTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    private func presentPendingNotificationSheet(momentId: String?) {
        guard let sheet = pendingNotificationSheet else { return }
        guard let momentId, let vibe = viewModel.vibes.first(where: { $0.id == momentId }) else {
            pendingNotificationSheet = nil
            return
        }
        let presentSheet = { [weak self] in
            guard let self else { return }
            self.pendingNotificationSheet = nil
            switch sheet {
            case .comments:
                self.presentComments(for: vibe)
            case .receivedGifts:
                self.presentReceivedGifts(for: vibe)
            }
        }
        let presentWhenVisible = { [weak self] in
            guard let self else { return }
            if let presented = self.presentedViewController {
                presented.dismiss(animated: false, completion: presentSheet)
            } else {
                presentSheet()
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.view.window == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: presentWhenVisible)
            } else {
                presentWhenVisible()
            }
        }
    }

    private func presentComments(for vibe: MomentsPost) {
        let commentViewController = MomentsCommentViewController(vibe: vibe)
        commentViewController.onCommentsCountChanged = { [weak self] count in
            guard let self else { return }
            let row = self.viewModel.updateVibe(id: vibe.id) { $0.commentsCount = count }
            self.refreshCounts(at: row)
        }
        commentViewController.onOpenUser = { [weak self] seed in
            self?.openUser(from: seed)
        }
        presentAsSheet(commentViewController, detents: [.medium(), .large()])
    }

    private func presentReceivedGifts(for vibe: MomentsPost) {
        presentAsSheet(MomentsReceivedGiftsViewController(vibe: vibe), detents: [.medium(), .large()])
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
extension MomentsListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.vibes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: MomentsTableViewCell.identifier, for: indexPath) as? MomentsTableViewCell else {
            return UITableViewCell()
        }
        let vibe = viewModel.vibes[indexPath.row]
        cell.configure(with: vibe, isCaptionExpanded: expandedCaptionIDs.contains(vibe.id))
        cell.delegate = self
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= viewModel.vibes.count - 3 {
            loadNextPage()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        updateScrollToTopButton()
    }
}

// MARK: - Like / Comment / Gift / Share
extension MomentsListViewController: MomentsTableViewCellDelegate {

    func vibeCellDidToggleCaption(_ cell: MomentsTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibeId = viewModel.vibes[indexPath.row].id
        let expand = !expandedCaptionIDs.contains(vibeId)
        if expand {
            expandedCaptionIDs.insert(vibeId)
        } else {
            expandedCaptionIDs.remove(vibeId)
        }
        cell.setCaptionExpanded(expand)
        tableView.performBatchUpdates(nil) { [weak self] _ in
            guard let self, !expand else { return }
            // After "less", bring the post's top back on screen if the long caption had scrolled it away.
            let cellTop = self.tableView.rectForRow(at: indexPath).minY
            if cellTop < self.tableView.contentOffset.y + self.tableView.adjustedContentInset.top {
                self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
            }
        }
    }

    func vibeCellDidTapLike(_ cell: MomentsTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibeId = viewModel.vibes[indexPath.row].id
        viewModel.toggleLike(vibeId: vibeId) { [weak self] row in
            self?.refreshCounts(at: row)
        }
        cell.updateCounts(with: viewModel.vibes[indexPath.row])
    }

    func vibeCellDidDoubleTapLike(_ cell: MomentsTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        guard viewModel.vibes[indexPath.row].hasLiked != true else { return }
        let vibeId = viewModel.vibes[indexPath.row].id
        viewModel.toggleLike(vibeId: vibeId) { [weak self] row in
            self?.refreshCounts(at: row)
        }
        cell.updateCounts(with: viewModel.vibes[indexPath.row])
    }

    func vibeCellDidLongPressLike(_ cell: MomentsTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]
        guard (vibe.likesCount ?? 0) > 0 else {
            aCustomToastView.show(message: "No likes yet")
            return
        }
        presentAsSheet(MomentLikesViewController(momentId: vibe.id), detents: [.medium(), .large()])
    }

    func vibeCellDidTapComment(_ cell: MomentsTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]
        let commentViewController = MomentsCommentViewController(vibe: vibe)
        commentViewController.onCommentsCountChanged = { [weak self] count in
            guard let self else { return }
            self.viewModel.markLocalEdit(id: vibe.id)
            let row = self.viewModel.updateVibe(id: vibe.id) { $0.commentsCount = count }
            self.refreshCounts(at: row)
        }
        commentViewController.onOpenUser = { [weak self] seed in
            self?.openUser(from: seed)
        }
        presentAsSheet(commentViewController, detents: [.medium(), .large()])
    }

    func vibeCellDidTapGift(_ cell: MomentsTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]

        if viewModel.isOwnVibe(vibe) {
            presentReceivedGifts(for: vibe)
            return
        }

        let giftViewController = MomentsGiftViewController(vibe: vibe)
        giftViewController.onSendStarted = { [weak self] in
            self?.viewModel.markLocalEdit(id: vibe.id)
        }
        giftViewController.onGiftsSent = { [weak self] sentCount, totalGifts in
            guard let self else { return }
            self.viewModel.markLocalEdit(id: vibe.id)
            let row = self.viewModel.updateVibe(id: vibe.id) { vibe in
                if let totalGifts {
                    vibe.giftCount = totalGifts
                } else {
                    vibe.giftCount = (vibe.giftCount ?? 0) + sentCount
                }
            }
            self.refreshCounts(at: row)
            self.aCustomToastView.show(message: sentCount > 1 ? "\(sentCount) gifts sent 🎉" : "Gift sent 🎉")
        }
        let height = MomentsGiftViewController.preferredSheetHeight
        presentAsSheet(giftViewController, detents: [.custom(identifier: .init("vibeGift")) { _ in height }, .large()])
    }

    func vibeCellDidTapShare(_ cell: MomentsTableViewCell) {
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

    private func shareText(for vibe: MomentsPost) -> String {
        let name = vibe.author?.displayName ?? "Someone"
        let caption = (vibe.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if caption.isEmpty { return "Check out \(name)'s moment on FlirtTime" }
        return "\(name) on FlirtTime: \(caption)"
    }

    func vibeCellDidTapProfile(_ cell: MomentsTableViewCell) {
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

    private func openUser(from seed: OtherUserProfileRouter.Seed) {
        let currentId = MomentsAuthor.currentUser.userId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tappedId = seed.userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let currentId, !currentId.isEmpty, currentId == tappedId {
            openOwnProfile()
            return
        }
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

    func vibeCellDidTapMore(_ cell: MomentsTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if viewModel.isOwnVibe(vibe) {
            sheet.addAction(UIAlertAction(title: "Delete moment", style: .destructive) { [weak self] _ in
                self?.confirmDelete(vibe)
            })
        } else {
            sheet.addAction(UIAlertAction(title: "Report moment", style: .destructive) { [weak self] _ in
                self?.showReportReasons(for: vibe, sourceView: cell)
            })
            sheet.addAction(UIAlertAction(title: "Block user", style: .destructive) { [weak self] _ in
                self?.confirmBlock(vibe)
            })
        }
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = cell
        present(sheet, animated: true)
    }
}

// MARK: - Delete / Report
private extension MomentsListViewController {

    func confirmDelete(_ vibe: MomentsPost) {
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

    func showReportReasons(for vibe: MomentsPost, sourceView: UIView) {
        let sheet = UIAlertController(title: "Report moment", message: "Why are you reporting this moment?", preferredStyle: .actionSheet)
        MomentsListViewModel.reportReasons.forEach { reason in
            sheet.addAction(UIAlertAction(title: reason, style: .default) { [weak self] _ in
                guard let self else { return }
                self.aActivityIndicator.show()
                self.viewModel.reportVibe(vibeId: vibe.id, reason: reason) { [weak self] result in
                    guard let self else { return }
                    self.handleRemoval(result, successMessage: "Thanks for reporting. We'll review this moment.")
                    guard case .success = result else { return }
                    self.onVibeRemoved?(vibe.id)
                    if self.isOtherUserScope, self.viewModel.vibes.isEmpty {
                        self.navigationController?.popViewController(animated: true)
                    }
                }
            })
        }
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        present(sheet, animated: true)
    }

    func confirmBlock(_ vibe: MomentsPost) {
        let name = vibe.author?.displayName ?? "this user"
        let alert = UIAlertController(title: "Block \(name)?",
                                      message: "They won't be able to see your profile or contact you, and you won't see their moments.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: "Block", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.aActivityIndicator.show()
            self.viewModel.blockAuthor(of: vibe) { [weak self] result in
                guard let self else { return }
                self.aActivityIndicator.hide()
                switch result {
                case .success(let rows):
                    self.tableView.deleteRows(at: rows.map { IndexPath(row: $0, section: 0) }, with: .fade)
                    self.updateEmptyState()
                    self.aCustomToastView.show(message: "\(name) has been blocked")
                    if self.isOtherUserScope {
                        self.navigationController?.popToRootViewController(animated: true)
                    }
                case .failure(let error):
                    self.aCustomToastView.show(message: error.message)
                }
            }
        })
        present(alert, animated: true)
    }

    func handleRemoval(_ result: Result<Int?, MomentsError>, successMessage: String) {
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
/// Title, icon and spacing are laid out in the storyboard.
final class MomentsFilterChipButton: UIButton {

    override func awakeFromNib() {
        super.awakeFromNib()
        layer.cornerRadius = bounds.height / 2
        layer.borderColor = AppColor.Gallery.cgColor
        setImage(image(for: .normal)?.withRenderingMode(.alwaysTemplate), for: .normal)
        applyStyle()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
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
        setTitleColor(foreground, for: .normal)
        setTitleColor(foreground, for: .selected)
        tintColor = foreground
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
