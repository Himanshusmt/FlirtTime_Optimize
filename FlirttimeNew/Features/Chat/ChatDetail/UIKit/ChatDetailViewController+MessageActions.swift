import UIKit
import SwiftUI
import Kingfisher

// MARK: - MessageCellActionsDelegate

extension ChatDetailViewController: MessageCellActionsDelegate {

    private static let appRootDomains: [String] = ["onevibe.ai"]

    func cellDidTapMessage(_ cell: BaseMessageCell, model: MessageCellModel) {
        view.endEditing(true)
        if viewModel.selection.isSelectionMode {
            viewModel.toggleMessageSelection(model.stableId)
            return
        }
        // Tap-to-retry for failed outgoing messages
        if model.deliveryStatus == .failed, !model.isIncoming {
            viewModel.retryFailedMessage(tempId: model.message.id)
            return
        }
        // Tap pinned bubble → same options sheet with Unpin
        if isMessagePinned(model) {
            if isChannel {
                guard viewModel.isChannelAdmin else { return }
                presentChannelAdminMessageOptions(for: model)
                return
            }
            presentMessageOptions(for: model, sourceView: cell)
        }
    }

    func cellDidToggleSelection(_ cell: BaseMessageCell, messageId: String) {
        viewModel.toggleMessageSelection(messageId)
    }

    func cellDidLongPress(_ cell: BaseMessageCell, model: MessageCellModel) {
        if viewModel.selection.isSelectionMode { return }

        if isChannel {
            guard viewModel.isChannelAdmin else { return }
            presentChannelAdminMessageOptions(for: model)
            return
        }

        presentMessageOptions(for: model, sourceView: cell)
    }

