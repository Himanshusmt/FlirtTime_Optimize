//
//  ChatListContent.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

struct ChatListContent: View {
    let chats: [ChatMessageRow]
    let isMultiSelectMode: Bool
    let selectedChats: Set<String>
    let mutedChats: Set<String> // Add this line
    let onSelect: (String) -> Void
    let onLongPress: (String) -> Void
    let onTap: (ChatMessageRow) -> Void
    let onArchive: (ChatMessageRow) -> Void
    let onDelete: (ChatMessageRow) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(chats, id: \.id) { chat in
                    let chatId = chat.id ?? ""
                    let draft: String? = {
                        guard !chatId.isEmpty else { return nil }
                        let text = ConversationDraftStore.shared.load(conversationId: chatId)
                        guard let text, !text.isEmpty else { return nil }
                        return text
                    }()
                    let ongoing = chat.isGroup
                        ? AgoraCallService.shared.ongoingGroupCall(for: chatId)
                        : nil
                    ChatRowSelectableView(
                        chat: chat,
                        isMultiSelectMode: isMultiSelectMode,
                        isSelected: selectedChats.contains(chatId),
                        isMuted: mutedChats.contains(chatId),
                        draftText: draft,
                        hasOngoingGroupCall: ongoing != nil,
                        ongoingGroupCallIsVideo: ongoing?.type == .video,
                        onSelect: {
                            onSelect(chatId)
                        },
                        onLongPress: {
                            onLongPress(chatId)
                        },
                        onTap: {
                            onTap(chat)
                        },
                        onArchive: {
                            onArchive(chat)
                        },
                        onDelete: {
                            onDelete(chat)
                        }
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 8)
        }
        .applyRTLEnvironment()
    }
}
