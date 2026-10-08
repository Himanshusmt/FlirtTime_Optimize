//
//  ChatDetailViewModel+UserListDelegate.swift
//  FlirttimeNew
//

import Foundation

// MARK: - ChatUserListViewModelDelegate

extension ChatDetailViewModel: ChatUserListViewModelDelegate {

    func didReceiveData() {
        AppLogger.debug("ChatDetailViewModel: didReceiveData")
    }

    func didReceiveError() {
        AppLogger.debug("ChatDetailViewModel: didReceiveError")
        DispatchQueue.main.async {
            self.showError("Failed to load data. Please try again.")
        }
    }

    func didDeleteChat() {
        AppLogger.debug("ChatDetailViewModel: Chat deleted successfully")
        DispatchQueue.main.async {
            self.showSuccess("Chat deleted successfully")
            self.onConversationDeleted?()
        }
    }

    func didDeleteMessage() {
        AppLogger.debug("ChatDetailViewModel: Message deleted successfully")
        DispatchQueue.main.async {
            self.showSuccess(ChatStrings.chat_messageDeleted.localizedString())
        }
    }

    func didFailedToDeleteMessage() {
        AppLogger.debug("ChatDetailViewModel: Failed to delete message")
        DispatchQueue.main.async {
            self.showError("Failed to delete message")
        }
    }

    func didFailedToDelete() {
        AppLogger.debug("ChatDetailViewModel: Failed to delete chat")
        DispatchQueue.main.async {
            self.showError("Failed to delete chat")
        }
    }

    func didReportChat() {
        AppLogger.debug("ChatDetailViewModel: Chat reported successfully")
        DispatchQueue.main.async {
            self.showSuccess("Chat reported successfully")
        }
    }

    func didIsBlockedUser() {
        AppLogger.debug("ChatDetailViewModel: User is blocked")
        DispatchQueue.main.async {
            self.applyBlockUIState(isBlocked: true)
        }
    }

    func didBlockUser() {
        AppLogger.debug("ChatDetailViewModel: User blocked successfully")
        DispatchQueue.main.async {
            self.applyBlockUIState(isBlocked: true)
            self.showSuccess("User blocked")
            if !self.selectedId.isEmpty {
                NotificationCenter.default.post(
                    name: .ChatBlockStatusChanged,
                    object: nil,
                    userInfo: ["conversationId": self.selectedId, "isBlocked": true]
                )
            }
        }
    }

    func didUnBlockUser() {
        AppLogger.debug("ChatDetailViewModel: User unblocked successfully")
        DispatchQueue.main.async {
            self.applyBlockUIState(isBlocked: false)
            self.showSuccess("User unblocked")
            if !self.selectedId.isEmpty {
                NotificationCenter.default.post(
                    name: .ChatBlockStatusChanged,
                    object: nil,
                    userInfo: ["conversationId": self.selectedId, "isBlocked": false]
                )
            }
        }
    }

    func didFailedToBlockUser() {
        AppLogger.debug("ChatDetailViewModel: Failed to block user")
        DispatchQueue.main.async {
            self.showError("Failed to block user")
        }
    }

    func didFailedToUnBlockUser() {
        AppLogger.debug("ChatDetailViewModel: Failed to unblock user")
        DispatchQueue.main.async {
            self.showError("Failed to unblock user")
        }
    }

    func didReceiveUnauthorizedError(_ message: String, _ statusCode: String) {
        AppLogger.debug("ChatDetailViewModel: Unauthorized error - \(message) (\(statusCode))")
        DispatchQueue.main.async {
            self.showError("Session expired. Please login again.")
        }
    }

    func showSuccess(_ message: String) {
        AppLogger.debug("Success: \(message)")
    }

    func showError(_ message: String) {
        AppLogger.debug("Error: \(message)")
    }
}
