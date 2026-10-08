import UIKit
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Attachment Panel & Presentation

extension ChatDetailViewController {

    func presentAttachmentPanel() {
        guard attachmentPanel == nil else { return }

        let panel = AttachmentPanelView(isChannel: isChannel)

        panel.onPhoto    = { [weak self] in self?.dismissAttachmentPanel(); self?.showMediaPicker(camera: false) }
        panel.onCamera   = { [weak self] in self?.dismissAttachmentPanel(); self?.showMediaPicker(camera: true) }
        panel.onLocation = { [weak self] in self?.dismissAttachmentPanel(); self?.presentSendLocation() }
        panel.onContact  = { [weak self] in self?.dismissAttachmentPanel(); self?.presentSendContact() }

        inputStack.addArrangedSubview(panel)
        attachmentPanel = panel

        panel.animateIn()

        updateContentInsets(
            animated: true,
            duration: 0.38,
            springWithDamping: 0.9,
            initialVelocity: 0,
            overrideInputHeight: inputContainer.frame.height + 112
        )
    }

    func presentAttachmentPanelCoordinated(duration: TimeInterval, animationCurve: UInt) {
        guard attachmentPanel == nil else {
            updateContentInsets(
                animated: true,
                duration: duration,
                animationCurve: animationCurve,
                bottomConstraintConstant: inputBarBottomConstant()
            )
            return
        }

        let panel = AttachmentPanelView(isChannel: isChannel)

        panel.onPhoto    = { [weak self] in self?.dismissAttachmentPanel(); self?.showMediaPicker(camera: false) }
        panel.onCamera   = { [weak self] in self?.dismissAttachmentPanel(); self?.showMediaPicker(camera: true) }
        panel.onLocation = { [weak self] in self?.dismissAttachmentPanel(); self?.presentSendLocation() }
        panel.onContact  = { [weak self] in self?.dismissAttachmentPanel(); self?.presentSendContact() }

        inputStack.addArrangedSubview(panel)
        attachmentPanel = panel

        let targetInputHeight = inputContainer.frame.height + panel.expandedHeight

        updateContentInsets(
            animated: true,
            duration: duration,
            animationCurve: animationCurve,
            overrideInputHeight: targetInputHeight,
            bottomConstraintConstant: inputBarBottomConstant()
        )

        panel.panelHeightConstraint?.constant = panel.expandedHeight
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.init(rawValue: animationCurve << 16), .beginFromCurrentState]
        ) {
            self.view.layoutIfNeeded()
        }
    }


    
    func dismissAttachmentPanel(animated: Bool = true) {
        guard let panel = attachmentPanel else { return }
        attachmentPanel = nil
        inputBar.resetAttachmentButton()
        inputBar.showingAttachmentSheet = false

        if animated {
            let heightAfterDismiss = max(0, inputContainer.frame.height - panel.frame.height)

            panel.animateOut()

            updateContentInsets(
                animated: true,
                duration: 0.26,
                springWithDamping: 1.0,
                initialVelocity: 0,
                overrideInputHeight: heightAfterDismiss
            )
        } else {
            panel.removeFromSuperview()
            updateContentInsets(animated: false)
        }
    }

    func showMediaPicker(camera: Bool) {
        if camera && UIImagePickerController.isSourceTypeAvailable(.camera) {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.mediaTypes = ["public.image", "public.movie"]
            picker.delegate = self
            picker.modalPresentationStyle = .fullScreen
            present(picker, animated: true)
            return
        }

        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 10
        config.filter = .any(of: [.images, .videos])
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }
}

// MARK: - UIImagePickerControllerDelegate

