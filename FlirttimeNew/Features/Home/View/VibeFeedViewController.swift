//
//  VibeFeedViewController.swift
//  FlirttimeNew
//
//  Moments tab: vibe feed with a "what's new" composer, like / comment / gift actions.
//

import UIKit
import Combine

final class VibeFeedViewController: BaseViewController {

    private let viewModel = VibeFeedViewModel()
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
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.backgroundColor = AppColor.AppWhite
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 160
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(VibeTableViewCell.self, forCellReuseIdentifier: VibeTableViewCell.identifier)
        tableView.contentInset.bottom = VibeFeedViewController.centerTabButtonOverlap
        tableView.verticalScrollIndicatorInsets.bottom = VibeFeedViewController.centerTabButtonOverlap
        return tableView
    }()

    private let refreshControl = UIRefreshControl()

    private let composerAvatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.backgroundColor = AppColor.AthensGray
        return imageView
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No vibes yet.\nBe the first to share what's on your mind!"
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        setUploadBinding()
        loadFeed(showLoader: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: false)
        refreshComposerAvatar()
    }

    // MARK: - UI

    private func setUI() {
        [logoImageView, notificationButton, newVibeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            topBarView.addSubview($0)
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
        tableView.tableHeaderView = makeComposerHeader()
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

    /// "What's new?" row from OneVibe's feed; tapping it opens the composer.
    private func makeComposerHeader() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 68))

        let promptLabel = UILabel()
        promptLabel.text = "What's new?"
        promptLabel.font = UIFont.fredoka(.regular, size: 15)
        promptLabel.textColor = AppColor.SilverChalice

        let pill = UIView()
        pill.backgroundColor = AppColor.WildSand
        pill.layer.cornerRadius = 20
        pill.isUserInteractionEnabled = false

        let separator = UIView()
        separator.backgroundColor = AppColor.Iron

        [composerAvatarImageView, pill, promptLabel, separator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }

        NSLayoutConstraint.activate([
            composerAvatarImageView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            composerAvatarImageView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            composerAvatarImageView.widthAnchor.constraint(equalToConstant: 40),
            composerAvatarImageView.heightAnchor.constraint(equalToConstant: 40),

            pill.leadingAnchor.constraint(equalTo: composerAvatarImageView.trailingAnchor, constant: 12),
            pill.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            pill.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 40),

            promptLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
            promptLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
            promptLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        header.isAccessibilityElement = true
        header.accessibilityLabel = "What's new? Post a vibe"
        header.accessibilityTraits = .button
        header.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(newVibeTapped)))
        return header
    }

    private func refreshComposerAvatar() {
        composerAvatarImageView.loadImage(path: viewModel.currentUserAuthor.profilePicture,
                                          placeholder: UIImage(named: "dummy_Profile"))
    }

    private func updateEmptyState() {
        emptyStateLabel.isHidden = !viewModel.vibes.isEmpty
    }

    // MARK: - Upload progress

    private func setUploadBinding() {
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
                    self.viewModel.prepend(vibe)
                    self.tableView.reloadData()
                    self.updateEmptyState()
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

// MARK: - Like / Comment / Gift
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

    func vibeCellDidTapMore(_ cell: VibeTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let vibe = viewModel.vibes[indexPath.row]

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if viewModel.isOwnVibe(vibe) {
            sheet.addAction(UIAlertAction(title: "Delete vibe", style: .destructive) { [weak self] _ in
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

// MARK: - Delete / Report
private extension VibeFeedViewController {

    func confirmDelete(_ vibe: Vibe) {
        aDeleteCustomPopUp.show(message: "Are you sure you want to delete this vibe?",
                                button1Text: Constants.AlertButtons.cancel,
                                button2Text: Constants.AlertButtons.yesDelete) { [weak self] in
            guard let self else { return }
            self.aActivityIndicator.show()
            self.viewModel.deleteVibe(vibeId: vibe.id) { [weak self] result in
                self?.handleRemoval(result, successMessage: "Vibe deleted")
            }
        }
    }

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