    func cellDidSwipeToReply(_ cell: BaseMessageCell, model: MessageCellModel) {
        if isChannel && !viewModel.isChannelAdmin { return }
        let isPendingOrFailed = !model.isIncoming
            && (model.deliveryStatus == .sending || model.deliveryStatus == .failed)
        guard !isPendingOrFailed else { return }

        let didStart = viewModel.startReply(to: model.message)
        if didStart {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        inputBar.becomeFirstResponderInput()
    }

    func cellDidTapReaction(_ cell: BaseMessageCell, model: MessageCellModel, reaction: MessageReaction) {
        let reactions = model.reactions.filter { !$0.users.isEmpty }
        guard !reactions.isEmpty else { return }
        presentReactionUsersList(reactions: reactions, messageId: model.message.id)
    }

    func cellDidTapReplyPreview(_ cell: BaseMessageCell, messageId: String) {
        viewModel.setSelectedMessageId(messageId, force: true)
    }

    func cellDidTapMedia(_ cell: BaseMessageCell, model: MessageCellModel, mediaIndex: Int) {
        guard !viewModel.shouldShowBlockView else { return }
        switch model.kind {
        case .audio:
            viewModel.toggleMessageAudio(for: model.message)
        case .image, .video:
            presentMediaViewer(for: model, sourceCell: cell, mediaIndex: mediaIndex)
        case .post, .vibe:
            let postId = model.message.sharedContentId ?? ""
            guard !postId.isEmpty else { return }
            openSharedContent(id: postId, type: model.message.sharedContentType, from: model.message)
        case .reel:
            let reelId = model.message.sharedContentId ?? ""
            guard !reelId.isEmpty else { return }
            openSharedContent(id: reelId, type: "reel", from: model.message)
        case .story:
            let storyId = model.message.sharedContentId ?? ""
            _ = storyId
        default:
            break
        }
    }

    func cellDidTapPollOption(_ cell: BaseMessageCell, model: MessageCellModel, optionIndex: Int) {
        guard let poll = model.pollData, optionIndex < poll.options.count else { return }
        guard !model.message.id.isEmpty else { return }
        guard !poll.isClosed else { return }
        let option = poll.options[optionIndex]
        let userId = viewModel.getCurrentUserId()
        let messageId = model.message.id

        let currentSelectedOptionId = viewModel.getSelectedPollOptionId(for: messageId)
        let myIds = poll.resolvedMyOptionIds(currentUserId: userId)
        let isInModelVotes = myIds.contains(option.optionId)
            || (option.votes?.contains(where: {
                $0.userId.caseInsensitiveCompare(userId) == .orderedSame
            }) ?? false)
        let isCurrentlySelected = currentSelectedOptionId == option.optionId || isInModelVotes

        if isInModelVotes && currentSelectedOptionId != option.optionId {
            viewModel.setSelectedPollOptionId(for: messageId, optionId: option.optionId)
        }

        if isCurrentlySelected,
           (viewModel.pendingPollVoteWorkItem[messageId] != nil || viewModel.inFlightPollVotes[messageId, default: 0] > 0) {
            return
        }

        viewModel.voteOnPoll(
            messageId: model.message.id,
            conversationId: selectedId,
            optionId: option.id
        )
    }

    func cellDidChangeAudioSpeed(_ cell: BaseMessageCell, speed: Float) {
        if let service = viewModel.audioService as? ChatAudioService {
            service.setPlaybackRate(speed)
        }
    }

    func cellDidTapLink(_ cell: BaseMessageCell, url: URL) {
        if url.scheme == "tel" {
            UIApplication.shared.open(url)
            return
        }

        if let userName = ChatConfig.profileShareUsername(from: url) {
            openProfileFromDeepLink(userName: userName)
            return
        }

        let host = url.host?.lowercased()
        let matchesKnownRoot = host.map { h in
            Self.appRootDomains.contains { root in
                h == root || h.hasSuffix(".\(root)")
            }
        } ?? false
        let isAppDomain = matchesKnownRoot || ChatConfig.isAppShareLinkHost(host)

        guard isAppDomain else {
            UIApplication.shared.open(url)
            return
        }

        let parts = url.pathComponents.filter { $0 != "/" }

        if let inviteSlug = ChannelShareLinkBuilder.inviteSlug(from: url) {
            openChannelFromDeepLinkBySlug(inviteSlug)
            return
        }

        // Channel deep link: .../chat/channel/{channelId}
        if let channelId = ChannelShareLinkBuilder.channelId(from: url) {
            openChannelFromDeepLink(channelId: channelId)
            return
        }

        // Legacy path parsing fallback
        if let channelIndex = parts.firstIndex(of: "channel"),
           channelIndex + 1 < parts.count,
           parts[channelIndex] != "channels" {
            let channelId = parts[channelIndex + 1]
            if !channelId.isEmpty {
                openChannelFromDeepLink(channelId: channelId)
                return
            }
        }
        
        if let postIndex = parts.firstIndex(of: "post"),
           parts.count > postIndex + 3 {
            
            let postId = parts[postIndex + 1]
            let userName = parts.last
            
            print("POST ID:", postId)
            print("USERNAME:", userName ?? "")
            print("GOING FROM CHAT ::")
            guard let name = userName else { return }
            openProfileFromDeepLink(userName: name, isFromSharedLink: true, postId: postId)
            return
        }
    
        // Profile deep link: .../auth/share/{userName} or .../{userName}
        let userName: String?
        if let shareIndex = parts.firstIndex(of: "share"),
           shareIndex + 1 < parts.count {
            userName = parts[shareIndex + 1]
        } else {
            userName = parts.last
        }
        if let userName, !userName.isEmpty {
            openProfileFromDeepLink(userName: userName)
            return
        }

        UIApplication.shared.open(url)
    }
    
    func cellDidTapMention(_ cell: BaseMessageCell, username: String) {
        guard let participant = viewModel.groupParticipants.first(where: {
            $0.userName.lowercased() == username.lowercased()
        }) else { return }
        print("----->>>>>",username)
        openProfileFromDeepLink(userName: username)
    }

    func cellDidTapAvatar(_ cell: BaseMessageCell, model: MessageCellModel) {
        guard model.isGroupChat else { return }
        let senderId = model.message.senderId ?? model.message.sender?.id ?? ""
        if let participant = viewModel.groupParticipants.first(where: {
            $0.userId == senderId || $0.id == senderId
        }), !participant.userName.isEmpty,
           !GroupParticipantDisplay.looksLikeUserId(participant.userName) {
            openProfileFromDeepLink(userName: participant.userName)
            return
        }
        if let userName = GroupParticipantDisplay.cleanName(model.senderName)
            ?? GroupParticipantDisplay.cleanName(model.message.sender?.userName) {
            // Prefer username when senderName is a display name — try participant match by fullName
            if let p = viewModel.groupParticipants.first(where: {
                $0.fullName == model.senderName || $0.userName == model.senderName
            }), !p.userName.isEmpty, !GroupParticipantDisplay.looksLikeUserId(p.userName) {
                openProfileFromDeepLink(userName: p.userName)
            } else if !GroupParticipantDisplay.looksLikeUserId(userName) {
                openProfileFromDeepLink(userName: userName)
            }
        }
    }

    // MARK: - Shared Post / Vibe / Reel

    private func openSharedContent(id: String, type: String, from message: ConversationMessage) {
        guard !isOpeningSharedContent else { return }

        let kind: ChatDetailViewModel.SharedEntityKind
        switch type {
        case "vibe": kind = .vibe
        case "reel": kind = .reel
        default: kind = .post
        }

        let currentUserId = viewModel.getCurrentUserId()
        let authorId = message.sharedAuthorUserId
        let isOwnContent = authorId.map {
            !$0.isEmpty && $0.caseInsensitiveCompare(currentUserId) == .orderedSame
        } ?? false

        if isOwnContent {
            navigateToSharedContent(id: id, kind: kind)
            return
        }

        isOpeningSharedContent = true
        ChatHUD.show()
        viewModel.fetchSharedEntity(id: id, kind: kind) { [weak self] result in
            guard let self else { return }
            self.isOpeningSharedContent = false
            ChatHUD.dismiss()
            switch result {
            case .success:
                self.navigateToSharedContent(id: id, kind: kind)
            case .failure:
                if self.openSharedContentAuthorProfile(from: message) {
                    return
                }
                self.navigateToSharedContent(id: id, kind: kind)
            }
        }
    }

    private func navigateToSharedContent(id: String, kind: ChatDetailViewModel.SharedEntityKind) {
        AppLogger.debug("[Chat] shared \(kind) \(id) is not supported in FlirtTime")
    }

    /// Private / forbidden shares open the author's profile instead of an empty vibe/post.
    @discardableResult
    private func openSharedContentAuthorProfile(from message: ConversationMessage) -> Bool {
        let authorId = message.sharedAuthorUserId
        let authorUsername = message.sharedAuthorUsername
        let currentUserId = viewModel.getCurrentUserId()
        let currentUserName = BetterUserDefaults(defaults: UserDefaults.standard).user?.userName

        if let authorId, !authorId.isEmpty,
           authorId.caseInsensitiveCompare(currentUserId) == .orderedSame {
            return false
        }
        if let authorUsername, let currentUserName,
           authorUsername.caseInsensitiveCompare(currentUserName) == .orderedSame {
            return false
        }

        let hasId = authorId?.isEmpty == false
        let hasUsername = authorUsername?.isEmpty == false
        guard hasId || hasUsername else { return false }

        view.endEditing(true)
        let seedUser = UserRes(
            id: authorId,
            userId: authorId,
            userName: authorUsername,
            fullName: message.sharedPost?.author?.fullName ?? message.sharedContentInfo?.authorName,
            profilePicture: message.sharedPost?.author?.profilePicture
                ?? message.sharedContentInfo?.authorImage
        )
        ChatProfileRouter.openProfile(of: seedUser, from: self)
        return true
    }

    // MARK: - Deep Link Navigation

    private func openProfileFromDeepLink(userName: String, isFromSharedLink: Bool = false, postId: String? = nil) {
        view.endEditing(true)
        AppLogger.debug("[Chat] profile deep link @\(userName) is not supported in FlirtTime")
    }

    private func openChannelFromDeepLink(channelId: String) {
        view.endEditing(true)
        AppLogger.debug("[Chat] channel link \(channelId) is not supported in FlirtTime")
    }

    private func openChannelFromDeepLinkBySlug(_ slug: String) {
        view.endEditing(true)
        AppLogger.debug("[Chat] channel link \(slug) is not supported in FlirtTime")
    }

    func cellDidTapViewVotes(_ cell: BaseMessageCell, model: MessageCellModel) {
        let latestMessage = viewModel.stateManager.messageById(model.message.id) ?? model.message
        guard let poll = latestMessage.poll ?? model.pollData else { return }
        let currentUserId = viewModel.getCurrentUserId()

        // Voters list is creator-only; everyone else only sees vote counts on the bubble.
        let isCreator = poll.isCreatedBy(userId: currentUserId)
            || (!model.isIncoming && (poll.createdBy == nil || poll.createdBy?.isEmpty == true))
        guard isCreator else {
            GlobalToast.shared.show("Only the poll creator can view voters")
            return
        }
        if poll.isAnonymousPoll {
            GlobalToast.shared.show("This poll is anonymous")
            return
        }

        let pollId = (poll.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let swiftUIView = PollVotesSheetView(
            pollId: pollId,
            pollQuestion: poll.question,
            options: poll.options,
            currentUserId: currentUserId,
            canSeeVoters: true
        )
        ChatSwiftUIHost.present(
            swiftUIView,
            style: .pageSheet,
            detents: [.large()],
            prefersGrabber: true,
            from: self
        )
    }

    func cellDidTapLocation(_ cell: BaseMessageCell, model: MessageCellModel) {
        guard let location = model.locationData else { return }
        let lat = location.lat ?? 0
        let lng = location.lng ?? 0
        let coordString = String(format: "%.7f,%.7f", lat, lng)

        let alert = UIAlertController(title: "Open Location", message: nil, preferredStyle: .actionSheet)

        if let googleURL = URL(string: "comgooglemaps://?daddr=\(coordString)&directionsmode=driving"),
           UIApplication.shared.canOpenURL(googleURL) {
            alert.addAction(UIAlertAction(title: ChatStrings.chat_googleMaps.localizedString(), style: .default) { _ in
                UIApplication.shared.open(googleURL)
            })
        } else if let webURL = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordString)") {
            alert.addAction(UIAlertAction(title: ChatStrings.chat_googleMaps.localizedString(), style: .default) { _ in
                UIApplication.shared.open(webURL)
            })
        }

        if let appleURL = URL(string: "http://maps.apple.com/?daddr=\(coordString)&dirflg=d&t=m") {
            alert.addAction(UIAlertAction(title: ChatStrings.chat_appleMaps.localizedString(), style: .default) { _ in
                UIApplication.shared.open(appleURL)
            })
        }

        alert.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Message Options Menu

    func presentMessageOptions(for model: MessageCellModel, sourceView: UIView) {
        view.endEditing(true)

        // Always prefer live state so Translate / See translation / See original stay in sync
        // after REST translate updates `translation` + `showingTranslations`.
        let message = viewModel.message(byId: model.message.id) ?? model.message
        let isPinned = isMessagePinned(model)

        // Only optimistic local temps get the Delete/Retry-only sheet.
        // Outgoing messages with unknown delivery fall back to `.sending` in DeliveryStatus.from,
        // which previously hid Pin/Unpin and looked like a delete popup.
        let isLocalTemp = message.isOptimisticTemporary
        let isPendingOrFailed = !model.isIncoming
            && (model.deliveryStatus == .sending || model.deliveryStatus == .failed)
            && isLocalTemp
            && !isPinned
        if isPendingOrFailed {
            let sheet = MessageOptionsSheet()
            sheet.configure(
                message: message,
                displayContent: model.displayContent,
                canCopy: false,
                canTranslate: false,
                translateTitle: nil,
                canEdit: false,
                canDelete: true,
                canDeleteForEveryone: false,
                canPin: false,
                canForward: false,
                canReply: false,
                canRetry: model.deliveryStatus == .failed,
                isPinned: false,
                onReact: { _ in },
                onCopy: {},
                onReply: {},
                onForward: {},
                onSelect: {},
                onTranslate: {},
                onEdit: {},
                onPin: {},
                onMessageInfo: {},
                onRetry: { [weak self] in
                    self?.viewModel.retryFailedMessage(tempId: message.id)
                },
                onDeleteForMe: { [weak self] in
                    self?.messageToDelete = message
                    self?.deleteForEveryone = false
                    self?.presentDeleteConfirmation()
                },
                onDeleteForEveryone: {},
                onPlusReaction: { [weak self] in
                    self?.presentEmojiPickerSheet { emoji in
                        guard !message.id.isEmpty else { return }
                        self?.viewModel.reactToMessage(messageId: message.id, emoji: emoji)
                    }
                }
            )
            sheet.present(in: view)
            return
        }

        let msgType = (message.messageType ?? message.type ?? "").lowercased()
        let isTextMessage = msgType == "text" || msgType.isEmpty
        let canCopy  = isTextMessage && !model.displayContent.isEmpty
        let isContactMsg = message.metadata?["isContact"]?.value as? Bool == true
        let canEdit  = !model.isIncoming && !isContactMsg && isTextMessage
        let canDel   = viewModel.canDeleteForEveryone(message: message)
        let canTranslate = shouldEnableTranslate(for: message)
        let translateTitle = translateButtonTitle(for: message)
        let canForward = !isPollMessage(message)

        let sheet = MessageOptionsSheet()
        sheet.configure(
            message: message,
            displayContent: model.displayContent,
            canCopy: canCopy,
            canTranslate: canTranslate,
            translateTitle: translateTitle,
            canEdit: canEdit,
            canDelete: true,
            canDeleteForEveryone: canDel,
            canPin: true,
            canForward: canForward,
            canReply: true,
            canMessageInfo: !model.isIncoming,
            isPinned: isPinned,
            onReact:             { [weak self] emoji in
                guard !message.id.isEmpty else { return }
                self?.viewModel.reactToMessage(messageId: message.id, emoji: emoji)
            },
            onCopy:              { UIPasteboard.general.string = model.displayContent },
            onReply:             { [weak self] in _ = self?.viewModel.startReply(to: message); self?.inputBar.becomeFirstResponderInput() },
            onForward:           {},
            onSelect:            { [weak self] in self?.viewModel.enterSelectionMode(with: message.stableId) },
            onTranslate:         { [weak self] in
                let live = self?.viewModel.message(byId: message.id) ?? message
                self?.handleTranslateToggle(for: live)
            },
            onEdit:              { [weak self] in self?.viewModel.startEdit(message: message) },
            onPin:               { [weak self] in
                guard let self else { return }
                guard !message.id.isEmpty else { return }
                if isPinned {
                    self.viewModel.pinMessage(
                        messageId: message.id,
                        isPinned: false,
                        pinDuration: nil
                    )
                } else {
                    self.presentPinDurationSheet(messageId: message.id)
                }
            },
            onMessageInfo: { [weak self] in
                guard let self else { return }
                guard !message.id.isEmpty else { return }
                let infoVC = self.presentMessageInfoSheet()
                // Prefer REST `GET chat/messages/{id}/info`; fall back to local statuses.
                self.viewModel.fetchMessageInfo(messageId: message.id) { [weak self, weak infoVC] result in
                    guard let self, let infoVC else { return }
                    switch result {
                    case .success(let data):
                        let mapped = self.mapMessageInfoAPI(data)
                        if mapped.readBy.isEmpty && mapped.deliveredTo.isEmpty && mapped.sentTo.isEmpty {
                            let local = self.buildMessageInfoEntries(from: message)
                            infoVC.populate(readBy: local.readBy, deliveredTo: local.deliveredTo, sentTo: local.sentTo)
                        } else {
                            infoVC.populate(readBy: mapped.readBy, deliveredTo: mapped.deliveredTo, sentTo: mapped.sentTo)
                        }
                    case .failure:
                        let local = self.buildMessageInfoEntries(from: message)
                        infoVC.populate(readBy: local.readBy, deliveredTo: local.deliveredTo, sentTo: local.sentTo)
                    }
                }
            }, onDeleteForMe:       { [weak self] in
                self?.messageToDelete = message
                self?.deleteForEveryone = false
                self?.presentDeleteConfirmation()
            },
            onDeleteForEveryone: { [weak self] in
                self?.messageToDelete = message
                self?.deleteForEveryone = true
                self?.presentDeleteConfirmation()
            },
            onPlusReaction: { [weak self] in
                self?.presentEmojiPickerSheet { emoji in
                    guard !message.id.isEmpty else { return }
                    self?.viewModel.reactToMessage(messageId: message.id, emoji: emoji)
                }
            }
            
            
        )
        sheet.present(in: view)
    }

    /// Prefer live pin state over possibly stale cell model after optimistic pin.
    private func isMessagePinned(_ model: MessageCellModel) -> Bool {
        if model.isPinned { return true }
        let id = model.message.id
        guard !id.isEmpty else { return false }
        if viewModel.currentPinnedMessage?.id == id { return true }
        if viewModel.message(byId: id)?.isPinned == true { return true }
        // Also match by stableId when server id differs
        if let pinned = viewModel.currentPinnedMessage,
           !pinned.id.isEmpty,
           pinned.stableId == model.stableId || pinned.id == model.stableId {
            return true
        }
        return false
    }

    
    @discardableResult
    func presentMessageInfoSheet() -> MessageInfoSheetVC {
        let vc = MessageInfoSheetVC()
        vc.modalPresentationStyle = .pageSheet

        if let sheet = vc.sheetPresentationController {
            sheet.detents = [
                .medium(),
                .large()
            ]
            sheet.prefersGrabberVisible = true
        }

        self.present(vc, animated: true)
        return vc
    }

    private func buildMessageInfoEntries(from message: ConversationMessage) -> (readBy: [MessageInfoEntry], deliveredTo: [MessageInfoEntry], sentTo: [MessageInfoEntry]) {
        let currentUserId = viewModel.getCurrentUserId()
        let otherStatuses = (message.statuses ?? []).filter { $0.userId != currentUserId }

        var readBy: [MessageInfoEntry] = []
        var deliveredTo: [MessageInfoEntry] = []
        var sentTo: [MessageInfoEntry] = []

        for status in otherStatuses {
            let lower = status.status.lowercased()
            let isRead = (lower == "seen" || lower == "read")
            let isDelivered = lower == "delivered"

            guard let (fullName, userName, profileImage) = resolveMessageInfoProfile(for: status.userId) else { continue }
            let readAt = isRead ? (status.statusUpdatedAt ?? status.updatedAt ?? message.seenAt) : message.seenAt
            let deliveredAt = (!isRead || isDelivered)
                ? (status.statusUpdatedAt ?? status.updatedAt ?? message.deliveredAt)
                : message.deliveredAt
            let sentAt = message.sentAt ?? message.createdAt

            let receipt: MessageInfoReceiptStatus
            if isRead { receipt = .read }
            else if isDelivered { receipt = .delivered }
            else { receipt = .sent }

            let entry = MessageInfoEntry(
                userId: status.userId,
                fullName: fullName,
                userName: userName,
                profileImage: profileImage,
                isVerified: false,
                receiptStatus: receipt,
                timestamp: isRead ? readAt : (isDelivered ? deliveredAt : sentAt),
                sentAt: sentAt,
                deliveredAt: deliveredAt,
                readAt: isRead ? readAt : nil
            )
            switch receipt {
            case .read: readBy.append(entry)
            case .delivered: deliveredTo.append(entry)
            case .sent: sentTo.append(entry)
            }
        }

        return (readBy, deliveredTo, sentTo)
    }

    /// Maps `GET chat/messages/{id}/info` payload into sheet rows.
    /// Supports NEW shape `data.info.recipients` and legacy `readBy` / `deliveredTo`.
    private func mapMessageInfoAPI(_ data: MessageInfoData) -> (readBy: [MessageInfoEntry], deliveredTo: [MessageInfoEntry], sentTo: [MessageInfoEntry]) {
        let currentUserId = viewModel.getCurrentUserId()

        // NEW API — recipients with per-user status
        if let recipients = data.info?.recipients, !recipients.isEmpty {
            var readBy: [MessageInfoEntry] = []
            var deliveredTo: [MessageInfoEntry] = []
            var sentTo: [MessageInfoEntry] = []

            for recipient in recipients {
                let userId = recipient.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !userId.isEmpty, userId != currentUserId else { continue }

                let status = (recipient.status ?? data.info?.status ?? "").lowercased()
                let hasRead = recipient.readAt != nil || status == "read" || status == "seen"
                let hasDelivered = recipient.deliveredAt != nil || status == "delivered"
                let profile = resolveMessageInfoProfile(for: userId)

                let receipt: MessageInfoReceiptStatus
                if hasRead { receipt = .read }
                else if hasDelivered { receipt = .delivered }
                else { receipt = .sent }

                let entry = MessageInfoEntry(
                    userId: userId,
                    fullName: nonEmpty(recipient.fullName) ?? profile?.fullName,
                    userName: nonEmpty(recipient.username) ?? profile?.userName,
                    profileImage: nonEmpty(recipient.profilePicture) ?? profile?.profileImage,
                    isVerified: recipient.isVerified ?? false,
                    receiptStatus: receipt,
                    timestamp: hasRead
                        ? (recipient.readAt ?? data.info?.readAt)
                        : (hasDelivered
                           ? (recipient.deliveredAt ?? data.info?.deliveredAt)
                           : data.info?.sentAt),
                    sentAt: data.info?.sentAt,
                    deliveredAt: recipient.deliveredAt ?? data.info?.deliveredAt,
                    readAt: recipient.readAt ?? data.info?.readAt
                )

                switch receipt {
                case .read: readBy.append(entry)
                case .delivered: deliveredTo.append(entry)
                case .sent: sentTo.append(entry)
                }
            }

            return (readBy, deliveredTo, sentTo)
        }

        // Legacy flat lists
        let readBy: [MessageInfoEntry] = (data.readBy ?? []).compactMap { row in
            let userId = row.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !userId.isEmpty, userId != currentUserId else { return nil }
            let profile = resolveMessageInfoProfile(for: userId)
            return MessageInfoEntry(
                userId: userId,
                fullName: nonEmpty(row.fullName) ?? profile?.fullName,
                userName: nonEmpty(row.userName) ?? profile?.userName,
                profileImage: nonEmpty(row.profileImage) ?? profile?.profileImage,
                isVerified: false,
                receiptStatus: .read,
                timestamp: row.at,
                sentAt: nil,
                deliveredAt: nil,
                readAt: row.at
            )
        }

        let readIds = Set(readBy.map(\.userId))
        let deliveredTo: [MessageInfoEntry] = (data.deliveredTo ?? []).compactMap { row in
            let userId = row.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !userId.isEmpty, userId != currentUserId, !readIds.contains(userId) else { return nil }
            let profile = resolveMessageInfoProfile(for: userId)
            return MessageInfoEntry(
                userId: userId,
                fullName: nonEmpty(row.fullName) ?? profile?.fullName,
                userName: nonEmpty(row.userName) ?? profile?.userName,
                profileImage: nonEmpty(row.profileImage) ?? profile?.profileImage,
                isVerified: false,
                receiptStatus: .delivered,
                timestamp: row.at,
                sentAt: nil,
                deliveredAt: row.at,
                readAt: nil
            )
        }

        return (readBy, deliveredTo, [])
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveMessageInfoProfile(for userId: String) -> (fullName: String?, userName: String?, profileImage: String?)? {
        if viewModel.isGroupChat {
            guard let participant = viewModel.groupParticipants.first(where: { $0.userId == userId }) else {
                return nil
            }
            return (participant.fullName, participant.userName, participant.profilePicture)
        }
        let other = viewModel.user ?? viewModel.headerUserData
        return (
            other?.fullName,
            other?.userName,
            other?.profilePictureDetails?.filePath ?? other?.profilePicture
        )
    }

    // MARK: - Channel Admin Message Options

    func presentChannelAdminMessageOptions(for model: MessageCellModel) {
        AppLogger.debug("Channel admin options are not supported in FlirtTime chat")
    }

    // MARK: - Translation Helpers

    func isTextMessage(_ message: ConversationMessage) -> Bool {
        let messageType = (message.messageType ?? message.type ?? "").lowercased()
        return messageType == "text" || messageType.isEmpty
    }

    func isPollMessage(_ message: ConversationMessage) -> Bool {
        let messageType = (message.messageType ?? message.type ?? "").lowercased()
        return messageType == "poll"
    }

    func shouldEnableTranslate(for message: ConversationMessage) -> Bool {
        guard isTextMessage(message) else { return false }
        guard !message.id.isEmpty else { return false }
        let live = viewModel.message(byId: message.id) ?? message
        if live.hasTranslation { return true }
        if viewModel.isShowingTranslation(for: live.id) { return true }
        return shouldOfferTranslation(for: live)
    }

    func translateButtonTitle(for message: ConversationMessage) -> String? {
        guard isTextMessage(message) else { return nil }
        guard !message.id.isEmpty else { return nil }

        let live = viewModel.message(byId: message.id) ?? message

        // Only two states: Translate ↔ See original (never "See translation")
        if viewModel.isShowingTranslation(for: live.id) {
            return ChatStrings.chat_seeOriginal.localizedString()
        }

        return shouldOfferTranslation(for: live) ? ChatStrings.chat_translate.localizedString() : nil
    }

    func handleTranslateToggle(for message: ConversationMessage) {
        guard !message.id.isEmpty else { return }
        let live = viewModel.message(byId: message.id) ?? message

        // Currently showing translation → switch back to original
        if viewModel.isShowingTranslation(for: live.id) {
            viewModel.toggleTranslation(for: live.id)
            return
        }

        // Otherwise always open language picker (Translate)
        guard shouldOfferTranslation(for: live) else { return }
        presentTranslateLanguagePicker(for: live)
    }

    func presentTranslateLanguagePicker(for message: ConversationMessage) {
        guard !message.id.isEmpty else { return }
        let messageId = message.id
        let storedLang = (message.metadata?["_translationLanguage"]?.value as? String)
            ?? preferredLanguageCode()

        // Wait for MessageOptionsSheet dismiss animation so the picker is not covered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self else { return }
            let sheet = TranslateLanguagePickerSheet()
            sheet.onLanguageSelected = { [weak self] entry in
                self?.viewModel.translateMessage(
                    messageId: messageId,
                    targetLanguage: entry.code
                )
            }
            sheet.present(in: self.view, selectedCode: storedLang)
        }
    }

    func shouldOfferTranslation(for message: ConversationMessage) -> Bool {
        let content = message.originalContentForDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        return !content.isEmpty
    }

    func preferredLanguageCode() -> String? {
        let code = getSelectedLanguage().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return code.isEmpty ? "en" : code
    }

    /// Normalize `en`, `en-US`, `en_US` → `en` for translation language checks.
    func normalizedLanguageCode(_ code: String) -> String {
        let lower = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return lower.split(separator: "-").first.map(String.init) ?? lower
    }

    func languagesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedLanguageCode(lhs) == normalizedLanguageCode(rhs)
    }