extension ChatDetailViewController {
    @objc func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
            picker.dismiss(animated: true) { [weak self] in
                self?.viewModel.sendImage(image)
            }
        } else if let videoURL = info[.mediaURL] as? URL {
            picker.dismiss(animated: true) { [weak self] in
                self?.viewModel.sendVideo(videoURL)
            }
        }
    }

    @objc func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension ChatDetailViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }

        let group = DispatchGroup()
        var ordered: [Int: MediaPickerResult] = [:]
        let lock = NSLock()
        let totalCount = results.count

        for (index, result) in results.enumerated() {
            let provider = result.itemProvider

            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    defer { group.leave() }
                    guard let url, error == nil else {
                        AppLogger.debug("[PHPicker] video load failed at \(index): \(String(describing: error))")
                        return
                    }
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(UUID().uuidString).mp4")
                    do {
                        try FileManager.default.copyItem(at: url, to: dest)
                        lock.lock(); ordered[index] = .video(dest); lock.unlock()
                    } catch {
                        AppLogger.debug("[PHPicker] video copy failed at \(index): \(error)")
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                    if let url, error == nil,
                       let data = try? Data(contentsOf: url),
                       let image = UIImage(data: data) {
                        lock.lock(); ordered[index] = .image(image); lock.unlock()
                        group.leave()
                        return
                    }
                    // Fallback for formats loadFileRepresentation struggles with
                    if provider.canLoadObject(ofClass: UIImage.self) {
                        provider.loadObject(ofClass: UIImage.self) { object, _ in
                            defer { group.leave() }
                            if let image = object as? UIImage {
                                lock.lock(); ordered[index] = .image(image); lock.unlock()
                            } else {
                                AppLogger.debug("[PHPicker] image fallback failed at \(index)")
                            }
                        }
                    } else {
                        AppLogger.debug("[PHPicker] image load failed at \(index): \(String(describing: error))")
                        group.leave()
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, error in
                    defer { group.leave() }
                    guard let image = object as? UIImage, error == nil else {
                        AppLogger.debug("[PHPicker] image object load failed at \(index)")
                        return
                    }
                    lock.lock(); ordered[index] = .image(image); lock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let sorted = ordered.sorted { $0.key < $1.key }.map { $0.value }
            let skipped = totalCount - sorted.count
            if skipped > 0 {
                AppLogger.debug("[PHPicker] skipped \(skipped)/\(totalCount) items during load")
            }
            guard !sorted.isEmpty else { return }

            if sorted.count == 1 {
                switch sorted[0] {
                case .image(let image): self.viewModel.sendImage(image)
                case .video(let url): self.viewModel.sendVideo(url)
                }
            } else {
                self.viewModel.sendMediaAlbum(sorted)
            }
        }
    }
}

// MARK: - Delete Confirmation Alert

extension ChatDetailViewController {
    func presentDeleteConfirmation() {
        guard let message = messageToDelete else { return }
        let title = deleteForEveryone ? ChatStrings.chat_deleteForEveryone.localizedString() : ChatStrings.chat_deleteForMe.localizedString()
        let messageText = deleteForEveryone
            ? ChatStrings.chat_deleteMsgConfirmAll.localizedString()
            : ChatStrings.chat_deleteMsgConfirmMe.localizedString()

        let alert = UIAlertController(title: title, message: messageText, preferredStyle: .alert)
        let actionTitle = deleteForEveryone
            ? ChatStrings.chat_deleteForEveryone.localizedString()
            : ChatStrings.chat_deleteForMe.localizedString()
        alert.addAction(UIAlertAction(title: actionTitle, style: .destructive) { [weak self] _ in
            guard let self else { return }
            if self.deleteForEveryone {
                self.viewModel.deleteMessageForEveryone(messageId: message.id)
            } else {
                self.animateDeleteForMe(messageId: message.id)
            }
            self.messageToDelete = nil
        })
        alert.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel) { [weak self] _ in
            self?.messageToDelete = nil
        })
        present(alert, animated: true)
    }

    func animateDeleteForMe(messageId: String) {
        guard let indexPath = dataSource?.indexPath(forItemId: messageId),
              let cell = collectionView.cellForItem(at: indexPath) else {
            viewModel.deleteMessageForMe(messageId: messageId)
            return
        }

        cell.isUserInteractionEnabled = false
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                cell.alpha = 0
                cell.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            },
            completion: { [weak self] _ in
                self?.viewModel.deleteMessageForMe(messageId: messageId)
            }
        )
    }

    func presentDeleteChatConfirmation() {
        let userName = user?.fullName ?? user?.userName
            ?? viewModel.headerUserData?.fullName ?? viewModel.headerUserData?.userName ?? ""
        let alert = UIAlertController(
            title: ChatStrings.chat_deleteChatConfirmation.localizedString(),
            message: String(format: ChatStrings.chat_deleteChatDescription.localizedString(), userName),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: ChatStrings.chat_deleteChat.localizedString(),
            style: .destructive
        ) { [weak self] _ in
            guard let self else { return }
            self.viewModel.deleteChat(id: self.selectedId)
        })
        alert.addAction(UIAlertAction(
            title: ChatStrings.chat_cancel.localizedString(),
            style: .cancel
        ))
        present(alert, animated: true)
    }
}

// MARK: - Conversation Menu

extension ChatDetailViewController {

