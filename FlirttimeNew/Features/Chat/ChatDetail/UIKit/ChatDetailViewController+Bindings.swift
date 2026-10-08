import UIKit
import Combine
import Kingfisher

// MARK: - ViewModel Bindings

extension ChatDetailViewController {

    func bindViewModel() {
        viewModel.$groupedMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] groups in
                guard let self else { return }
                guard !self.viewModel.isSilentPrepending else { return }
                let newCount = groups.reduce(0) { $0 + $1.messages.count }
//                guard newCount > 0 else { return }
                if newCount == 0 {
                           self.dataSource?.applyMessages([], animated: true)
                           return
                       }

                if self.viewModel.shouldScrollToBottomAfterWindowChange {
                    self.dataSource?.updateConfig(
                        currentUserId: self.viewModel.getCurrentUserId(),
                        isGroupChat: self.viewModel.isGroupChat,
                        showingTranslations: self.viewModel.showingTranslations,
                        groupParticipants: self.viewModel.participantsForMessageDisplay()
                    )
                    self.dataSource?.applyMessages(groups, animated: false)
                    self.collectionView.layoutIfNeeded()
                    return
                }

                // Capture previous data-source state BEFORE applying the new snapshot.
                let previousFirstMessageId   = self.dataSource?.firstMessageId
                let previousLatestCreatedAt  = self.dataSource?.latestMessageCreatedAt
                let newLatestCreatedAt        = groups.last?.messages.last?.createdAt

                // In-place update (status, reaction, poll changes) — no structural change, no scroll
                if self.initialSnapshotApplied,
                   self.canPerformInPlaceUpdate(groups: groups) {
                    self.performInPlaceUpdate(groups: groups)
                    return
                }

                let wasNearBottom = self.checkIfNearBottom()
                let previousCount = self.dataSource?.totalItemCount ?? 0

                let hasNewLatestMessage = newLatestCreatedAt != nil
                    && (newLatestCreatedAt ?? "") > (previousLatestCreatedAt ?? "")

                let isPrepend = self.initialSnapshotApplied
                    && previousFirstMessageId != nil
                    && groups.first?.messages.first?.id != previousFirstMessageId
                    && !hasNewLatestMessage

                let isSameCountReplacement = self.initialSnapshotApplied
                    && previousCount == newCount
                    && !isPrepend

                let preApplyContentHeight = self.collectionView.contentSize.height
                let preApplyOffset        = self.collectionView.contentOffset.y

                self.dataSource?.updateConfig(
                    currentUserId: self.viewModel.getCurrentUserId(),
                    isGroupChat: self.viewModel.isGroupChat,
                    showingTranslations: self.viewModel.showingTranslations,
                    groupParticipants: self.viewModel.participantsForMessageDisplay()
                )

