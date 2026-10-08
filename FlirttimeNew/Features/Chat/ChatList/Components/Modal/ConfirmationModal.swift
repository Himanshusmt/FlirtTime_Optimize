//
//  ConfirmationModal.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

struct ConfirmationModal: View {
    let title: String
    let description: String
    let imageName: String
    let actionButtonTitle: String
    let onAction: () -> Void
    let onDismiss: () -> Void

    var secondActionButtonTitle: String? = nil
    var onSecondAction: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        onDismiss()
                    }

                VStack {
                    Spacer()

                    VStack(spacing: 0) {

                        VStack(spacing: 12) {
                            SwiftUI.Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .padding(.top, 20)

                            Text(title)
                                .font(.chatBold(size: 20))
                                .foregroundColor(Color.chatTextPrimary)
                                .multilineTextAlignment(.center)

                            Text(description)
                                .font(.chatRegular(size: 13))
                                .foregroundColor(Color.chatTextSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .padding(.horizontal, 36)
                                .padding(.bottom, 16)

                            Button(action: onAction) {
                                ZStack {
                                    Capsule()
                                        .fill(LinearGradient(colors: [.chatPrimary, .chatPrimaryDark], startPoint: .leading, endPoint: .trailing))
                                        .frame(maxWidth: .infinity)

                                    Text(actionButtonTitle)
                                        .font(.chatSemiBold(size: 16))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .padding(.horizontal, 36)

                            if let secondTitle = secondActionButtonTitle, let secondAction = onSecondAction {
                                Button(action: secondAction) {
                                    Text(secondTitle)
                                        .font(.chatSemiBold(size: 16))
                                        .foregroundColor(Color.chatPrimary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(Color.chatPrimary.opacity(0.08))
                                        .cornerRadius(25)
                                }
                                .padding(.horizontal, 36)
                                .padding(.top, 8)
                            }

                            Spacer()
                                .frame(height: 24 + geometry.safeAreaInsets.bottom)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(24, corners: [.topLeft, .topRight])
                    .overlay(alignment: .topTrailing) {
                        Button(action: onDismiss) {
                            SwiftUI.Image(systemName: "xmark")
                                .font(.chat(.bold, size: 16))
                                .foregroundColor(Color.chatTextPrimary)
                                .frame(width: 36, height: 36)
                                .background(Color.chatSurfaceAlt)
                                .clipShape(Circle())
                        }
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                    }
                }
                .ignoresSafeArea(.all, edges: .all)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: true)
        .applyRTLEnvironment()
    }
}

// MARK: - Convenience Initializers
extension ConfirmationModal {
    static func archiveChat(
        chatName: String,
        onArchive: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_archive.localizedString() + "?",
            description: ChatStrings.chat_archiveDescription.localizedString(),
            imageName: ChatAssets.archive,
            actionButtonTitle: ChatStrings.chat_archive.localizedString(),
            onAction: onArchive,
            onDismiss: onDismiss
        )
    }

    static func deleteChat(
        chatName: String,
        isGroup: Bool = false,
        isChannel: Bool = false,
        isCurrentUserAdmin: Bool = false,
        onDelete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        let title: String
        let description: String
        let buttonTitle: String

        if isChannel {
            title = ChatStrings.chat_deleteChannelConfirmation.localizedString()
            if isCurrentUserAdmin {
                description = String(format: ChatStrings.chat_exitAndDeleteChannelDescription.localizedString(), chatName)
                buttonTitle = ChatStrings.chat_exitAndDeleteChannel.localizedString()
            } else {
                description = String(format: ChatStrings.chat_deleteChannelDescription.localizedString(), chatName)
                buttonTitle = ChatStrings.chat_deleteChannel.localizedString()
            }
        } else if isGroup {
            title = ChatStrings.chat_deleteGroupConfirmation.localizedString()
            if isCurrentUserAdmin {
                description = String(format: ChatStrings.chat_exitAndDeleteGroupDescription.localizedString(), chatName)
                buttonTitle = ChatStrings.chat_exitAndDeleteGroup.localizedString()
            } else {
                description = String(format: ChatStrings.chat_deleteGroupDescription.localizedString(), chatName)
                buttonTitle = ChatStrings.chat_deleteGroup.localizedString()
            }
        } else {
            title = ChatStrings.chat_deleteChatConfirmation.localizedString()
            description = String(format: ChatStrings.chat_deleteChatDescription.localizedString(), chatName)
            buttonTitle = ChatStrings.chat_deleteChat.localizedString()
        }

        return ConfirmationModal(
            title: title,
            description: description,
            imageName: ChatAssets.delete,
            actionButtonTitle: buttonTitle,
            onAction: onDelete,
            onDismiss: onDismiss
        )
    }

    static func deleteChat(
        chatName: String,
        onDelete: @escaping () -> Void,
        onDeleteForEveryone: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_deleteChatConfirmation.localizedString(),
            description: String(format: ChatStrings.chat_deleteChatDescription.localizedString(), chatName),
            imageName: ChatAssets.delete,
            actionButtonTitle: ChatStrings.chat_deleteChat.localizedString(),
            onAction: onDelete,
            onDismiss: onDismiss,
            secondActionButtonTitle: String(format: ChatStrings.chat_deleteForMeAndUser.localizedString(), chatName),
            onSecondAction: onDeleteForEveryone
        )
    }

    static func deleteChatForEveryone(
        userName: String,
        onDelete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_deleteForEveryoneConfirmation.localizedString(),
            description: ChatStrings.chat_deleteForEveryoneDescription.localizedString(),
            imageName: ChatAssets.delete,
            actionButtonTitle: ChatStrings.chat_deleteForEveryone.localizedString(),
            onAction: onDelete,
            onDismiss: onDismiss
        )
    }

    static func blockUser(
        userName: String,
        onBlock: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_blockUserConfirmation.localizedString(),
            description: String(format: ChatStrings.chat_blockUserDescription.localizedString(), userName),
            imageName: ChatAssets.block,
            actionButtonTitle: ChatStrings.chat_block.localizedString(),
            onAction: onBlock,
            onDismiss: onDismiss
        )
    }

    static func unblockUser(
        userName: String,
        onUnblock: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_unblockUserConfirmation.localizedString(),
            description: String(format: ChatStrings.chat_unblockUserDescription.localizedString(), userName),
            imageName: ChatAssets.block,
            actionButtonTitle: ChatStrings.chat_unblock.localizedString(),
            onAction: onUnblock,
            onDismiss: onDismiss
        )
    }

    static func muteChat(
        chatName: String,
        onMute: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_muteConfirmation.localizedString(),
            description: ChatStrings.chat_muteDescription.localizedString(),
            imageName: ChatAssets.mute,
            actionButtonTitle: ChatStrings.chat_mute.localizedString(),
            onAction: onMute,
            onDismiss: onDismiss
        )
    }

    static func unmuteChat(
        chatName: String,
        onUnmute: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_unmuteConfirmation.localizedString(),
            description: String(format: ChatStrings.chat_unmuteDescription.localizedString(), chatName),
            imageName: ChatAssets.unmute,
            actionButtonTitle: ChatStrings.chat_unmute.localizedString(),
            onAction: onUnmute,
            onDismiss: onDismiss
        )
    }

    static func reportChat(
        chatName: String,
        onReport: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_reportConfirmation.localizedString(),
            description: String(format: ChatStrings.chat_reportDescription.localizedString(), chatName),
            imageName: ChatAssets.report,
            actionButtonTitle: ChatStrings.chat_report.localizedString(),
            onAction: onReport,
            onDismiss: onDismiss
        )
    }

    static func leaveGroup(
        groupName: String,
        onLeave: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_leaveGroupConfirmation.localizedString(),
            description: String(format: ChatStrings.chat_leaveGroupDescription.localizedString(), groupName),
            imageName: ChatAssets.leave,
            actionButtonTitle: ChatStrings.chat_leaveGroup.localizedString(),
            onAction: onLeave,
            onDismiss: onDismiss
        )
    }

    static func deleteMessage(
        onDelete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_deleteMessageConfirmation.localizedString(),
            description: ChatStrings.chat_deleteMessageDescription.localizedString(),
            imageName: ChatAssets.delete,
            actionButtonTitle: ChatStrings.chat_deleteForMe.localizedString(),
            onAction: onDelete,
            onDismiss: onDismiss
        )
    }

    static func clearChat(
        chatName: String,
        onClear: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> ConfirmationModal {
        ConfirmationModal(
            title: ChatStrings.chat_clearChatConfirmation.localizedString(),
            description: String(format: ChatStrings.chat_clearChatDescription.localizedString(), chatName),
            imageName: ChatAssets.clearChat,
            actionButtonTitle: ChatStrings.chat_clearChatAction.localizedString(),
            onAction: onClear,
            onDismiss: onDismiss
        )
    }
}