    func presentConversationMenu() {
        view.endEditing(true)
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.view.tintColor = ChatTheme.primary
        sheet.addAction(UIAlertAction(title: ChatStrings.viewProfile.localizedString(), style: .default) { [weak self] _ in
            self?.onProfileTap?()
        })
        sheet.addAction(UIAlertAction(title: ChatStrings.chat_report.localizedString(), style: .default) { [weak self] _ in
            self?.presentReportReasons()
        })
        if viewModel.isBlocked {
            sheet.addAction(UIAlertAction(title: ChatStrings.chat_unblock.localizedString(), style: .default) { [weak self] _ in
                self?.viewModel.unblockUser(userID: "")
            })
        } else {
            sheet.addAction(UIAlertAction(title: ChatStrings.chat_block.localizedString(), style: .destructive) { [weak self] _ in
                self?.confirmBlockUser()
            })
        }
        sheet.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel))
        anchorPopover(of: sheet)
        present(sheet, animated: true)
    }

    func presentReportReasons() {
        let sheet = UIAlertController(
            title: ChatStrings.chat_reportConfirmation.localizedString(),
            message: ChatStrings.chat_reportDescription.localizedString(),
            preferredStyle: .actionSheet
        )
        sheet.view.tintColor = ChatTheme.primary
        let reasons = ["Spam", "Inappropriate content", "Fake profile", "Harassment"]
        for reason in reasons {
            sheet.addAction(UIAlertAction(title: reason, style: .default) { [weak self] _ in
                guard let self else { return }
                let peerId = self.viewModel.selectedUserChatID
                if !ChatMockSeeder.isMockMode, !peerId.isEmpty {
                    self.viewModel.userListViewModel.reportUser(userID: peerId, reason: reason)
                }
                GlobalToast.shared.show(ChatStrings.chat_report.localizedString() + " ✓")
            })
        }
        sheet.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel))
        anchorPopover(of: sheet)
        present(sheet, animated: true)
    }

    private func confirmBlockUser() {
        let alert = UIAlertController(
            title: ChatStrings.chat_blockUserConfirmation.localizedString(),
            message: ChatStrings.chat_blockUserDescription.localizedString(),
            preferredStyle: .alert
        )
        alert.view.tintColor = ChatTheme.primary
        alert.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel))
        alert.addAction(UIAlertAction(title: ChatStrings.chat_block.localizedString(), style: .destructive) { [weak self] _ in
            self?.viewModel.blockUserInConversation()
        })
        present(alert, animated: true)
    }

    private func anchorPopover(of controller: UIAlertController) {
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.maxX - 40, y: view.safeAreaInsets.top + 30, width: 1, height: 1)
    }
}

// MARK: - Empty Conversation Card

extension ChatDetailViewController {

    func updateEmptyProfileCard(itemCount: Int) {
        let profile = itemCount == 0 && !isGroupChat && !isChannel ? emptyCardProfile() : nil
        guard let profile else {
            emptyProfileCard?.removeFromSuperview()
            emptyProfileCard = nil
            return
        }

        let card = emptyProfileCard ?? makeEmptyProfileCard()
        card.configure(with: profile)
    }

    private func makeEmptyProfileCard() -> ChatEmptyProfileCardView {
        let card = ChatEmptyProfileCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.onProfile = { [weak self] in self?.onProfileTap?() }
        card.onReport = { [weak self] in self?.presentReportReasons() }
        view.insertSubview(card, aboveSubview: collectionView)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -30),
        ])
        emptyProfileCard = card
        return card
    }

    private func emptyCardProfile() -> ChatEmptyProfileCardView.Profile? {
        let peerId = viewModel.selectedUserChatID.isEmpty ? selectedUserChatID : viewModel.selectedUserChatID
        if let mock = ChatMockSeeder.profile(forPeerId: peerId) { return mock }

        guard let peer = viewModel.headerUserData ?? user else { return nil }
        let name = (peer.fullName ?? peer.userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return ChatEmptyProfileCardView.Profile(
            name: name,
            avatarURL: peer.profilePicture,
            distanceMiles: peer.distanceKm.map { Int(($0 * 0.621371).rounded()) }
        )
    }
}

// MARK: - Location & Contact Sharing

extension ChatDetailViewController {

    func presentSendLocation() {
        let locationView = SendLocationView(onLocationSent: { [weak self] request in
            self?.viewModel.sendLocation(locationRequest: request)
        })
        ChatSwiftUIHost.present(locationView, style: .fullScreen, from: self)
    }

    func presentSendContact() {
        let contactView = SendContactView(onContactSelected: { [weak self] contact in
            let phone = contact.phoneNumbers.first ?? ""
            let contactText = "Contact: \(contact.name)\nPhone: \(phone)"
            let meta = ["contactName": contact.name, "contactPhone": phone]
            self?.viewModel.sendMessage(text: contactText, isContact: true, contactMeta: meta)
        })
        ChatSwiftUIHost.present(contactView, style: .fullScreen, from: self)
    }
}
