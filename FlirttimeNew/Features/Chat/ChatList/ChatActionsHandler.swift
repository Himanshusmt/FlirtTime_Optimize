//
//  ChatActionsHandler.swift
//  FlirttimeNew
//
//  Created by Awais on 27/08/2025.
//

import SwiftUI

final class ChatActionsHandler: ObservableObject {
    @Published var showConfirmation = false
    @Published var confirmationAction: ChatAction?
    @Published var selectedChatForAction: ChatMessageRow?
    @Published var showDeleteForEveryoneConfirmation = false
    @Published var deleteForEveryoneChat: ChatMessageRow?

    func showAction(_ action: ChatAction, for chat: ChatMessageRow) {
        selectedChatForAction = chat
        confirmationAction = action
        showConfirmation = true
    }

    func hideConfirmation() {
        showConfirmation = false
        confirmationAction = nil
        selectedChatForAction = nil
    }

    func showDeleteForEveryone(for chat: ChatMessageRow) {
        deleteForEveryoneChat = chat
        showDeleteForEveryoneConfirmation = true
    }

    func hideDeleteForEveryone() {
        showDeleteForEveryoneConfirmation = false
        deleteForEveryoneChat = nil
    }
}

struct ChatActionOverlay: View {
    @ObservedObject var actionsHandler: ChatActionsHandler
    @ObservedObject var viewModel: ChatListViewModel

    var body: some View {
        Group {
            if actionsHandler.showDeleteForEveryoneConfirmation,
               let chat = actionsHandler.deleteForEveryoneChat {
                ConfirmationModal.deleteChatForEveryone(
                    userName: getChatName(chat),
                    onDelete: {
                        // DELETE /api/v1/chat/conversations/{id}?scope=everyone
                        handleDeleteChat(chat: chat, forEveryone: true)
                        actionsHandler.hideDeleteForEveryone()
                    },
                    onDismiss: { actionsHandler.hideDeleteForEveryone() }
                )
            } else if actionsHandler.showConfirmation,
                      let chat = actionsHandler.selectedChatForAction,
                      let action = actionsHandler.confirmationAction {

                switch action {
                case .archive:
                    ConfirmationModal.archiveChat(
                        chatName: getChatName(chat),
                        onArchive: {
                            viewModel.archiveChat(chatId: chat.id ?? "", isArchived: true)
                            actionsHandler.hideConfirmation()
                        },
                        onDismiss: { actionsHandler.hideConfirmation() }
                    )
                case .mute:
                    ConfirmationModal.muteChat(
                        chatName: getChatName(chat),
                        onMute: {
                            handleMuteChat(chat: chat)
                            actionsHandler.hideConfirmation()
                        },
                        onDismiss: { actionsHandler.hideConfirmation() }
                    )
                case .block:
                    let isBlocked = viewModel.isBlockedChat(chatId: chat.id ?? "")
                    if isBlocked {
                        ConfirmationModal.unblockUser(
                            userName: getChatName(chat),
                            onUnblock: {
                                handleUnblockChat(chat: chat)
                                actionsHandler.hideConfirmation()
                            },
                            onDismiss: { actionsHandler.hideConfirmation() }
                        )
                    } else {
                        ConfirmationModal.blockUser(
                            userName: getChatName(chat),
                            onBlock: {
                                handleBlockChat(chat: chat)
                                actionsHandler.hideConfirmation()
                            },
                            onDismiss: { actionsHandler.hideConfirmation() }
                        )
                    }
                case .delete:
                    let chatType = chat.type?.lowercased() ?? ""
                    let isGroup = chatType == "group" || chat.isGroup
                    let isChannel = chatType == "channel"
                    let isAdmin = chat.currentUserParticipant?.role?.lowercased() == "admin"

                    if !isGroup && !isChannel {
                        // Direct chat: show delete for me + delete for everyone
                        ConfirmationModal.deleteChat(
                            chatName: getChatName(chat),
                            onDelete: {
                                // DELETE .../conversations/{id}?scope=me
                                handleDeleteChat(chat: chat, forEveryone: false)
                                actionsHandler.hideConfirmation()
                            },
                            onDeleteForEveryone: {
                                actionsHandler.hideConfirmation()
                                // Confirm → DELETE .../conversations/{id}?scope=everyone
                                actionsHandler.showDeleteForEveryone(for: chat)
                            },
                            onDismiss: { actionsHandler.hideConfirmation() }
                        )
                    } else {
                        ConfirmationModal.deleteChat(
                            chatName: getChatName(chat),
                            isGroup: isGroup,
                            isChannel: isChannel,
                            isCurrentUserAdmin: isAdmin,
                            onDelete: {
                                handleDeleteChat(chat: chat, forEveryone: false)
                                actionsHandler.hideConfirmation()
                            },
                            onDismiss: { actionsHandler.hideConfirmation() }
                        )
                    }
                case .label:
                    LabelChatModal(
                        chatName: getChatName(chat),
                        currentLabel: viewModel.getChatLabel(chatId: chat.id ?? ""),
                        currentColor: viewModel.getChatLabelColor(chatId: chat.id ?? ""),
                        onDone: { label, color in
                            handleLabelChat(chat: chat, label: label, color: color)
                            actionsHandler.hideConfirmation()
                        },
                        onDismiss: { actionsHandler.hideConfirmation() }
                    )
                }
            }
        }
        .applyRTLEnvironment()
    }

    private func getChatName(_ chat: ChatMessageRow) -> String {
        if chat.isGroup {
            return chat.title ?? ChatStrings.chat_groupChat.localizedString()
        } else {
            let userDetails = chat.getUserDetails()
            return userDetails?.fullName ?? userDetails?.userName ?? "User"
        }
    }

    private func handleMuteChat(chat: ChatMessageRow) {
        viewModel.muteChat(id: chat.id ?? "")
    }

    private func handleUnmuteChat(chat: ChatMessageRow) {
        viewModel.unmuteChat(id: chat.id ?? "")
    }

    private func handleBlockChat(chat: ChatMessageRow) {
        viewModel.blockChat(chatId: chat.id ?? "")
    }

    private func handleUnblockChat(chat: ChatMessageRow) {
        viewModel.unblockChat(chatId: chat.id ?? "")
    }

    private func handleLabelChat(chat: ChatMessageRow, label: String, color: String?) {
        viewModel.setChatLabel(chatId: chat.id ?? "", label: label, color: color)
    }

    private func handleDeleteChat(chat: ChatMessageRow, forEveryone: Bool = false) {
        viewModel.deleteConversation(conversationId: chat.id ?? "", forEveryone: forEveryone)
    }
}
