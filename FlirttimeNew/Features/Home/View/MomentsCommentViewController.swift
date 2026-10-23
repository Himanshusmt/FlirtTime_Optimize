//
//  MomentsCommentViewController.swift
//  FlirttimeNew
//
//  Comment sheet for a moment (presented at medium / large detents).
//

import UIKit
import Combine
import IQKeyboardManagerSwift

final class MomentsCommentViewController: BaseViewController {

    var onCommentsCountChanged: ((Int) -> Void)?
    /// Called after the sheet is dismissed so the presenting Moments list can push the profile.
    var onOpenUser: ((OtherUserProfileRouter.Seed) -> Void)?
    var vibeId: String { viewModel.vibeId }

    private var isResolvingMention = false
    private var cancellables: Set<AnyCancellable> = []

    private let viewModel: MomentsCommentViewModel
    private var wasKeyboardManagerEnabled = true
    private var wasAutoToolbarEnabled = true

    /// The comment being replied to, shown in the "Replying to" banner.
    private var replyTarget: MomentsComment?
    /// "@name " put in the field when a reply starts, so it can be removed on cancel.
    private var replyPrefix: String?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Comments"
        label.font = UIFont.fredoka(.bold, size: 18)
        label.textColor = AppColor.MineShaft
        label.textAlignment = .center
        return label
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.sectionHeaderHeight = 0
        tableView.sectionFooterHeight = 0
        tableView.sectionHeaderTopPadding = 0
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(MomentsCommentThreadCell.self, forCellReuseIdentifier: MomentsCommentThreadCell.identifier)
        return tableView
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = AppColor.Punch
        spinner.hidesWhenStopped = true
        return spinner
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No comments yet.\nStart the conversation."
        label.font = UIFont.fredoka(.regular, size: 15)
        label.textColor = AppColor.DoveGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private let inputBarView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColor.AppWhite
        return view
    }()

    // MARK: Reply banner

    private let replyBannerView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColor.WildSand
        view.isHidden = true
        return view
    }()

    private let replyBannerLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 13)
        label.textColor = AppColor.DoveGray
        return label
    }()

    private lazy var replyCancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        button.tintColor = AppColor.DoveGray
        button.accessibilityLabel = "Cancel reply"
        button.addAction(UIAction { [weak self] _ in self?.cancelReply() }, for: .touchUpInside)
        return button
    }()

    // MARK: Emoji bar

    private lazy var emojiBar: MomentsCommentEmojiBar = {
        let bar = MomentsCommentEmojiBar()
        bar.onSelect = { [weak self] emoji in self?.insertEmoji(emoji) }
        return bar
    }()

    // MARK: Input

    private let inputAvatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.backgroundColor = AppColor.AthensGray
        return imageView
    }()

    private lazy var commentTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Add a comment…"
        textField.font = UIFont.fredoka(.regular, size: 15)
        textField.textColor = AppColor.MineShaft
        textField.backgroundColor = AppColor.WildSand
        textField.layer.cornerRadius = 20
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        textField.leftViewMode = .always
        textField.returnKeyType = .send
        textField.isEnabled = false
        textField.delegate = self
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        return textField
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "Btn_Send_Message"), for: .normal)
        button.imageView?.contentMode = .scaleAspectFill
        button.contentHorizontalAlignment = .fill
        button.contentVerticalAlignment = .fill
        button.layer.cornerRadius = 20
        button.clipsToBounds = true
        button.accessibilityLabel = "Send comment"
        button.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        return button
    }()

    init(vibe: MomentsPost) {
        viewModel = MomentsCommentViewModel(vibeId: vibe.id)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        refreshSendState()
        setSocketBinding()
        loadComments()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The input bar follows the keyboard itself; IQKeyboardManager would shift it twice.
        wasKeyboardManagerEnabled = IQKeyboardManager.shared.isEnabled
        wasAutoToolbarEnabled = IQKeyboardManager.shared.enableAutoToolbar
        IQKeyboardManager.shared.isEnabled = false
        IQKeyboardManager.shared.enableAutoToolbar = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IQKeyboardManager.shared.isEnabled = wasKeyboardManagerEnabled
        IQKeyboardManager.shared.enableAutoToolbar = wasAutoToolbarEnabled
    }

    // MARK: - UI

    private func setUI() {
        let headerSeparator = UIView()
        headerSeparator.backgroundColor = AppColor.Iron
        let inputSeparator = UIView()
        inputSeparator.backgroundColor = AppColor.Iron

        [replyBannerLabel, replyCancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            replyBannerView.addSubview($0)
        }

        let inputRow = UIView()
        [inputAvatarImageView, commentTextField, sendButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputRow.addSubview($0)
        }

        let inputStack = UIStackView(arrangedSubviews: [replyBannerView, emojiBar, inputRow])
        inputStack.axis = .vertical
        [inputSeparator, inputStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputBarView.addSubview($0)
        }
        [titleLabel, headerSeparator, tableView, loadingIndicator, emptyStateLabel, inputBarView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            headerSeparator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            headerSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            tableView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBarView.topAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 40),

            emptyStateLabel.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 40),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            inputSeparator.topAnchor.constraint(equalTo: inputBarView.topAnchor),
            inputSeparator.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor),
            inputSeparator.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor),
            inputSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            inputStack.topAnchor.constraint(equalTo: inputSeparator.bottomAnchor),
            inputStack.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor),
            inputStack.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor),
            inputStack.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor),

            replyBannerView.heightAnchor.constraint(equalToConstant: 34),
            replyBannerLabel.leadingAnchor.constraint(equalTo: replyBannerView.leadingAnchor, constant: 16),
            replyBannerLabel.centerYAnchor.constraint(equalTo: replyBannerView.centerYAnchor),
            replyBannerLabel.trailingAnchor.constraint(lessThanOrEqualTo: replyCancelButton.leadingAnchor, constant: -8),
            replyCancelButton.trailingAnchor.constraint(equalTo: replyBannerView.trailingAnchor, constant: -8),
            replyCancelButton.centerYAnchor.constraint(equalTo: replyBannerView.centerYAnchor),
            replyCancelButton.widthAnchor.constraint(equalToConstant: 32),
            replyCancelButton.heightAnchor.constraint(equalToConstant: 32),

            emojiBar.heightAnchor.constraint(equalToConstant: 44),

            inputRow.heightAnchor.constraint(equalToConstant: 56),
            inputAvatarImageView.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor, constant: 16),
            inputAvatarImageView.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            inputAvatarImageView.widthAnchor.constraint(equalToConstant: 32),
            inputAvatarImageView.heightAnchor.constraint(equalToConstant: 32),

            commentTextField.leadingAnchor.constraint(equalTo: inputAvatarImageView.trailingAnchor, constant: 10),
            commentTextField.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            commentTextField.heightAnchor.constraint(equalToConstant: 40),

            sendButton.leadingAnchor.constraint(equalTo: commentTextField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40)
        ])

        inputAvatarImageView.loadImage(path: viewModel.currentUserAuthor.profilePicture,
                                       placeholder: UIImage(named: "dummy_Profile"))
    }

    private func refreshSendState() {
        let hasText = !(commentTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText && commentTextField.isEnabled && !viewModel.isSending
        sendButton.alpha = sendButton.isEnabled ? 1 : 0.5
        emojiBar.isEnabled = commentTextField.isEnabled
    }

    private func updateEmptyState() {
        emptyStateLabel.text = "No comments yet.\nStart the conversation."
        emptyStateLabel.isHidden = !viewModel.isEmpty
    }

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
        guard update.momentId == viewModel.vibeId else { return }
        switch viewModel.applySocket(update) {
        case .inserted(let indexPath, let isNewThread):
            emptyStateLabel.isHidden = true
            apply(isNewThread ? .insert(indexPath.section) : .reload(indexPath.section))
            onCommentsCountChanged?(viewModel.totalCount)
        case .deleted(let section, let removedThread):
            if replyTarget?.id == update.commentId { cancelReply() }
            apply(removedThread ? .delete(section) : .reload(section), animation: .fade)
            updateEmptyState()
            onCommentsCountChanged?(viewModel.totalCount)
        case .liked(let commentId):
            reconfigureRow(forCommentId: commentId)
        case .none:
            break
        }
    }

    // MARK: - Data

    private func loadComments() {
        loadingIndicator.startAnimating()
        viewModel.loadComments { [weak self] result in
            guard let self else { return }
            self.loadingIndicator.stopAnimating()
            switch result {
            case .success:
                self.tableView.reloadData()
                self.updateEmptyState()
                self.onCommentsCountChanged?(self.viewModel.totalCount)
            case .failure(let error):
                self.emptyStateLabel.text = error.message
                self.emptyStateLabel.isHidden = false
            }
            self.commentTextField.isEnabled = true
            self.refreshSendState()
        }
    }

    private func loadMoreComments() {
        viewModel.loadMoreIfNeeded { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.tableView.reloadData()
                self.onCommentsCountChanged?(self.viewModel.totalCount)
            case .failure(let error):
                self.aCustomToastView.show(message: error.message)
            }
        }
    }

    @objc private func textChanged() {
        if let text = commentTextField.text, text.count > viewModel.maxCommentLength {
            commentTextField.text = String(text.prefix(viewModel.maxCommentLength))
        }
        refreshSendState()
    }

    @objc private func sendTapped() {
        guard sendButton.isEnabled, let text = commentTextField.text else { return }
        let target = replyTarget
        let prefix = replyPrefix
        send(text, replyTo: target) { [weak self] succeeded in
            guard let self, !succeeded else { return }
            self.commentTextField.text = text
            if let target, self.replyTarget == nil { self.startReply(to: target, prefix: prefix) }
            self.refreshSendState()
        }
        commentTextField.text = nil
        endReply()
        refreshSendState()
    }

    /// Inserts the tapped emoji at the cursor, or at the end when the field isn't being edited.
    private func insertEmoji(_ emoji: String) {
        guard commentTextField.isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let text = commentTextField.text ?? ""
        guard text.count + emoji.count <= viewModel.maxCommentLength else { return }
        if commentTextField.isFirstResponder, let range = commentTextField.selectedTextRange {
            commentTextField.replace(range, withText: emoji)
        } else {
            commentTextField.text = text + emoji
        }
        refreshSendState()
    }

    private func send(_ text: String, replyTo target: MomentsComment?, completion: @escaping (Bool) -> Void) {
        viewModel.addComment(text, replyTo: target) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let added):
                self.emptyStateLabel.isHidden = true
                self.apply(added.isNewThread ? .insert(added.indexPath.section) : .reload(added.indexPath.section))
                self.scrollToRowIfValid(added.indexPath)
                self.onCommentsCountChanged?(self.viewModel.totalCount)
                completion(true)
            case .failure(let error):
                self.aCustomToastView.show(message: error.message)
                completion(false)
            }
            self.refreshSendState()
        }
    }

    // MARK: - Reply

    private func startReply(to comment: MomentsComment, prefix: String? = nil) {
        let name = comment.author?.displayName ?? ""
        replyTarget = comment
        replyBannerLabel.text = name.isEmpty ? "Replying to comment" : "Replying to @\(name)"
        let mention = prefix ?? (name.isEmpty ? nil : "@\(name.replacingOccurrences(of: " ", with: "")) ")
        if let mention, !(commentTextField.text ?? "").hasPrefix(mention) {
            commentTextField.text = mention + (commentTextField.text ?? "")
        }
        replyPrefix = mention
        UIView.animate(withDuration: 0.2) { self.replyBannerView.isHidden = false }
        commentTextField.becomeFirstResponder()
        refreshSendState()
    }

    /// Clears the reply state but leaves the text as is.
    private func endReply() {
        replyTarget = nil
        replyPrefix = nil
        guard !replyBannerView.isHidden else { return }
        UIView.animate(withDuration: 0.2) { self.replyBannerView.isHidden = true }
    }

    private func cancelReply() {
        if let prefix = replyPrefix, let text = commentTextField.text, text.hasPrefix(prefix) {
            commentTextField.text = String(text.dropFirst(prefix.count))
        }
        endReply()
        refreshSendState()
    }

    // MARK: - Like / Delete / Replies

    private func toggleLike(commentId: String) {
        viewModel.toggleLike(commentId: commentId) { [weak self] result in
            guard let self else { return }
            self.reconfigureRow(forCommentId: commentId)
            if case .failure(let error) = result {
                self.aCustomToastView.show(message: error.message)
            }
        }
        reconfigureRow(forCommentId: commentId)
    }

    private func reconfigureRow(forCommentId id: String) {
        guard let indexPath = viewModel.indexPath(forCommentId: id),
              let comment = viewModel.comment(at: indexPath),
              let cell = tableView.cellForRow(at: indexPath) as? MomentsCommentThreadCell else { return }
        cell.updateLike(isLiked: comment.isLiked ?? false, count: comment.likesCount ?? 0)
    }

    private func toggleReplies(section: Int) {
        guard viewModel.threads.indices.contains(section) else { return }
        let commentId = viewModel.threads[section].comment.id
        viewModel.toggleReplies(section: section) { [weak self] result in
            guard let self else { return }
            // The section may have moved if comments changed while replies were loading.
            if let section = self.viewModel.threads.firstIndex(where: { $0.comment.id == commentId }) {
                self.applyRepliesChange(section: section)
            } else {
                self.tableView.reloadData()
            }
            if case .failure(let error) = result {
                self.aCustomToastView.show(message: error.message)
            }
        }
        if let section = viewModel.threads.firstIndex(where: { $0.comment.id == commentId }),
           viewModel.isLoadingReplies(section: section) {
            updateRepliesToggleCell(section: section)
        }
    }

    /// Inserts or deletes reply rows so the parent comment (and its avatar) is not recreated.
    private func applyRepliesChange(section: Int) {
        updateRepliesToggleCell(section: section)
        let tableRows = tableView.numberOfRows(inSection: section)
        let modelRows = viewModel.numberOfRows(in: section)
        guard tableView.numberOfSections == viewModel.threads.count,
              section < tableView.numberOfSections,
              view.window != nil else {
            tableView.reloadData()
            return
        }
        guard tableRows != modelRows else { return }

        let othersMatch = (0..<viewModel.threads.count).allSatisfy { other in
            other == section || tableView.numberOfRows(inSection: other) == viewModel.numberOfRows(in: other)
        }
        let canInsert = tableRows == 1 && modelRows > 1
        let canDelete = modelRows == 1 && tableRows > 1
        guard othersMatch, canInsert || canDelete else {
            UIView.performWithoutAnimation {
                tableView.reloadSections(IndexSet(integer: section), with: .none)
            }
            return
        }

        let paths = (1..<(canInsert ? modelRows : tableRows)).map { IndexPath(row: $0, section: section) }
        tableView.performBatchUpdates {
            if canInsert {
                tableView.insertRows(at: paths, with: .fade)
            } else {
                tableView.deleteRows(at: paths, with: .fade)
            }
        }
    }

    private func updateRepliesToggleCell(section: Int) {
        guard viewModel.threads.indices.contains(section),
              let cell = tableView.cellForRow(at: IndexPath(row: 0, section: section)) as? MomentsCommentThreadCell else { return }
        cell.updateRepliesToggle(thread: viewModel.threads[section],
                                 isLoading: viewModel.isLoadingReplies(section: section))
    }

    // MARK: - Table updates

    private enum SectionChange {
        case reload(Int)
        case insert(Int)
        case delete(Int)
    }

    /// Animates a one-section change only when every other section already matches the view model.
    /// Otherwise it reloads the whole table, so a mismatch can never raise an "invalid update" exception.
    private func apply(_ change: SectionChange, animation: UITableView.RowAnimation = .automatic) {
        let tableSections = tableView.numberOfSections
        let modelSections = viewModel.threads.count
        let rowsMatch: (Int, Int) -> Bool = { tableSection, modelSection in
            self.tableView.numberOfRows(inSection: tableSection) == self.viewModel.numberOfRows(in: modelSection)
        }
        let isConsistent: Bool
        switch change {
        case .reload(let section):
            isConsistent = tableSections == modelSections && section < modelSections
                && (0..<modelSections).allSatisfy { $0 == section || rowsMatch($0, $0) }
        case .insert(let section):
            isConsistent = tableSections + 1 == modelSections && section < modelSections
                && (0..<tableSections).allSatisfy { rowsMatch($0, $0 < section ? $0 : $0 + 1) }
        case .delete(let section):
            isConsistent = tableSections == modelSections + 1 && section < tableSections
                && (0..<modelSections).allSatisfy { rowsMatch($0 < section ? $0 : $0 + 1, $0) }
        }
        guard isConsistent, view.window != nil else {
            tableView.reloadData()
            return
        }
        switch change {
        case .reload(let section):
            tableView.reloadSections(IndexSet(integer: section), with: animation)
        case .insert(let section):
            tableView.insertSections(IndexSet(integer: section), with: animation)
        case .delete(let section):
            tableView.deleteSections(IndexSet(integer: section), with: animation)
        }
    }

    private func scrollToRowIfValid(_ indexPath: IndexPath) {
        guard indexPath.section < tableView.numberOfSections,
              indexPath.row < tableView.numberOfRows(inSection: indexPath.section) else { return }
        tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
    }

    private func confirmDelete(commentId: String) {
        let alert = UIAlertController(title: "Delete comment?", message: "This can't be undone.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteComment(id: commentId)
        })
        present(alert, animated: true)
    }

    private func openMention(_ username: String) {
        guard !isResolvingMention else { return }
        isResolvingMention = true
        viewModel.resolveMentionedUser(username: username) { [weak self] result in
            guard let self else { return }
            self.isResolvingMention = false
            switch result {
            case .success(let seed):
                let open = self.onOpenUser
                self.dismiss(animated: true) { open?(seed) }
            case .failure(let error):
                self.aCustomToastView.show(message: error.message)
            }
        }
    }

    private func deleteComment(id: String) {
        viewModel.deleteComment(id: id) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let removed):
                if self.replyTarget?.id == id { self.cancelReply() }
                self.apply(removed.removedThread ? .delete(removed.section) : .reload(removed.section), animation: .fade)
                self.updateEmptyState()
                self.onCommentsCountChanged?(self.viewModel.totalCount)
            case .failure(let error):
                self.aCustomToastView.show(message: error.message)
            }
        }
    }
}