    // MARK: - Media Viewer

    func presentMediaViewer(for model: MessageCellModel, sourceCell: BaseMessageCell, mediaIndex: Int = 0) {
        let galleryItems = MediaGalleryBuilder.buildGalleryItems(from: viewModel.messages)
        guard !galleryItems.isEmpty else { return }

        let messageItems = galleryItems.enumerated().filter { $0.element.messageId == model.message.id }
        let tappedIndex: Int
        if !messageItems.isEmpty {
            let clamped = min(max(mediaIndex, 0), messageItems.count - 1)
            tappedIndex = messageItems[clamped].offset
        } else {
            tappedIndex = galleryItems.firstIndex(where: { $0.messageId == model.message.id }) ?? 0
        }
        let viewer = MediaViewerController(
            items: galleryItems,
            initialIndex: tappedIndex,
            sourceView: sourceCell.mediaImageView
        )
        present(viewer, animated: false)
    }

    // MARK: - Reaction Users List

    func presentReactionUsersList(reactions: [MessageReaction], messageId: String) {
        let listView = ReactionUsersListView(
            reactions: reactions,
            groupParticipants: viewModel.groupParticipants,
            headerUserData: viewModel.headerUserData,
            currentUserId: viewModel.getCurrentUserId(),
            currentUserName: viewModel.userListViewModel.sessionManager?.user?.userName,
            currentUserFullName: viewModel.userListViewModel.sessionManager?.user?.fullName,
            currentUserProfilePicture: viewModel.userListViewModel.sessionManager?.user?.profilePicture,
            findSenderByUserId: { [weak self] userId in
                if let info = self?.viewModel.findSenderByUserId(userId) {
                    return (info.fullName, info.userName, info.profilePicture)
                }
                return nil
            },
            onRemoveReaction: { [weak self] emoji in
                self?.viewModel.reactToMessage(messageId: messageId, emoji: emoji)
            }
        )
        ChatSwiftUIHost.present(
            listView,
            style: .pageSheet,
            detents: [.medium(), .large()],
            prefersGrabber: false,
            from: self
        )
    }

    // MARK: - Expand / Collapse

    func cellDidToggleExpand(_ cell: BaseMessageCell) {
        guard let model = cell.cellModel else { return }
        let id = model.stableId
        if expandedMessageIds.contains(id) {
            expandedMessageIds.remove(id)
        } else {
            expandedMessageIds.insert(id)
        }
        dataSource?.expandedMessageIds = expandedMessageIds

        let contentOffset = collectionView.contentOffset
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: .allowUserInteraction) {
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
        } completion: { _ in
            self.collectionView.setContentOffset(contentOffset, animated: false)
        }
    }
}
