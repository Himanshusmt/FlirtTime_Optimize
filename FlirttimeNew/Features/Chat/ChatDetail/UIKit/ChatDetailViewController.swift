import UIKit
import Combine
import IQKeyboardManagerSwift

// MARK: - ChatDetailViewController

final class ChatDetailViewController: UIViewController {

    // MARK: - Properties

    let viewModel: ChatDetailViewModel
    var cancellables = Set<AnyCancellable>()
    var dataSource: ChatMessagesDataSource?
    var keyboardHeight: CGFloat = 0
    let keyboardTrackingView = ChatKeyboardTrackingView()
    var keyboardTrackingDisplayLink: CADisplayLink?
    var keyboardTrackingProxy: KeyboardDisplayLinkProxy?
    var isApplyingKeyboardTracking = false

    // MARK: - Config

    var onBack: (() -> Void)?
    var onProfileTap: (() -> Void)?
    var selectedId: String = ""
    var selectedUserChatID: String = ""
    var user: UserRes?
    var activeStatus: String = ""
    var isGroupChat: Bool = false
    var isGroupParticipant: Bool = true
    var groupTitle: String = ""
    var groupAvatarUrl: String = ""
    var isChannel: Bool = false
    var channelId: String = ""
    var canSendInChannel: Bool = false
    var expandedMessageIds: Set<String> = []
    var isAlreadyFollowingChannel: Bool = false
    var participantsCount: Int?
    var unreadCount: Int = 0
    var hasScrolledToUnread = false

    // MARK: - Subviews

    lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: ChatMessagesLayout.create())
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.alwaysBounceVertical = true
        cv.showsVerticalScrollIndicator = false
        cv.keyboardDismissMode = .interactive
        cv.contentInsetAdjustmentBehavior = .never
        return cv
    }()

    let scrollDownButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.backgroundColor = .white
        btn.layer.cornerRadius = 18
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.15
        btn.layer.shadowOffset = CGSize(width: 0, height: 2)
        btn.layer.shadowRadius = 4
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        btn.setImage(UIImage(systemName: "chevron.down", withConfiguration: config), for: .normal)
        btn.tintColor = ChatTheme.primary
        btn.isHidden = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    var newMessageCount = 0

    let scrollDownBadge: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.semibold, size: 10)
        lbl.textColor = .white
        lbl.backgroundColor = .systemRed
        lbl.textAlignment = .center
        lbl.layer.cornerRadius = 9
        lbl.layer.masksToBounds = true
        lbl.isHidden = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    var navBar: ChatDetailNavBar?
    var emptyProfileCard: ChatEmptyProfileCardView?

    let pinnedBanner = ChatPinnedMessageBanner()
    let groupCallRejoinBanner = ChatGroupCallRejoinBanner()
    /// Keeps pinned banner under the rejoin banner when both are visible.
    var pinnedBannerTopConstraint: NSLayoutConstraint?

    let channelFollowBanner = ChatChannelFollowBanner()

    var selectionHeaderView: ChatSelectionHeaderBar?
    var selectionActionView: ChatSelectionActionBar?

    var attachmentPanel: AttachmentPanelView?

    var pendingAttachmentFromKeyboard: Bool = false

    var cameraOverlay: CameraOverlayView?

    var messageToDelete: ConversationMessage?
    var deleteForEveryone = false
    var isOpeningSharedContent = false

    let inputBar = ChatMessageInputBar()
    let replyBanner = ChatReplyBanner()
    let editBanner = ChatEditBanner()
    let audioComposer = ChatAudioComposerView()
    let typingIndicator = ChatTypingIndicator()
    var isTypingActive = false
    let mentionTable = MentionAutocompleteTableView()
    let blockOverlay = ChatBlockOverlayView()

    let nonParticipantBar: UIView = {
        let v = UIView()
        v.backgroundColor = ChatTheme.primary.withAlphaComponent(0.1)
        v.layer.cornerRadius = 8
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let nonParticipantLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.medium, size: 14)
        lbl.textColor = .gray
        lbl.text = ChatStrings.chat_noLongerMember.localizedString()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    let channelReadOnlyBar: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    lazy var channelReadOnlyContent: UIStackView = {
        let s = UIStackView(arrangedSubviews: [channelReadOnlyIcon, channelReadOnlyLabel])
        s.axis = .horizontal
        s.spacing = 8
        s.alignment = .center
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    let channelReadOnlyIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "megaphone"))
        iv.tintColor = ChatTheme.primary
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
        ])
        return iv
    }()

    let channelReadOnlyLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.medium, size: 12)
        lbl.textColor = .gray
        lbl.text = ChatStrings.chat_onlyAdminsCanSend.localizedString()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    let channelFollowBarButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(ChatStrings.chat_followChannel.localizedString(), for: .normal)
        btn.titleLabel?.font = UIFont.chat(.semibold, size: 12)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = ChatTheme.primary
        btn.layer.cornerRadius = 4
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 100),
            btn.heightAnchor.constraint(equalToConstant: 28),
        ])
        return btn
    }()

    let inputContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let inputStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    let inputBottomFill: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    var inputContainerBottom: NSLayoutConstraint?
    var channelContentCenterX: NSLayoutConstraint?
    var channelContentLeading: NSLayoutConstraint?
    var mentionTableHeight: NSLayoutConstraint?
    var audioComposerHeight: NSLayoutConstraint?
    var scrollDownButtonBottom: NSLayoutConstraint?
    var typingBottomConstraint: NSLayoutConstraint?
    var initialSnapshotApplied = false
    var initialSnapshotAppliedAt: Date?
    var previousSelectedIds: Set<String> = []
    var wasInSelectionMode = false
    private var hasSetInitialInsets = false
    private var isCollectionViewRevealed = false
    private var inAppBanner: ChatInAppNotificationBanner?

    init(viewModel: ChatDetailViewModel, unreadCount: Int = 0) {
        self.viewModel = viewModel
        self.unreadCount = unreadCount
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        keyboardTrackingDisplayLink?.invalidate()
        cancellables.removeAll()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        collectionView.alpha = 0

        DispatchQueue.global(qos: .utility).async {
            _ = EmojiCatalog.shared
        }

        IQKeyboardManager.shared.isEnabled = false
        IQKeyboardManager.shared.enableAutoToolbar = false

        setupCollectionView()
        setupNavBar()
        setupPinnedBanner()
        setupGroupCallRejoinBanner()
        setupChannelFollowBanner()
        setupInputSystem()
        setupScrollDownButton()
        setupNonParticipantBar()
        setupKeyboardObservers()
        setupScreenshotDetection()
        setupDataSource()

        applyInitialMessagesIfAvailable()

        bindViewModel()
        bindInputActions()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissChatDetail),
            name: NSNotification.Name("DismissChatDetail"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleConversationRemovedByServer(_:)),
            name: .conversationRemovedByServer, object: nil
        )

        bindInAppBanner()
        view.enforceRTLIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasSetInitialInsets, collectionView.frame.height > 0 {
            hasSetInitialInsets = true
            if keyboardHeight == 0, !inputBar.textView.isFirstResponder {
                inputContainerBottom?.constant = inputBarBottomConstant()
            }
            updateContentInsets()
            if initialSnapshotApplied {
                scrollToInitialPosition()//scrollToBottomImmediate()
                scheduleInitialReveal()
            } else if isChannel {
                DispatchQueue.main.async {
                    self.updateContentInsets()
                    self.scrollToInitialPosition()//self.scrollToBottomImmediate()
                    self.scheduleInitialReveal()
                }
            }
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if keyboardHeight == 0, !inputBar.textView.isFirstResponder {
            inputContainerBottom?.constant = inputBarBottomConstant()
        }
        if initialSnapshotApplied, collectionView.frame.height > 0 {
            scheduleInitialReveal()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        MessageCellModel.flushHeightCache()
        collectionView.collectionViewLayout.invalidateLayout()
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        })
    }

    func presentEmojiPickerSheet(onEmojiSelected: @escaping (String) -> Void) {
        let picker = EmojiPickerSheet()
        picker.onEmojiSelected = onEmojiSelected
        picker.present(in: view)
    }

    @objc private func handleDismissChatDetail() {
        // Only act if this screen is for a channel
        guard isChannel else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onBack?()
        }
    }
    
    func revealCollectionView() {
        guard !isCollectionViewRevealed else { return }
        isCollectionViewRevealed = true
        collectionView.alpha = 1
    }

    func scheduleInitialReveal() {
        guard !isCollectionViewRevealed else { return }
        collectionView.layoutIfNeeded()
        updateContentInsets(animated: false)
        scrollToInitialPosition()
        revealCollectionView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hidesBottomBarWhenPushed = true
        self.tabBarController?.tabBar.isHidden = true
        if keyboardHeight == 0, !inputBar.textView.isFirstResponder {
            inputContainerBottom?.constant = inputBarBottomConstant()
        }
        IQKeyboardManager.shared.isEnabled = false
        IQKeyboardManager.shared.enableAutoToolbar = false
        restoreDraft()
        resetKeyboardLayoutIfNeeded()

        ChatNotificationState.shared.isInChatModule = true
        ChatNotificationState.shared.isShowingChatDetail = true
        let convId = isChannel ? channelId : selectedId
        ChatNotificationState.shared.activeConversationId = convId.isEmpty ? nil : convId

        if !convId.isEmpty {
            ChatNotificationState.clearNotifications(for: convId)
        }
        refreshGroupCallRejoinBanner()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isChannel {
            viewModel.isChannelFollowed = isAlreadyFollowingChannel
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        let isLeavingChatScreen = isMovingFromParent
            || isBeingDismissed
            || navigationController?.isBeingDismissed == true

        guard isLeavingChatScreen else { return }

        stopKeyboardTracking()
        self.tabBarController?.tabBar.isHidden = false
        saveDraft()
        dismissAttachmentPanel()

        viewModel.userStoppedTyping()
        viewModel.prepareForReuse()
        viewModel.stopSocketListening()
        viewModel.stopUserStatusEmitting()

        ChatNotificationState.shared.isInChatModule = false
        ChatNotificationState.shared.isShowingChatDetail = false
        ChatNotificationState.shared.activeConversationId = nil

        IQKeyboardManager.shared.isEnabled = true
        IQKeyboardManager.shared.enableAutoToolbar = true
    }

    @objc private func appWillResignActive() {
        // If focus was already dropped (CallKit / presented call UI), pin the input
        // bar immediately. Don't force-resign — Control Center would dismiss the keyboard.
        if !inputBar.textView.isFirstResponder {
            resetKeyboardLayoutIfNeeded(animated: false)
        }
        if isChannel, !channelId.isEmpty, view.window != nil {
            ChatSocketManager.shared.setChannelViewing(channelId: channelId, active: false)
        }
    }

    @objc private func appDidBecomeActive() {
        resetKeyboardLayoutIfNeeded()
        viewModel.refreshMessages()
        if isChannel, !channelId.isEmpty, view.window != nil {
            ChatSocketManager.shared.setChannelViewing(channelId: channelId, active: true)
            viewModel.markChannelAsRead()
        } else if !viewModel.selectedId.isEmpty, !isChannel {
            viewModel.markConversationAsRead()
        }
    }

    @objc private func handleConversationRemovedByServer(_ note: Notification) {
        if let id = note.userInfo?["conversationId"] as? String, id == selectedId {
            navigationController?.popViewController(animated: true)
        }
    }

    private func indexPathForFirstUnreadMessage() -> IndexPath? {
        guard unreadCount > 0,
              let dataSource = dataSource else { return nil }

        let snapshot = dataSource.diffableDataSource?.snapshot()
        let allItems = snapshot?.itemIdentifiers ?? []

        guard allItems.count >= unreadCount else { return nil }

        // The first unread message is `unreadCount` items from the end
        let firstUnreadIndex = allItems.count - unreadCount
        let targetItem = allItems[firstUnreadIndex]
        
        return dataSource.indexPath(forItemId: targetItem.stableId)
    }
    
    func scrollToInitialPosition() {
        if unreadCount > 0, !hasScrolledToUnread,
           let indexPath = indexPathForFirstUnreadMessage() {
            hasScrolledToUnread = true
            if contentFitsOnScreen() {
                newMessageCount = 0
            } else {
                newMessageCount = unreadCount
            }
            updateScrollDownBadge()
            collectionView.scrollToItem(
                at: indexPath,
                at: .top,
                animated: false
            )
        } else if contentFitsOnScreen() {
            scrollToTopImmediate()
        } else {
            scrollToBottomImmediate()
        }
        updateScrollDownButtonVisibility()
    }
    
    
    func presentPinDurationSheet(messageId: String) {
        let sheet = PinDurationPickerSheet()
        sheet.onDurationSelected = { [weak self] duration in
            self?.viewModel.pinMessage(
                messageId: messageId,
                isPinned: true,
                pinDuration: duration.rawValue
            )
        }
        sheet.present(in: view)
    }

    // MARK: - In-App Notification Banner

    private func bindInAppBanner() {
        ChatNotificationState.shared.$pendingBanner
            .receive(on: DispatchQueue.main)
            .sink { [weak self] banner in
                guard let self, let banner else { return }
                // Only show banner for conversations the user is NOT currently viewing
                guard !ChatNotificationState.shared.isViewingConversation(banner.conversationId) else {
                    ChatNotificationState.shared.pendingBanner = nil
                    return
                }
                ChatNotificationState.shared.pendingBanner = nil
                // self.showInAppBanner(banner)
            }
            .store(in: &cancellables)
    }

    private func showInAppBanner(_ data: InAppChatBannerData) {
        inAppBanner?.forceRemove()
        inAppBanner = nil
        let banner = ChatInAppNotificationBanner(data: data) { [weak self] bannerData in
            guard let self else { return }
            ChatNotificationState.navigateFromBanner(bannerData)
        }
        banner.show(in: view, below: navBar)
        inAppBanner = banner
    }

    // MARK: - Scrolling

    @objc func didTapScrollToBottomButton() {
        if viewModel.isInHistoricalWindow {
            // We're in a pinned-message jump window; restore the live message tail.
            viewModel.returnToLatestMessages()
        } else {
            scrollToBottom(animated: true, userInitiated: true)
        }
    }

    func scrollToBottom(animated: Bool = true, userInitiated: Bool = false) {
        if userInitiated {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        newMessageCount = 0
        updateScrollDownBadge()
        scrollToBottomEdge(animated: animated)
    }

    func scrollToBottomImmediate() {
        scrollToBottomEdge(animated: false)
    }

    func scrollToTopImmediate() {
        collectionView.layoutIfNeeded()
        let minY = -collectionView.adjustedContentInset.top
        collectionView.setContentOffset(CGPoint(x: 0, y: minY), animated: false)
    }

    /// True when all messages fit within the visible scroll area (short / new chats).
    func contentFitsOnScreen() -> Bool {
        collectionView.layoutIfNeeded()
        let availableHeight = collectionView.bounds.height
            - collectionView.adjustedContentInset.top
            - collectionView.adjustedContentInset.bottom
        guard availableHeight > 0 else { return true }
        return collectionView.contentSize.height <= availableHeight
    }

    private func scrollToBottomEdge(animated: Bool) {
        collectionView.layoutIfNeeded()

        let targetY = collectionView.contentSize.height
            + collectionView.adjustedContentInset.bottom
            - collectionView.bounds.height
        let minY = -collectionView.adjustedContentInset.top
        collectionView.setContentOffset(CGPoint(x: 0, y: max(minY, targetY)),
                                        animated: animated)
    }

    func isInInitialScrollSettlingWindow(seconds: TimeInterval = 1.2) -> Bool {
        guard let appliedAt = initialSnapshotAppliedAt else { return false }
        return Date().timeIntervalSince(appliedAt) < seconds
    }

    func scrollToMessage(id: String, retryCount: Int = 0) {
        collectionView.layoutIfNeeded()
        if let indexPath = dataSource?.indexPath(forItemId: id) {
            let sections = collectionView.numberOfSections
            guard indexPath.section < sections else { return }
            let items = collectionView.numberOfItems(inSection: indexPath.section)
            guard indexPath.item < items else { return }
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.highlightMessage(at: indexPath)
            }
            return
        }
        // Snapshot may still be applying after a window jump — retry briefly
        if retryCount < 8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.scrollToMessage(id: id, retryCount: retryCount + 1)
            }
            return
        }
        // Avoid forceScroll loop; soft path can load the message if missing from memory
        if viewModel.message(byId: id) == nil {
            viewModel.setSelectedMessageId(id, force: false)
        }
    }

    private func highlightMessage(at indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? BaseMessageCell else { return }
        cell.applyHighlight()
    }

    func checkIfNearBottom() -> Bool {
        if contentFitsOnScreen() { return false }
        let contentHeight = collectionView.contentSize.height
        let scrollOffset = collectionView.contentOffset.y
        let visibleHeight = collectionView.frame.height
        return contentHeight - scrollOffset - visibleHeight < 100
    }

    func updateScrollDownBadge() {
        if newMessageCount > 0 {
            scrollDownBadge.isHidden = false
            scrollDownBadge.text = newMessageCount > 9 ? "9+" : "\(newMessageCount)"
        } else {
            scrollDownBadge.isHidden = true
        }
    }

    func updateScrollDownButtonVisibility() {
        if viewModel.isInHistoricalWindow {
            scrollDownButton.isHidden = false
            return
        }
        if contentFitsOnScreen() {
            scrollDownButton.isHidden = true
            return
        }
        scrollDownButton.isHidden = checkIfNearBottom()
    }

    func silentlyPrependDeferredMessages() {
        guard !viewModel.deferredPrependMessages.isEmpty else { return }

        let oldContentHeight = collectionView.contentSize.height
        let oldOffset = collectionView.contentOffset.y

        viewModel.isSilentPrepending = true

        viewModel.performSilentPrepend()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dataSource?.applyMessages(viewModel.groupedMessages, animated: false)
        collectionView.layoutIfNeeded()
        CATransaction.commit()

        let newContentHeight = collectionView.contentSize.height
        let addedHeight = newContentHeight - oldContentHeight
        collectionView.contentOffset.y = oldOffset + addedHeight

        viewModel.isSilentPrepending = false
        AppLogger.debug("[SilentPrepend] offset: \(oldOffset) → \(oldOffset + addedHeight) (added \(addedHeight)), oldH=\(oldContentHeight) newH=\(newContentHeight)")
    }

    // MARK: - In-place Update

    func canPerformInPlaceUpdate(groups: [MessageGroup]) -> Bool {
        guard let ds = dataSource else { return false }
        let snapshot = ds.diffableDataSource?.snapshot()
        let existingIds = Set((snapshot?.itemIdentifiers ?? []).map { $0.stableId })
        var newIds = Set<String>()
        for group in groups {
            for msg in group.messages {
                newIds.insert(msg.stableId)
            }
        }
        return existingIds == newIds
    }

    func performInPlaceUpdate(groups: [MessageGroup]) {
        guard let ds = dataSource else { return }
        let userId = viewModel.getCurrentUserId()
        let isGroup = viewModel.isGroupChat
        let translations = viewModel.showingTranslations
        let participants = viewModel.participantsForMessageDisplay()

        var changedMessages: [ConversationMessage] = []
        for group in groups {
            for msg in group.messages {
                guard let existing = ds.findItem(withId: msg.stableId) else { continue }
                let translationKey = msg.id.isEmpty ? msg.stableId : msg.id
                let freshModel = MessageCellModel.from(
                    msg, isGroupChat: isGroup, currentUserId: userId,
                    showingTranslation: translations.contains(translationKey),
                    groupParticipants: participants
                )
                let cachedModel = ds.modelCache[existing.stableId] ?? existing.model
                if cachedModel != freshModel
                    || cachedModel.measuredHeight != freshModel.measuredHeight
                    || cachedModel.isDeletedState != freshModel.isDeletedState {
                    changedMessages.append(msg)
                }
            }
        }

        if !changedMessages.isEmpty {
            let preContentHeight = collectionView.contentSize.height
            let preOffset = collectionView.contentOffset.y
            let wasNearBottom = checkIfNearBottom()

            ds.updateConfig(
                currentUserId: userId,
                isGroupChat: isGroup,
                showingTranslations: translations,
                groupParticipants: participants
            )
            ds.batchReconfigure(changedMessages)

            collectionView.layoutIfNeeded()
            updateContentInsets()
            updateVisibleAudioCells(playback: viewModel.audioPlayback)

            if wasNearBottom && !viewModel.isInHistoricalWindow {
                scrollToBottomImmediate()
            } else {
                let heightDelta = collectionView.contentSize.height - preContentHeight
                if heightDelta != 0 {
                    collectionView.contentOffset.y = preOffset + heightDelta
                }
            }
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension ChatDetailViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let model = dataSource?.model(at: indexPath) else {
            return CGSize(width: collectionView.frame.width, height: 72)
        }
        let height: CGFloat
        if model.needsTruncation && expandedMessageIds.contains(model.stableId) {
            height = model.fullHeight
        } else {
            height = model.measuredHeight
        }
        return CGSize(width: collectionView.frame.width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        CGSize(width: collectionView.frame.width, height: 44)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
    }
}

// MARK: - UICollectionViewDelegate

extension ChatDetailViewController: UICollectionViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if keyboardHeight > 0 || keyboardTrackingView.window != nil {
            startKeyboardTracking()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if keyboardTrackingDisplayLink != nil || keyboardTrackingView.window != nil {
            syncInputBarToKeyboard()
        }

        let nearBottom = checkIfNearBottom()

        // In a historical (pinned-jump) window keep the scroll-down button always
        // visible — it doubles as the "back to latest" affordance.
        updateScrollDownButtonVisibility()

        if nearBottom && newMessageCount > 0 {
            newMessageCount = 0
            unreadCount = 0          // ← add this
            hasScrolledToUnread = true
            updateScrollDownBadge()
        }

        guard initialSnapshotApplied,
              hasSetInitialInsets,
              viewModel.deferredPrependMessages.isEmpty else { return }

        if nearBottom, viewModel.isInHistoricalWindow,
           scrollView.isDragging || scrollView.isDecelerating {
            viewModel.returnToLatestMessages()
            return
        }

        if scrollView.contentOffset.y < 200,
           !viewModel.isLoadingHistory,
           !viewModel.isLoadingOlderMessages {
            viewModel.loadMoreMessages()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        view.endEditing(true)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ChatDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer.view == collectionView,
           !mentionTable.isHidden,
           mentionTable.frame.contains(touch.location(in: view)) {
            return false
        }
        return true
    }
}