                if !self.initialSnapshotApplied {
                    self.dataSource?.applyMessages(groups, animated: false)
                    self.initialSnapshotApplied = true
                    self.initialSnapshotAppliedAt = Date()
                    self.collectionView.layoutIfNeeded()
//                    self.scrollToBottomImmediate()
                    self.scrollToInitialPosition()
                    if self.collectionView.frame.height > 0 {
                        self.scheduleInitialReveal()
                    }
                } else if isSameCountReplacement {
                    self.dataSource?.applyMessages(groups, animated: false)
                    self.collectionView.layoutIfNeeded()
                    let heightDelta = self.collectionView.contentSize.height - preApplyContentHeight
                    self.collectionView.contentOffset.y = preApplyOffset + heightDelta
                } else if isPrepend {
                    self.dataSource?.applyMessages(groups, animated: false)
                    self.collectionView.layoutIfNeeded()
                    let addedHeight = self.collectionView.contentSize.height - preApplyContentHeight
                    if addedHeight > 0 {
                        self.collectionView.contentOffset.y = preApplyOffset + addedHeight
                    }
                } else if hasNewLatestMessage && !self.viewModel.isInHistoricalWindow {
                    self.dataSource?.applyMessages(groups, animated: true)
                    self.collectionView.layoutIfNeeded()
                    let shouldAnimate = !self.isInInitialScrollSettlingWindow()
                    if self.contentFitsOnScreen() {
                        self.scrollToTopImmediate()
                    } else if wasNearBottom {
                        self.scrollToBottom(animated: shouldAnimate, userInitiated: false)
                    }
                    self.updateScrollDownButtonVisibility()
                } else {
                    // Deletions, count changes away from bottom, etc.
                    let isStructuralChange = previousCount != newCount
                    self.dataSource?.applyMessages(groups, animated: isStructuralChange)
                    if hasNewLatestMessage && !wasNearBottom && !self.viewModel.isInHistoricalWindow {
                        guard !self.contentFitsOnScreen() else {
                            self.updateScrollDownButtonVisibility()
                            return
                        }
                        let myId = self.viewModel.getCurrentUserId()
                        let genuinelyNew = groups.flatMap { $0.messages }
                            .filter { ($0.createdAt) > (previousLatestCreatedAt ?? "") }
                            .filter { $0.senderId != myId }
                            .count
                        guard genuinelyNew > 0 else { return }
                        self.newMessageCount += genuinelyNew
                        self.updateScrollDownBadge()
                        self.updateScrollDownButtonVisibility()
                    }
                }
            }
            .store(in: &cancellables)

        viewModel.$pendingScrollToMessageId
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messageId in
                guard let self else { return }
                self.viewModel.pendingScrollToMessageId = nil
                let latestId = self.viewModel.messages.last?.id
                if latestId == messageId {
                    if self.contentFitsOnScreen() {
                        self.scrollToTopImmediate()
                    } else {
                        guard self.checkIfNearBottom() else { return }
                        if self.initialSnapshotApplied {
                            let shouldAnimate = !self.isInInitialScrollSettlingWindow()
                            self.scrollToBottom(animated: shouldAnimate, userInitiated: false)
                        }
                    }
                    self.updateScrollDownButtonVisibility()
                } else {
                    self.scrollToMessage(id: messageId)
                }
            }
            .store(in: &cancellables)

        viewModel.$forceScrollToMessageId
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messageId in
                guard let self else { return }
                self.viewModel.forceScrollToMessageId = nil
                self.scrollToMessage(id: messageId, retryCount: 0)
            }
            .store(in: &cancellables)

        viewModel.$shouldAutoScroll
            .dropFirst()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.initialSnapshotApplied else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.contentFitsOnScreen() {
                        self.scrollToTopImmediate()
                    } else {
                        self.scrollToBottom(animated: true, userInitiated: false)
                    }
                    self.updateScrollDownButtonVisibility()
                }
            }
            .store(in: &cancellables)

        viewModel.$shouldScrollToBottomAfterWindowChange
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.viewModel.shouldScrollToBottomAfterWindowChange = false
                self.newMessageCount = 0
                self.updateScrollDownBadge()
                self.collectionView.layoutIfNeeded()
                self.scrollToBottomImmediate()
            }
            .store(in: &cancellables)

        viewModel.$showingTranslations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showing in
                guard let self, self.initialSnapshotApplied else { return }
                self.dataSource?.updateConfig(
                    currentUserId: self.viewModel.getCurrentUserId(),
                    isGroupChat: self.viewModel.isGroupChat,
                    showingTranslations: showing,
                    groupParticipants: self.viewModel.participantsForMessageDisplay()
                )

                let allMessages = self.viewModel.groupedMessages.flatMap { $0.messages }
                self.dataSource?.batchReconfigure(allMessages, animated: true)
            }
            .store(in: &cancellables)

        // Reply banner
        viewModel.$replyingToMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self else { return }
                if let message {
                    let name = self.bannerSenderName(for: message)
                    let preview = message.displayPreviewText()
                    let msgType = (message.messageType ?? message.type ?? "").lowercased()
                    let isMedia = msgType == "image" || msgType == "video"
                    let thumbnail: UIImage? = isMedia ? (
                        InMemoryMediaCache.shared.getCachedImage(for: message.id) ??
                        {
                            let urlStr = message.thumbnail ?? message.media?.first?.thumbnail ?? message.media?.first?.url
                            guard let str = urlStr, let url = URL(string: str) else { return nil as UIImage? }
                            return ImageCache.default.retrieveImageInMemoryCache(forKey: url.absoluteString)
                        }()
                    ) : nil
                    self.replyBanner.configure(senderName: name, previewText: preview, thumbnail: thumbnail, isVideo: msgType == "video")
                    self.replyBanner.isHidden = false
                } else {
                    self.replyBanner.isHidden = true
                }
                self.updateContentInsets(animated: true)
            }
            .store(in: &cancellables)

        // Edit banner
        viewModel.$editingMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self else { return }
                if let message {
                    self.editBanner.configure(previewText: message.content ?? ChatStrings.chat_message.localizedString())
                    self.editBanner.isHidden = false
                    self.inputBar.isEditing = true
                    self.inputBar.messageText = message.content ?? ""
                    // Avoid focusing while a modal sheet is still up — keyboardWillShow would
                    // skip lifting the input bar and leave it buried under the keyboard.
                    if self.presentedViewController == nil {
                        self.inputBar.becomeFirstResponderInput()
                    } else {
                        self.dismiss(animated: true) {
                            self.inputBar.becomeFirstResponderInput()
                            self.updateContentInsets(animated: true)
                        }
                        return
                    }
                } else {
                    self.editBanner.isHidden = true
                    self.inputBar.isEditing = false
                }
                self.updateContentInsets(animated: true)
            }
            .store(in: &cancellables)

        // Audio recording state
        var previousAudioRecordingFlags: (isRecording: Bool, hasRecorded: Bool)?
        viewModel.$audioRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let flags = (state.isRecordingAudio, state.hasRecordedAudio)
                let flagsChanged = previousAudioRecordingFlags.map { $0 != flags } ?? true
                previousAudioRecordingFlags = flags

                if state.isRecordingAudio {
                    self.inputBar.isHidden = true
                    if flagsChanged {
                        self.setAudioComposerVisible(true)
                    }
                    self.audioComposer.setRecording(true, amplitudes: state.liveWaveAmplitudes, duration: state.recordingDuration)
                } else if state.hasRecordedAudio {
                    self.inputBar.isHidden = true
                    if flagsChanged {
                        self.setAudioComposerVisible(true)
                    }
                    self.audioComposer.setPreview(
                        seed: state.recordedWaveSeed,
                        progress: state.recordedAudioProgress,
                        duration: self.viewModel.recordedAudioDurationDisplay,
                        isPlaying: state.isPlayingRecordedAudio,
                        isPaused: state.isRecordedAudioPaused,
                        totalDurationSeconds: state.recordingDuration,
                        isUploading: self.viewModel.isAudioUploading
                    )
                } else {
                    if flagsChanged {
                        self.setAudioComposerVisible(false)
                        self.audioComposer.setHidden()
                        self.inputBar.isHidden = self.isInputHidden()
                    }
                }
                // Only recompute insets when composer visibility / mode changes —
                // not on every live amplitude tick.
                if flagsChanged {
                    self.updateContentInsets(animated: true)
                }
            }
            .store(in: &cancellables)

        // Typing indicator
        viewModel.$typingIndicator
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.isTypingActive = state.isTyping
                if state.isTyping {
                    self.typingIndicator.show(senderName: state.senderName)
                } else {
                    self.typingIndicator.hide()
                }
                self.updateContentInsets(animated: true, duration: 0.25, onlyIfNearBottom: true)
            }
            .store(in: &cancellables)

        // Mention autocomplete
        viewModel.mentionManager.$filteredParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                guard let self else { return }
                let hasActiveQuery = self.viewModel.mentionManager.mentionQuery != nil
                let shouldShow = hasActiveQuery && !participants.isEmpty
                self.mentionTable.isHidden = !shouldShow
                if shouldShow {
                    self.mentionTable.updateParticipants(participants)
                    self.view.bringSubviewToFront(self.mentionTable)
                }
                self.mentionTableHeight?.constant = shouldShow ? self.mentionTable.heightForParticipants() : 0
                self.view.layoutIfNeeded()
            }
            .store(in: &cancellables)

        viewModel.$groupParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                guard let self else { return }
                self.viewModel.mentionManager.allParticipants = participants
                self.viewModel.mentionManager.isGroupChat = self.viewModel.isGroupChat
                self.navBar?.updateMemberCount(participants, participantsCount: self.viewModel.participantsCount)
                // Re-resolve sender names/avatars once members load (NEW API has no nested sender)
                guard self.viewModel.isGroupChat, self.initialSnapshotApplied else { return }
                self.dataSource?.updateConfig(
                    currentUserId: self.viewModel.getCurrentUserId(),
                    isGroupChat: true,
                    showingTranslations: self.viewModel.showingTranslations,
                    groupParticipants: participants
                )
                let allMessages = self.viewModel.groupedMessages.flatMap { $0.messages }
                self.dataSource?.batchReconfigure(allMessages, animated: false)
            }
            .store(in: &cancellables)

        viewModel.$participantsCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self, self.viewModel.isGroupChat else { return }
                self.navBar?.updateMemberCount(
                    self.viewModel.groupParticipants,
                    participantsCount: count
                )
            }
            .store(in: &cancellables)

        viewModel.$groupTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                guard let self, self.viewModel.isGroupChat else { return }
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.navBar?.updateTitle(trimmed)
            }
            .store(in: &cancellables)

        // Block view
        viewModel.$shouldShowBlockView
            .dropFirst() // Initial state already applied in setupInputSystem()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                self.blockOverlay.isHidden = !show
                self.inputContainer.isHidden = show
                if !show {
                    self.inputBar.isHidden = self.isInputHidden()
                }
                // Re-anchor scroll-down button above the active bottom bar
                self.scrollDownButtonBottom?.isActive = false
                let anchor: NSLayoutYAxisAnchor = show
                    ? self.blockOverlay.topAnchor
                    : self.inputContainer.topAnchor
                self.scrollDownButtonBottom = self.scrollDownButton.bottomAnchor.constraint(equalTo: anchor, constant: -12)
                self.scrollDownButtonBottom?.isActive = true
                self.updateContentInsets(animated: true)
            }
            .store(in: &cancellables)

        // Audio playback state
        viewModel.$audioPlayback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateVisibleAudioCells(playback: state)
            }
            .store(in: &cancellables)

        // Group participant status
        viewModel.$isGroupParticipant
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isParticipant in
                guard let self, self.isGroupChat else { return }
                if isParticipant {
                    self.nonParticipantBar.isHidden = true
                    self.inputContainer.isHidden = self.viewModel.shouldShowBlockView
                    self.inputBar.isHidden = self.isInputHidden()
                } else {
                    self.nonParticipantBar.isHidden = false
                    self.inputContainer.isHidden = false
                    self.inputBar.isHidden = true
                }
                self.updateContentInsets(animated: true)
            }
            .store(in: &cancellables)

        // Nav bar dynamic updates
        viewModel.$headerUserData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] userData in
                guard let self, let navBar = self.navBar else { return }
                navBar.updateHeader(userData: userData)
                // Direct chats: refresh reply/sender names once peer profile arrives
                guard !self.viewModel.isGroupChat,
                      !self.viewModel.isChannel,
                      self.initialSnapshotApplied else { return }
                self.dataSource?.updateConfig(
                    currentUserId: self.viewModel.getCurrentUserId(),
                    isGroupChat: false,
                    showingTranslations: self.viewModel.showingTranslations,
                    groupParticipants: self.viewModel.participantsForMessageDisplay()
                )
                let allMessages = self.viewModel.groupedMessages.flatMap { $0.messages }
                self.dataSource?.batchReconfigure(allMessages, animated: false)
            }
            .store(in: &cancellables)

        viewModel.$groupTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                guard let self, let navBar = self.navBar, !title.isEmpty else { return }
                navBar.updateTitle(title)
            }
            .store(in: &cancellables)

        viewModel.$conversationAvatarURL
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] urlString in
                guard let self, let navBar = self.navBar else { return }
                navBar.updateAvatar(urlString: urlString)
            }
            .store(in: &cancellables)

        viewModel.$userStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, let navBar = self.navBar else { return }
                navBar.updateStatus(status)
            }
            .store(in: &cancellables)

        // Pinned message banner
        viewModel.$currentPinnedMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pinned in
                guard let self else { return }
                if let pinned {
                    let text: String
                    let msgType = (pinned.messageType ?? pinned.type ?? "").lowercased()
                    let typeName = ConversationMessage.messageTypeDisplayName(msgType)
                    if typeName.isEmpty {
                        text = pinned.content ?? ChatStrings.chat_pinnedMessage.localizedString()
                    } else if typeName == ChatStrings.chat_message.localizedString() {
                        text = pinned.content ?? ChatStrings.chat_pinnedMessage.localizedString()
                    } else {
                        text = typeName
                    }
                    self.pinnedBanner.configure(
                        text: String(text.prefix(60)),
                        isLoading: self.viewModel.isJumpingToPinnedMessage
                    )
                    self.pinnedBanner.isHidden = false
                    if !self.groupCallRejoinBanner.isHidden {
                        self.view.bringSubviewToFront(self.groupCallRejoinBanner)
                    }
                    self.view.bringSubviewToFront(self.pinnedBanner)
                    if let navBar = self.navBar {
                        self.view.bringSubviewToFront(navBar)
                    }
                } else {
                    self.pinnedBanner.isHidden = true
                }
                self.updatePinnedBannerTopForRejoin()
                self.updateContentInsets(animated: true)
            }
            .store(in: &cancellables)

        viewModel.$isJumpingToPinnedMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isJumping in
                guard let self, !self.pinnedBanner.isHidden else { return }
                let bannerText: String
                if let pinned = self.viewModel.currentPinnedMessage {
                    let msgType = (pinned.messageType ?? pinned.type ?? "").lowercased()
                    let typeName = ConversationMessage.messageTypeDisplayName(msgType)
                    if typeName.isEmpty {
                        bannerText = pinned.content ?? ChatStrings.chat_pinnedMessage.localizedString()
                    } else if typeName == ChatStrings.chat_message.localizedString() {
                        bannerText = pinned.content ?? ChatStrings.chat_pinnedMessage.localizedString()
                    } else {
                        bannerText = typeName
                    }
                } else {
                    bannerText = ""
                }
                self.pinnedBanner.configure(
                    text: bannerText,
                    isLoading: isJumping
                )
            }
            .store(in: &cancellables)

        // Channel follow state
        viewModel.$isChannelFollowed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFollowed in
                guard let self, self.isChannel else { return }
                let isAdmin = self.viewModel.isChannelAdmin
                let hasResolved = self.viewModel.hasResolvedChannelRole
                if hasResolved && !isAdmin {
                    if !isFollowed {
                        self.channelFollowBanner.configure(isFollowing: false)
                        self.channelFollowBanner.isHidden = false
                        self.channelFollowBarButton.isHidden = false
                        self.channelContentCenterX?.isActive = false
                        self.channelContentLeading?.isActive = true
                    } else {
                        self.channelFollowBanner.isHidden = true
                        self.channelFollowBarButton.isHidden = true
                        self.channelContentLeading?.isActive = false
                        self.channelContentCenterX?.isActive = true
                    }
                    self.inputBar.isHidden = true
                    self.channelReadOnlyBar.isHidden = false
                    updateContentInsets(animated: false)
                    self.inputContainer.isHidden = false
                } else if hasResolved && isAdmin {
                    self.channelFollowBanner.isHidden = true
                    self.channelFollowBarButton.isHidden = true
                    self.channelContentLeading?.isActive = false
                    self.channelContentCenterX?.isActive = true
                    self.channelReadOnlyBar.isHidden = true
                    updateContentInsets(animated: false)
                    self.inputBar.isHidden = self.isInputHidden()
                    self.inputContainer.isHidden = false
                }
                self.updateContentInsets()
            }
            .store(in: &cancellables)

        viewModel.$hasResolvedChannelRole
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasResolved in
                guard let self, self.isChannel, hasResolved else { return }
                let isAdmin = self.viewModel.isChannelAdmin
                if !isAdmin {
                    let isFollowed = self.viewModel.isChannelFollowed
                    if !isFollowed {
                        self.channelFollowBanner.configure(isFollowing: false)
                        self.channelFollowBanner.isHidden = false
                        self.channelFollowBarButton.isHidden = false
                        self.channelContentCenterX?.isActive = false
                        self.channelContentLeading?.isActive = true
                    }
                    self.inputBar.isHidden = true
                    self.channelReadOnlyBar.isHidden = false
                    self.inputContainer.isHidden = false
                    updateContentInsets(animated: false)
                } else {
                    self.channelReadOnlyBar.isHidden = true
                    updateContentInsets(animated: false)
                    self.channelFollowBarButton.isHidden = true
                    self.inputBar.isHidden = self.isInputHidden()
                    self.inputContainer.isHidden = false
                }
                self.updateContentInsets()
            }
            .store(in: &cancellables)

        // Keep NavBar's follow state in sync so context menu reflects current state
        viewModel.$isChannelFollowed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFollowed in
                self?.navBar?.updateChannelFollowState(isFollowed: isFollowed)
            }
            .store(in: &cancellables)

        // Multi-select mode
        viewModel.$selection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateSelectionUI(state)
            }
            .store(in: &cancellables)

        // Media upload progress — reconfigure affected cells
        viewModel.$mediaUploadTempIds
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uploadingIds in
                guard let self else { return }
                let snapshot = self.dataSource?.diffableDataSource?.snapshot()
                guard let snapshot else { return }
                var itemsToReconfigure: [ChatMessageCellItem] = []
                for item in snapshot.itemIdentifiers {
                    guard var model = self.dataSource?.modelCache[item.stableId] else { continue }
                    // Spinner while still sending, or while the uploader is active for this bubble
                    let isOutgoingVisualMedia = !model.isIncoming
                        && (model.kind == .image || model.kind == .video)
                    let shouldShowUpload = isOutgoingVisualMedia
                        && (model.deliveryStatus == .sending
                            || uploadingIds.contains(item.stableId))
                    guard model.isUploading != shouldShowUpload else { continue }
                    model.isUploading = shouldShowUpload
                    self.dataSource?.modelCache[item.stableId] = model
                    itemsToReconfigure.append(item)
                }

                for item in itemsToReconfigure {
                    guard let indexPath = self.dataSource?.diffableDataSource?.indexPath(for: item) else { continue }
                    if let cell = self.collectionView.cellForItem(at: indexPath) as? BaseMessageCell {
                        let model = self.dataSource?.modelCache[item.stableId] ?? item.model
                        let inSelection = self.dataSource?.isInSelectionMode ?? false
                        cell.configure(with: model, isInSelectionMode: inSelection)
                    }
                }
            }
            .store(in: &cancellables)

        bindMediaDownloadNotification()
    }

    private func bindMediaDownloadNotification() {
        NotificationCenter.default.publisher(for: .mediaDownloadCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      self.initialSnapshotApplied,
                      let dataSource = self.dataSource,
                      let messageId = notification.userInfo?["messageId"] as? String else { return }

                guard let item = dataSource.findItem(withId: messageId) else { return }
                guard let indexPath = dataSource.diffableDataSource?.indexPath(for: item) else { return }

                if let cell = self.collectionView.cellForItem(at: indexPath) as? BaseMessageCell {
                    let model = dataSource.modelCache[item.stableId] ?? item.model
                    cell.configure(with: model, isInSelectionMode: dataSource.isInSelectionMode)
                }
            }
            .store(in: &cancellables)
    }
}
