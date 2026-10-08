import UIKit

// MARK: - ChatMessageInputBarDelegate

extension ChatDetailViewController: ChatMessageInputBarDelegate {

    func inputBarDidSend(_ inputBar: ChatMessageInputBar) {
        let trimmed = inputBar.messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let mentions = viewModel.mentionManager.buildMentionsMetadata(for: trimmed)
        let socketMentions = viewModel.mentionManager.buildSocketMentions(for: trimmed)
        viewModel.sendMessage(text: trimmed, mentions: mentions, socketMentions: socketMentions)

        inputBar.messageText = ""
        inputBar.resetHeight()
        updateContentInsets()

        let cid = isChannel ? channelId : selectedId
        if !cid.isEmpty {
            ConversationDraftStore.shared.remove(conversationId: cid)
        }
    }

    func inputBar(_ inputBar: ChatMessageInputBar, didEditText text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.editMessage(newText: trimmed)
        inputBar.messageText = ""
        inputBar.resetHeight()
        updateContentInsets()
    }

    func inputBarDidChangeHeight(_ inputBar: ChatMessageInputBar, height: CGFloat) {
        updateContentInsets(skipThreshold: 0.5)
    }

    func inputBarDidToggleAttachment(_ inputBar: ChatMessageInputBar) {
        if !inputBar.showingAttachmentSheet {
            if attachmentPanel != nil {
                dismissAttachmentPanel()
            }
            return
        }

        if attachmentPanel != nil { return }

        if keyboardHeight > 0 {
            pendingAttachmentFromKeyboard = true
            inputBar.resignFirstResponderInput()
        } else {
            presentAttachmentPanel()
        }
    }

    func inputBarDidTapCamera(_ inputBar: ChatMessageInputBar) {
        inputBar.resignFirstResponderInput()

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showMediaPicker(camera: false)
            return
        }

        presentChatCamera()
    }

    private func presentChatCamera() {
        let controller = ChatCameraController()
        controller.modalPresentationStyle = .fullScreen
        controller.onSend = { [weak self] output in
            guard let self else { return }
            switch output {
            case .image(let image):
                self.viewModel.sendImage(image)
            case .video(let url, let cropAspect):
                self.viewModel.sendVideo(url, cropAspect: cropAspect)
            }
        }
        present(controller, animated: true)
    }

    func inputBarDidTapMicrophone(_ inputBar: ChatMessageInputBar) {
        inputBar.resignFirstResponderInput()
        viewModel.startAudioRecording()
    }

    func inputBarDidCloseAttachment(_ inputBar: ChatMessageInputBar) {
        
    }

    func inputBarTextDidChange(_ inputBar: ChatMessageInputBar, text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.userStoppedTyping()
        } else {
            viewModel.userDidType()
        }
    }

    func inputBar(_ inputBar: ChatMessageInputBar, mentionQueryChanged query: String?, range: Range<String.Index>?) {
        if let query, let range {
            let nsRange = NSRange(range, in: inputBar.textView.text ?? "")
            viewModel.mentionManager.updateQuery(query, range: range)
        } else {
            viewModel.mentionManager.dismiss()
        }
    }

    func inputBar(_ inputBar: ChatMessageInputBar, didSelectMention participant: GroupParticipant) {
        guard let result = viewModel.mentionManager.selectParticipant(participant) else { return }
        if let range = result.replacingRange {
            let nsRange = NSRange(range, in: inputBar.textView.text ?? "")
            inputBar.textView.text = ((inputBar.textView.text ?? "") as NSString).replacingCharacters(in: nsRange, with: result.text)
        } else {
            inputBar.textView.text = (inputBar.textView.text ?? "") + result.text
        }
        viewModel.mentionManager.dismiss()
        inputBar.textViewDidChange(inputBar.textView)
    }
}

// MARK: - MentionAutocompleteDelegate

extension ChatDetailViewController: MentionAutocompleteDelegate {
    func mentionAutocomplete(_ view: MentionAutocompleteTableView, didSelect participant: GroupParticipant) {
        inputBar(inputBar, didSelectMention: participant)
    }
}
