//
//  MultiSelectActionBar.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

enum MultiSelectAction: Hashable {
    case markUnread, markAsRead, archive, label, mute, unmute, lock, block, unblock, pin, delete, deleteForEveryone, unpin, selectAll, deselectAll
}

struct MultiSelectActionBar: View {
    let selectedCount: Int
    let totalChatsCount: Int
    let hasPinnedChats: Bool
    let canPinMoreChats: Bool
    let hasBlockedChats: Bool
    let hasUnreadChats: Bool
    let hasMutedChats: Bool
    let hasUnmutedChats: Bool
    let hasGroupChatsSelected: Bool
    let isSingleDirectChatSelected: Bool
    var onCancel: () -> Void
    var onAction: (MultiSelectAction) -> Void

    private var isAllSelected: Bool {
        selectedCount == totalChatsCount && totalChatsCount > 0
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Button(ChatStrings.done.localizedString(), action: onCancel)
                    .font(.chatSemiBold(size: 16))
                    .foregroundColor(Color.chatTextPrimary)
                Text("\(selectedCount) \(ChatStrings.chat_selected.localizedString())")
                    .font(.chatBold(size: 26))
                    .foregroundColor(Color.chatTextPrimary)
                    .transaction { $0.animation = nil }
                    .animation(nil, value: selectedCount)
            }

            Spacer()

            // Select All / Deselect All text (tap to toggle)
            Text(isAllSelected
                ? ChatStrings.chat_deselectAll.localizedString()
                : ChatStrings.select_all.localizedString())
                .font(.chatSemiBold(size: 14))
                .foregroundColor(Color.chatTextPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
//                .background(Color.chatSurface)
//                .clipShape(Capsule())
                .contentShape(Rectangle())
                .onTapGesture {
                    if isAllSelected {
                        onAction(.deselectAll)
                    } else {
                        onAction(.selectAll)
                    }
                }

            Spacer().frame(width: 12)

            Menu {
                ForEach(menuActions, id: \.self) { action in
                    if action == .delete || action == .deleteForEveryone || action == .block {
                        Button(role: .destructive) { onAction(action) } label: {
                            actionLabel(for: action)
                        }
                    } else {
                        Button { onAction(action) } label: {
                            actionLabel(for: action)
                        }
                    }
                }
            } label: {
                SwiftUI.Image(ChatAssets.menu)
                    .opacity(selectedCount == 0 ? 0.4 : 1.0)
            }
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.white)
        .applyRTLEnvironment()
    }

    private var menuActions: [MultiSelectAction] {
        var actions: [MultiSelectAction] = []

        if hasUnreadChats {
            actions.append(.markAsRead)
        } else {
            actions.append(.markUnread)
        }

        if hasUnmutedChats {
            actions.append(.mute)
        } else {
            actions.append(.unmute)
        }

        actions.append(.archive)

        if hasPinnedChats {
            actions.append(.unpin)
        } else if canPinMoreChats {
            actions.append(.pin)
        }
        // else: pinning would exceed limit — show neither pin nor unpin

        if hasGroupChatsSelected {
            if selectedCount == 1 { actions.append(.label) }
            actions.append(.delete)
        } else if hasBlockedChats {
            if selectedCount == 1 { actions.append(.label) }
            actions.append(contentsOf: [.unblock, .delete])
            if isSingleDirectChatSelected { actions.append(.deleteForEveryone) }
        } else {
            if selectedCount == 1 { actions.append(.label) }
            actions.append(contentsOf: [.block, .delete])
            if isSingleDirectChatSelected { actions.append(.deleteForEveryone) }
        }

        return actions
    }
    
    @ViewBuilder
    private func actionLabel(for action: MultiSelectAction) -> some View {
        switch action {
        case .selectAll:
            Label(ChatStrings.select_all.localizedString(), systemImage: "checkmark.circle.fill")
        case .deselectAll:
            Label(ChatStrings.chat_deselectAll.localizedString(), systemImage: "circle")
        case .markUnread:
            Label(ChatStrings.chat_markAsUnread.localizedString(), image: ChatAssets.unread)
        case .markAsRead:
            Label(ChatStrings.chat_markAsRead.localizedString(), image: ChatAssets.read)
        case .archive:
            Label(ChatStrings.chat_archive.localizedString(), image: ChatAssets.archive)
        case .mute:
            Label(ChatStrings.chat_mute.localizedString(), image: ChatAssets.mute)
        case .unmute:
            Label(ChatStrings.chat_unmute.localizedString(), systemImage: "speaker")
        case .pin:
            Label(ChatStrings.chat_pin.localizedString(), image: ChatAssets.pin)
        case .block:
            Label(ChatStrings.chat_block.localizedString(), image: ChatAssets.block)
        case .unblock:
            Label(ChatStrings.chat_unblock.localizedString(), systemImage: "person.crop.circle.badge.checkmark")
        case .delete:
            Label(ChatStrings.chat_deleteChat.localizedString(), image: ChatAssets.delete)
        case .deleteForEveryone:
            Label(ChatStrings.chat_deleteForEveryone.localizedString(), image: ChatAssets.delete)
        case .label:
            Label(ChatStrings.chat_labelChat.localizedString(), image: ChatAssets.tag)
        case .lock:
            Label(ChatStrings.chat_lockChat.localizedString(), systemImage: "lock")
        case .unpin:
            Label(ChatStrings.chat_unpin.localizedString(), image: ChatAssets.unpin)
        }
    }
}