// MARK: - UITableViewDelegate
extension MomentsCommentViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.section >= viewModel.threads.count - 3 {
            loadMoreComments()
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? { nil }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { .leastNonzeroMagnitude }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { .leastNonzeroMagnitude }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let comment = viewModel.comment(at: indexPath) else { return nil }
        let reply = UIContextualAction(style: .normal, title: "Reply") { [weak self] _, _, done in
            self?.startReply(to: comment)
            done(true)
        }
        reply.image = UIImage(systemName: "arrowshape.turn.up.left")
        reply.backgroundColor = AppColor.DoveGray
        var actions = [reply]
        if viewModel.canDelete(comment) {
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
                self?.confirmDelete(commentId: comment.id)
                done(false)
            }
            delete.image = UIImage(systemName: "trash")
            actions.insert(delete, at: 0)
        }
        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let comment = viewModel.comment(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIMenuElement] = [
                UIAction(title: comment.isLiked == true ? "Unlike" : "Like",
                         image: UIImage(systemName: comment.isLiked == true ? "heart.slash" : "heart")) { [weak self] _ in
                    self?.toggleLike(commentId: comment.id)
                },
                UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self] _ in
                    self?.startReply(to: comment)
                },
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = comment.body
                }
            ]
            if self.viewModel.canDelete(comment) {
                actions.append(UIAction(title: "Delete comment", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.confirmDelete(commentId: comment.id)
                })
            }
            return UIMenu(children: actions)
        }
    }
}

