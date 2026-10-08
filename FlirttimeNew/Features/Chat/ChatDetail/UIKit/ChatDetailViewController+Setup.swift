import UIKit
import SwiftUI

// MARK: - Setup & Configuration

extension ChatDetailViewController {

    func setupCollectionView() {
        view.backgroundColor = ChatTheme.background
        let backgroundView = UIImageView(image: UIImage(named: ChatAssets.backgroundPattern))
        backgroundView.contentMode = .scaleAspectFill
        backgroundView.clipsToBounds = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(backgroundView, at: 0)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCollectionTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        collectionView.addGestureRecognizer(tap)
    }

    @objc func handleCollectionTap(_ gesture: UITapGestureRecognizer) {
        view.endEditing(true)
        if attachmentPanel != nil {
            dismissAttachmentPanel()
        }
    }

    func setupNavBar() {
        let resolvedGroupTitle = viewModel.groupTitle.isEmpty ? (isGroupChat ? groupTitle : "") : viewModel.groupTitle

        let bar = ChatDetailNavBar(
            isGroupChat: isGroupChat,
            groupTitle: resolvedGroupTitle,
            groupParticipants: viewModel.groupParticipants,
            user: user,
            headerUserData: viewModel.headerUserData,
            activeStatus: activeStatus,
            userStatus: viewModel.userStatus,
            isGroupParticipant: viewModel.isGroupParticipant,
            showCallButtons: true,
            isChannel: isChannel,
            isChannelAdmin: viewModel.isChannelAdmin,
            isChannelFollowed: viewModel.isChannelFollowed,
            hasResolvedChannelRole: viewModel.hasResolvedChannelRole,
            channelFollowersCount: viewModel.channelFollowersCount,
            otherUserId: selectedUserChatID.isEmpty ? nil : selectedUserChatID,
            groupAvatarUrl: viewModel.conversationAvatarURL ?? groupAvatarUrl,
            conversationId: selectedId,
            participantsCount: participantsCount
        )
        bar.onBack = { [weak self] in self?.onBack?() }
        bar.onProfileTap = { [weak self] in self?.onProfileTap?() }
        bar.onVoiceCall = { [weak self] in self?.startAgoraCall(type: .audio) }
        bar.onVideoCall = { [weak self] in self?.startAgoraCall(type: .video) }
        bar.onMore = { [weak self] in self?.presentConversationMenu() }
        bar.onShareChannel = { [weak self] in self?.shareChannel() }
        bar.onUnfollowChannel = { [weak self] in self?.confirmUnfollowChannel() }
        bar.onFollowChannel = { [weak self] in
            guard let self else { return }
            ChannelSocketService.shared.toggleFollow(
                channelId: self.channelId,
                currentlyFollowing: false
            ) { [weak self] newState in
                guard let self else { return }
                if newState {
                    self.viewModel.isChannelFollowed = true
                    self.channelFollowBanner.isHidden = true
                    self.updateContentInsets()
                }
            }
        }
        bar.onDeleteChannel = { [weak self] in self?.confirmDeleteChannel() }
        
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 66),
        ])
        navBar = bar
    }

    /// Same Agora flow as FollowersProfileViewController call buttons.
    /// Works for 1:1 and group chats (channels remain blocked).
    /// New Chat opens with an empty conversation id — create/resolve it first (like send message).
    func startAgoraCall(type: AgoraCallType) {
        guard !isChannel else { return }
        if isGroupChat, !viewModel.isGroupParticipant { return }
        guard !viewModel.shouldShowBlockView else { return }
        guard AgoraCallService.shared.phase == .idle else {
            viewModel.showToastMessage("Already in a call")
            return
        }

        viewModel.ensureConversationReady { [weak self] success in
            guard let self else { return }
            let run: () -> Void = {
                // Keep VC snapshot in sync with ViewModel (New Chat creates id asynchronously).
                if !self.viewModel.selectedId.isEmpty {
                    self.selectedId = self.viewModel.selectedId
                }
                let conversationId = self.viewModel.selectedId
                guard success, !conversationId.isEmpty else {
                    self.viewModel.showToastMessage("Unable to start call")
                    return
                }
                // Prefer rejoin when this group call is still live after we left.
                if self.isGroupChat, AgoraCallService.shared.canRejoinGroupCall(conversationId: conversationId) {
                    self.rejoinActiveGroupCall()
                    return
                }
                guard AgoraCallService.shared.phase == .idle else {
                    self.viewModel.showToastMessage("Already in a call")
                    return
                }

                let peerUser = self.viewModel.headerUserData ?? self.user
                let displayName: String? = {
                    if self.isGroupChat {
                        let title = self.viewModel.groupTitle.isEmpty ? self.groupTitle : self.viewModel.groupTitle
                        return title.isEmpty ? "Group Call" : title
                    }
                    let full = peerUser?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !full.isEmpty { return full }
                    let user = peerUser?.userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return user.isEmpty ? nil : user
                }()

                let avatarURL: String? = {
                    if self.isGroupChat {
                        let url = (self.viewModel.conversationAvatarURL ?? self.groupAvatarUrl)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return url.isEmpty ? nil : url
                    }
                    let path = peerUser?.profilePictureDetails?.filePath
                        ?? peerUser?.profilePicture
                        ?? ""
                    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }()

                let meId = ChatAuthStore.shared.currentUser?.userId ?? ""
                let groupMembers: [AgoraCallGridParticipant] = self.isGroupChat
                    ? self.viewModel.groupParticipants.map { p in
                        AgoraCallGridParticipant(
                            userId: p.userId,
                            displayName: {
                                let name = p.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !name.isEmpty { return name }
                                let user = p.userName.trimmingCharacters(in: .whitespacesAndNewlines)
                                return user.isEmpty ? "Member" : user
                            }(),
                            avatarURL: p.profilePicture,
                            isSelf: p.userId == meId,
                            isConnected: p.userId == meId
                        )
                    }
                    : []

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await AgoraCallService.shared.startOutgoing(
                            conversationId: conversationId,
                            type: type,
                            isGroup: self.isGroupChat,
                            displayName: displayName,
                            avatarURL: avatarURL,
                            groupMembers: groupMembers
                        )
                    } catch {
                        let message: String
                        if let callError = error as? AgoraCallError, case .busy = callError {
                            message = "User is busy"
                        } else if AgoraCallError.isBusyMessage(error.localizedDescription) {
                            message = "User is busy"
                        } else {
                            message = error.localizedDescription
                        }
                        self.viewModel.showToastMessage(message)
                    }
                }
            }
            if Thread.isMainThread {
                run()
            } else {
                DispatchQueue.main.async(execute: run)
            }
        }
    }

    func setupPinnedBanner() {
        pinnedBanner.isHidden = true
        view.addSubview(pinnedBanner)
        let top = pinnedBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 66)
        pinnedBannerTopConstraint = top
        NSLayoutConstraint.activate([
            top,
            pinnedBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pinnedBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        view.bringSubviewToFront(pinnedBanner)
        pinnedBanner.onTap = { [weak self] in
            guard let self, let pinned = self.viewModel.currentPinnedMessage else { return }
            self.viewModel.handlePinnedMessageBannerTap(pinned)
        }
    }

    func setupGroupCallRejoinBanner() {
        groupCallRejoinBanner.isHidden = true
        view.addSubview(groupCallRejoinBanner)
        NSLayoutConstraint.activate([
            groupCallRejoinBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 66),
            groupCallRejoinBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            groupCallRejoinBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        groupCallRejoinBanner.onRejoin = { [weak self] in
            self?.rejoinActiveGroupCall()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGroupCallRejoinDidChange),
            name: .agoraGroupCallRejoinDidChange,
            object: nil
        )
        refreshGroupCallRejoinBanner()
    }

    @objc func handleGroupCallRejoinDidChange() {
        refreshGroupCallRejoinBanner()
    }

    func refreshGroupCallRejoinBanner() {
        guard isGroupChat, !isChannel else {
            groupCallRejoinBanner.isHidden = true
            updatePinnedBannerTopForRejoin()
            updateContentInsets()
            return
        }
        // Prefer live ViewModel id (same as New Chat / member-added open paths).
        let conversationId = !viewModel.selectedId.isEmpty ? viewModel.selectedId : selectedId
        guard !conversationId.isEmpty else {
            groupCallRejoinBanner.isHidden = true
            updatePinnedBannerTopForRejoin()
            updateContentInsets()
            return
        }
        if selectedId.isEmpty {
            selectedId = conversationId
        }
        // Restore after kill + hide if server says the call already ended.
        // If store empty (new member mid-call), kicks off detail `activeCall` fetch.
        AgoraCallService.shared.refreshRejoinableState(for: conversationId)
        let canRejoin = AgoraCallService.shared.canRejoinGroupCall(conversationId: conversationId)
        if canRejoin, let info = AgoraCallService.shared.rejoinableInfo(for: conversationId) {
            groupCallRejoinBanner.configure(isVideo: info.type == .video)
            groupCallRejoinBanner.isHidden = false
            view.bringSubviewToFront(groupCallRejoinBanner)
            if !pinnedBanner.isHidden {
                view.bringSubviewToFront(pinnedBanner)
            }
        } else {
            groupCallRejoinBanner.isHidden = true
        }
        updatePinnedBannerTopForRejoin()
        updateContentInsets()
    }

    func updatePinnedBannerTopForRejoin() {
        pinnedBannerTopConstraint?.constant = groupCallRejoinBanner.isHidden ? 66 : 66 + 48
    }

    func rejoinActiveGroupCall() {
        guard isGroupChat else { return }
        let conversationId = !viewModel.selectedId.isEmpty ? viewModel.selectedId : selectedId
        guard AgoraCallService.shared.canRejoinGroupCall(conversationId: conversationId) else {
            refreshGroupCallRejoinBanner()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await AgoraCallService.shared.rejoinGroupCall(conversationId: conversationId)
                self.refreshGroupCallRejoinBanner()
            } catch {
                self.viewModel.showToastMessage(error.localizedDescription)
                self.refreshGroupCallRejoinBanner()
            }
        }
    }

    func setupChannelFollowBanner() {
        channelFollowBanner.isHidden = true
        view.addSubview(channelFollowBanner)
        NSLayoutConstraint.activate([
            channelFollowBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            channelFollowBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            channelFollowBanner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        channelFollowBanner.onFollow = { [weak self] in
            guard let self else { return }
            self.channelFollowBanner.setLoading(true)
            ChannelSocketService.shared.toggleFollow(
                channelId: self.channelId,
                currentlyFollowing: false
            ) { [weak self] newState in
                guard let self else { return }
                self.channelFollowBanner.setLoading(false)
                if newState {
                    self.viewModel.isChannelFollowed = true
                    self.channelFollowBanner.configure(isFollowing: true)
                    self.inputContainer.isHidden = false
                    self.updateContentInsets()
                }
            }
        }
        channelFollowBanner.onUnfollow = { [weak self] in
            guard let self else { return }
            ChannelSocketService.shared.toggleFollow(
                channelId: self.channelId,
                currentlyFollowing: true
            ) { [weak self] newState in
                guard let self else { return }
                if !newState {
                    self.viewModel.isChannelFollowed = false
                    self.onBack?()
                }
            }
        }
    }

    func setupScreenshotDetection() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenshotDetected),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )
    }

    @objc func screenshotDetected() {
        // Emit screenshot event so the other user gets a system message notification
        let conversationId = viewModel.selectedId
        if !conversationId.isEmpty {
            let payload: [String: Any] = [
                "conversationId": conversationId,
                "takenAt": Int(Date().timeIntervalSince1970 * 1000)
            ]
            ChatSocketManager.shared.emitMessage(
                SocketEvent.conversationScreenshot.rawValue,
                withData: [payload]
            )
        }


    }

    // MARK: - Channel Actions

    func shareChannel() {
        viewModel.hydrateChannelShareLinkFromCacheIfNeeded()
        guard let shareLink = viewModel.resolvedChannelShareLink(),
              URL(string: shareLink) != nil else {
            GlobalToast.shared.show(ChatStrings.somethingWentWrong.localizedString())
            return
        }
        let channelName = viewModel.groupTitle.isEmpty ? ChatStrings.chat_channelLabel.localizedString() : viewModel.groupTitle
        let text = String(format: ChatStrings.chat_shareChannelText.localizedString(), channelName, shareLink)
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let anchor = navBar?.sharePopoverAnchorView {
            vc.popoverPresentationController?.sourceView = anchor
            vc.popoverPresentationController?.sourceRect = anchor.bounds
        }
        present(vc, animated: true)
    }

    func confirmUnfollowChannel() {
        let channelName = viewModel.groupTitle.isEmpty ? ChatStrings.chat_channelLabel.localizedString() : viewModel.groupTitle
        let alert = UIAlertController(
            title: ChatStrings.chat_unfollowChannel.localizedString(),
            message: String(format: ChatStrings.chat_unfollowChannelConfirmation.localizedString(), channelName),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: ChatStrings.chat_unfollowChannel.localizedString(), style: .destructive) { [weak self] _ in
            self?.unfollowChannel()
        })
        alert.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel))
        present(alert, animated: true)
    }

    func confirmDeleteChannel() {
        let channelName = viewModel.groupTitle.isEmpty ? ChatStrings.chat_channelLabel.localizedString() : viewModel.groupTitle
        let alert = UIAlertController(
            title: ChatStrings.chat_deleteChannel.localizedString(),
            message: String(format: ChatStrings.chat_deleteChannelConfirmation.localizedString(), channelName),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: ChatStrings.delete.localizedString(), style: .destructive) { [weak self] _ in
            self?.deleteChannel()
        })
        alert.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel))
        present(alert, animated: true)
    }

    private func unfollowChannel() {
        ChannelSocketService.shared.toggleFollow(
            channelId: channelId,
            currentlyFollowing: true
        ) { [weak self] newState in
            guard let self else { return }
            if !newState {
                self.viewModel.isChannelFollowed = false
                self.onBack?()
            }
        }
    }

    @objc private func channelFollowBarButtonTapped() {
        channelFollowBarButton.isEnabled = false
        ChannelSocketService.shared.toggleFollow(
            channelId: channelId,
            currentlyFollowing: false
        ) { [weak self] newState in
            guard let self else { return }
            self.channelFollowBarButton.isEnabled = true
            if newState {
                self.viewModel.isChannelFollowed = true
                self.channelFollowBarButton.isHidden = true
                self.channelFollowBanner.isHidden = true
                self.channelContentLeading?.isActive = false
                self.channelContentCenterX?.isActive = true
                self.updateContentInsets()
            }
        }
    }

    private func deleteChannel() {
        ChannelSocketService.shared.deleteChannel(channelId: channelId) { [weak self] in
            self?.onBack?()
        }
    }

    func setupInputSystem() {
        view.addSubview(inputBottomFill)
        view.addSubview(inputContainer)

        // Pin to the screen bottom (not safe area / keyboard guide). The floating
        // tab bar inflates safe-area and keyboardLayoutGuide, which left a gap and
        // stopped the composer lifting with the keyboard.
        inputContainerBottom = inputContainer.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: inputBarBottomConstant()
        )
        inputContainerBottom?.isActive = true
        NSLayoutConstraint.activate([
            inputBottomFill.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBottomFill.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBottomFill.topAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            inputBottomFill.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        inputContainer.addSubview(inputStack)
        NSLayoutConstraint.activate([
            inputStack.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            inputStack.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            inputStack.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            inputStack.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),
        ])

        replyBanner.isHidden = true
        replyBanner.onCancel = { [weak self] in self?.viewModel.cancelReply() }

        editBanner.isHidden = true
        editBanner.onCancel = { [weak self] in
            self?.viewModel.cancelEdit()
            self?.inputBar.messageText = ""
        }

        audioComposer.isHidden = true
        audioComposer.clipsToBounds = true
        audioComposerHeight = audioComposer.heightAnchor.constraint(equalToConstant: 0)

        inputStack.addArrangedSubview(replyBanner)
        inputStack.addArrangedSubview(editBanner)
        inputStack.addArrangedSubview(audioComposer)
        inputStack.addArrangedSubview(inputBar)

        // Channel read-only bar (non-admin) — icon + label + follow button
        channelReadOnlyBar.addSubview(channelReadOnlyContent)
        channelReadOnlyBar.addSubview(channelFollowBarButton)
        channelContentCenterX = channelReadOnlyContent.centerXAnchor.constraint(equalTo: channelReadOnlyBar.centerXAnchor)
        channelContentLeading = channelReadOnlyContent.leadingAnchor.constraint(equalTo: channelReadOnlyBar.leadingAnchor, constant: 16)
        channelContentCenterX?.priority = .defaultHigh
        channelContentLeading?.priority = .defaultHigh
        channelContentCenterX?.isActive = true
        channelContentLeading?.isActive = false
        NSLayoutConstraint.activate([
            channelReadOnlyContent.centerYAnchor.constraint(equalTo: channelReadOnlyBar.centerYAnchor),
            channelFollowBarButton.trailingAnchor.constraint(equalTo: channelReadOnlyBar.trailingAnchor, constant: -12),
            channelFollowBarButton.centerYAnchor.constraint(equalTo: channelReadOnlyBar.centerYAnchor),
            channelReadOnlyBar.heightAnchor.constraint(equalToConstant: 44),
        ])
        channelFollowBarButton.addTarget(self, action: #selector(channelFollowBarButtonTapped), for: .touchUpInside)
        channelFollowBarButton.isHidden = true
        inputStack.addArrangedSubview(channelReadOnlyBar)

        audioComposerHeight?.isActive = true

        if isChannel {
            if canSendInChannel {
                inputContainer.isHidden = false
                inputBar.isHidden = false
                channelReadOnlyBar.isHidden = true
            } else {
                inputContainer.isHidden = true
                inputBar.isHidden = true
                channelReadOnlyBar.isHidden = false
            }
            updateContentInsets(animated: false)
        } else if viewModel.shouldShowBlockView {
            inputContainer.isHidden = true
            inputBar.isHidden = true
            channelReadOnlyBar.isHidden = true
            updateContentInsets(animated: false)
        } else if isGroupChat && !viewModel.isGroupParticipant {
            inputContainer.isHidden = false
            inputBar.isHidden = true
            channelReadOnlyBar.isHidden = true
            nonParticipantBar.isHidden = false
            updateContentInsets(animated: false)
        } else {
            inputContainer.isHidden = false
            inputBar.isHidden = false
            channelReadOnlyBar.isHidden = true
            nonParticipantBar.isHidden = true
            updateContentInsets(animated: false)
        }

        mentionTable.delegate = self
        mentionTable.isHidden = true
        view.addSubview(mentionTable)
        mentionTableHeight = mentionTable.heightAnchor.constraint(equalToConstant: 0)
        mentionTableHeight?.isActive = true
        NSLayoutConstraint.activate([
            mentionTable.bottomAnchor.constraint(equalTo: inputContainer.topAnchor),
            mentionTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mentionTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        view.addSubview(typingIndicator)
        NSLayoutConstraint.activate([
            typingIndicator.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 14),
            typingIndicator.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
        ])
        typingBottomConstraint = typingIndicator.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -12)
        typingBottomConstraint?.isActive = true

        blockOverlay.isHidden = !viewModel.shouldShowBlockView
        blockOverlay.onUnblock = { [weak self] in
            guard let self, let userId = self.user?.userId ?? self.user?.id else { return }
            self.viewModel.unblockUser(userID: userId)
        }
        blockOverlay.onDeleteChat = { [weak self] in
            guard let self else { return }
            self.presentDeleteChatConfirmation()
        }
        blockOverlay.configure(userName: user?.fullName ?? user?.userName)
        view.addSubview(blockOverlay)
        NSLayoutConstraint.activate([
            blockOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blockOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blockOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func setupNonParticipantBar() {
        nonParticipantBar.isHidden = true
        let icon = UIImageView(image: UIImage(systemName: "info.circle"))
        icon.tintColor = ChatTheme.primary
        icon.translatesAutoresizingMaskIntoConstraints = false
        nonParticipantBar.addSubview(icon)
        nonParticipantBar.addSubview(nonParticipantLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: nonParticipantBar.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: nonParticipantBar.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            nonParticipantLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            nonParticipantLabel.trailingAnchor.constraint(equalTo: nonParticipantBar.trailingAnchor, constant: -12),
            nonParticipantLabel.topAnchor.constraint(equalTo: nonParticipantBar.topAnchor, constant: 12),
            nonParticipantLabel.bottomAnchor.constraint(equalTo: nonParticipantBar.bottomAnchor, constant: -12),
        ])
    }

    func setupScrollDownButton() {
        view.addSubview(scrollDownButton)
        let bottomAnchor: NSLayoutYAxisAnchor = viewModel.shouldShowBlockView
            ? blockOverlay.topAnchor
            : inputContainer.topAnchor
        scrollDownButtonBottom = scrollDownButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        scrollDownButtonBottom?.isActive = true
        NSLayoutConstraint.activate([
            scrollDownButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scrollDownButton.widthAnchor.constraint(equalToConstant: 36),
            scrollDownButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        scrollDownButton.addTarget(self, action: #selector(didTapScrollToBottomButton), for: .touchUpInside)

        scrollDownButton.addSubview(scrollDownBadge)
        NSLayoutConstraint.activate([
            scrollDownBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            scrollDownBadge.heightAnchor.constraint(equalToConstant: 18),
            scrollDownBadge.topAnchor.constraint(equalTo: scrollDownButton.topAnchor, constant: -8),
            scrollDownBadge.trailingAnchor.constraint(equalTo: scrollDownButton.trailingAnchor, constant: 4),
        ])
    }

    func setupDataSource() {
        dataSource = ChatMessagesDataSource(
            collectionView: collectionView,
            currentUserId: viewModel.getCurrentUserId(),
            isGroupChat: viewModel.isGroupChat
        )
        dataSource?.actionsDelegate = self
        dataSource?.onSnapshotApplied = { [weak self] count in
            self?.updateEmptyProfileCard(itemCount: count)
        }
    }

    func setupKeyboardObservers() {
        keyboardTrackingView.onPositionChange = { [weak self] in
            self?.syncInputBarToKeyboard()
        }
        inputBar.textView.inputAccessoryView = keyboardTrackingView

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardDidHide(_:)),
            name: UIResponder.keyboardDidHideNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    func bindInputActions() {
        inputBar.delegate = self

        audioComposer.onCancelRecording = { [weak self] in self?.viewModel.cancelAudioRecordingAndDiscard() }
        audioComposer.onStopRecording = { [weak self] in self?.viewModel.stopAudioRecording() }
        audioComposer.onTogglePlayback = { [weak self] in
            guard let self else { return }
            self.viewModel.toggleRecordedAudioPlayback()
        }
        audioComposer.onDeleteRecording = { [weak self] in self?.viewModel.deleteRecordedAudio() }
        audioComposer.onSendRecording = { [weak self] in self?.viewModel.sendRecordedAudio() }
    }

    func setDraftText(_ text: String) {
        inputBar.messageText = text
    }

    func saveDraft() {
        let cid = isChannel ? channelId : selectedId
        guard !cid.isEmpty else { return }
        let text = inputBar.messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        ConversationDraftStore.shared.save(conversationId: cid, text: text)
    }

    func restoreDraft() {
        let cid = isChannel ? channelId : selectedId
        guard !cid.isEmpty else { return }
        if let draft = ConversationDraftStore.shared.load(conversationId: cid), !draft.isEmpty {
            inputBar.messageText = draft
        }
    }

    func isInputHidden() -> Bool {
        viewModel.audioRecording.isRecordingAudio || viewModel.audioRecording.hasRecordedAudio || viewModel.shouldShowBlockView
    }

    func setAudioComposerVisible(_ visible: Bool) {
        audioComposerHeight?.constant = visible ? ChatAudioComposerView.barHeight : 0
        audioComposer.isHidden = !visible
    }

    func bannerSenderName(for message: ConversationMessage) -> String {
        let senderId = (message.sender?.id ?? message.senderId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = viewModel.resolvedDisplayName(for: senderId)
        if !resolved.isEmpty { return resolved }

        if let fullName = GroupParticipantDisplay.cleanName(message.sender?.fullName) {
            return fullName
        }
        if let userName = GroupParticipantDisplay.cleanName(message.sender?.userName) {
            return userName
        }
        return ""
    }

    func updateVisibleAudioCells(playback: AudioPlaybackState) {
        for cell in collectionView.visibleCells {
            guard let audioCell = cell as? ChatAudioMessageCell,
                  let model = audioCell.cellModel else { continue }
            let messageId = model.message.id
            let stableId = model.stableId
            let isCurrentMessage = playback.isCurrentMessage(id: messageId, stableId: stableId)
            let isActive = isCurrentMessage && !playback.isPaused
            let progress = playback.progress(id: messageId, stableId: stableId)
            audioCell.updatePlayingState(isActive, isPaused: isCurrentMessage && playback.isPaused)
            if isCurrentMessage {
                audioCell.updatePlaybackProgress(
                    progress,
                    currentTime: playback.currentTime,
                    duration: playback.duration
                )
            } else {
                audioCell.updatePlaybackProgress(0)
                audioCell.resetDurationLabel()
            }
        }
    }

    func applyInitialMessagesIfAvailable() {
        let groups = viewModel.groupedMessages
        let newCount = groups.reduce(0) { $0 + $1.messages.count }
        guard newCount > 0 else { return }

        dataSource?.updateConfig(
            currentUserId: viewModel.getCurrentUserId(),
            isGroupChat: viewModel.isGroupChat,
            showingTranslations: viewModel.showingTranslations,
            groupParticipants: viewModel.participantsForMessageDisplay()
        )
        dataSource?.applyMessages(groups, animated: false)
        initialSnapshotApplied = true
        initialSnapshotAppliedAt = Date()
        collectionView.layoutIfNeeded()
        scrollToInitialPosition() //scrollToBottomImmediate()
    }

    // MARK: - Factory

    /// Creates a fully configured `ChatDetailViewController` ready to be pushed.
    static func make(
        selectedId: String,
        selectedUserChatID: String = "",
        user: UserRes?,
        activeStatus: String = "",
        isGroupChat: Bool = false,
        groupTitle: String = "",
        groupParticipants: [GroupParticipant] = [],
        isGroupParticipant: Bool = true,
        groupAvatarUrl: String = "",
        isChannel: Bool = false,
        channelId: String = "",
        canSendInChannel: Bool = false,
        isAlreadyFollowingChannel: Bool = false,
        initialFollowersCount: Int? = nil,
        initialIsBlocked: Bool = false,
        participantsCount: Int? = nil,
        storyData: OtherStoryResponseModel? = nil,
        selfUserStoryData: StoryResponseModel? = nil,
        unreadCount: Int? = 0,
        onBack: (() -> Void)? = nil
    ) -> ChatDetailViewController {
        let userListViewModel = ChatUserListViewModel()
        let vm = ChatDetailViewModel(
            userListViewModel: userListViewModel,
            initialChannelFollowersCount: initialFollowersCount,
            initialIsBlocked: initialIsBlocked
        )

        let vc = ChatDetailViewController(viewModel: vm)
        vc.selectedId = selectedId
        vc.selectedUserChatID = selectedUserChatID
        vc.user = user
        vc.activeStatus = activeStatus
        vc.isGroupChat = isGroupChat
        vc.groupTitle = groupTitle
        vc.isGroupParticipant = isGroupParticipant
        vc.groupAvatarUrl = groupAvatarUrl
        vc.isChannel = isChannel
        vc.channelId = channelId
        vc.canSendInChannel = canSendInChannel
        vc.isAlreadyFollowingChannel = isAlreadyFollowingChannel
        vc.participantsCount = participantsCount
        vc.unreadCount = unreadCount ?? 0

        vc.onBack = onBack ?? { [weak vc] in
            vc?.navigationController?.popViewController(animated: true)
        }

        vc.onProfileTap = { [weak vc] in
            guard let vc else { return }
            vc.view.endEditing(true)

            guard !vc.isChannel, !vc.isGroupChat else { return }
            Task { @MainActor [weak vc, weak vm] in
                guard let vc, let vm else { return }
                guard let seed = await vm.ensureOtherUserProfileForNavigation() else { return }
                ChatProfileRouter.openProfile(of: seed.user, from: vc)
            }
        }

        vm.setStoryData(storyData, selfStoryData: selfUserStoryData)
        vm.onConversationDeleted = { [weak vc] in
            vc?.navigationController?.popViewController(animated: true)
        }

        vm.prepareForDisplay(
            selectedId: selectedId,
            selectedUserChatID: selectedUserChatID,
            user: user,
            activeStatus: activeStatus,
            isGroupChat: isGroupChat,
            groupTitle: groupTitle,
            groupParticipants: groupParticipants,
            isGroupParticipant: isGroupParticipant,
            groupAvatarUrl: groupAvatarUrl,
            isChannel: isChannel,
            channelId: channelId,
            isAlreadyFollowingChannel: isAlreadyFollowingChannel,
            canSendInChannel: canSendInChannel
        ) {
            // New Chat resolves / creates conversationId on the ViewModel only — sync VC snapshot.
            if !vm.selectedId.isEmpty {
                vc.selectedId = vm.selectedId
            }
            // Don't overwrite a fresher API count with a stale inbox snapshot
            if let participantsCount, participantsCount > 0,
               (vm.participantsCount ?? 0) < participantsCount {
                vm.participantsCount = participantsCount
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                vm.refreshHeaderData()
            }
        }

        return vc
    }
}