// MARK: - UITableViewDataSource
extension MomentsCommentViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.threads.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows(in: section)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: MomentsCommentThreadCell.identifier, for: indexPath) as? MomentsCommentThreadCell,
              let comment = viewModel.comment(at: indexPath) else {
            return UITableViewCell()
        }
        let isReply = indexPath.row > 0
        let section = indexPath.section
        cell.configure(with: comment,
                       isReply: isReply,
                       thread: isReply ? nil : viewModel.threads[section],
                       isLoadingReplies: !isReply && viewModel.isLoadingReplies(section: section),
                       canDelete: viewModel.canDelete(comment))
        cell.onLike = { [weak self] in self?.toggleLike(commentId: comment.id) }
        cell.onReply = { [weak self] in self?.startReply(to: comment) }
        cell.onDelete = { [weak self] in self?.confirmDelete(commentId: comment.id) }
        cell.onToggleReplies = { [weak self, weak cell] in
            guard let self, let cell, let current = self.tableView.indexPath(for: cell) else { return }
            self.toggleReplies(section: current.section)
        }
        cell.onMention = { [weak self] username in self?.openMention(username) }
        return cell
    }
}

// MARK: - UITextFieldDelegate
extension MomentsCommentViewController: UITextFieldDelegate {

    func textFieldDidBeginEditing(_ textField: UITextField) {
        guard let sheet = sheetPresentationController, sheet.selectedDetentIdentifier != .large else { return }
        sheet.animateChanges {
            sheet.selectedDetentIdentifier = .large
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return false
    }
}

// MARK: - Emoji bar

/// Quick emojis from the old FlirtTime comment sheet; a tap adds the emoji to the comment field.
final class MomentsCommentEmojiBar: UIView {

    static let emojis = ["❤️", "🔥", "😍", "❤️‍🔥", "😎", "🙌", "😮"]

    var onSelect: ((String) -> Void)?

    var isEnabled = true {
        didSet {
            buttons.forEach { $0.isEnabled = isEnabled }
            alpha = isEnabled ? 1 : 0.5
        }
    }

    private var buttons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        buttons = Self.emojis.map { emoji in
            let button = UIButton(type: .system)
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 26)
            button.accessibilityLabel = "Add \(emoji)"
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button else { return }
                UIView.animate(withDuration: 0.1, animations: {
                    button.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
                }, completion: { _ in
                    UIView.animate(withDuration: 0.1) { button.transform = .identity }
                })
                self.onSelect?(emoji)
            }, for: .touchUpInside)
            return button
        }
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
