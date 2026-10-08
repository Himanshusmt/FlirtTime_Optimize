//
//  ChatRowView.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

struct ChatRowView: View {
    let chat: ChatMessageRow
    let isMultiSelectMode: Bool
    let isSelected: Bool
    let isMuted: Bool
    let isArchived: Bool
    let isMarkedUnread: Bool
    let isTyping: Bool
    let isPending: Bool
    let isOnline: Bool
    let showMuteAction: Bool
    let draftText: String?
    let hasOngoingGroupCall: Bool
    let ongoingGroupCallIsVideo: Bool
    let onSelect: () -> Void
    let onLongPress: () -> Void
    let onTap: () -> Void
    let onMute: () -> Void
    let onUnMute: () -> Void
    let onRead: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    init(chat: ChatMessageRow,
         isMultiSelectMode: Bool,
         isSelected: Bool,
         isMuted: Bool,
         isArchived: Bool,
         isMarkedUnread: Bool = false,
         isTyping: Bool = false,
         isPending: Bool = false,
         isOnline: Bool = false,
         showMuteAction: Bool = true,
         draftText: String? = nil,
         hasOngoingGroupCall: Bool = false,
         ongoingGroupCallIsVideo: Bool = false,
         onSelect: @escaping () -> Void,
         onLongPress: @escaping () -> Void,
         onTap: @escaping () -> Void,
         onMute: @escaping () -> Void,
         onUnMute: @escaping () -> Void,
         onRead: @escaping () -> Void,
         onArchive: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.chat = chat
        self.isMultiSelectMode = isMultiSelectMode
        self.isSelected = isSelected
        self.isMuted = isMuted
        self.isArchived = isArchived
        self.isMarkedUnread = isMarkedUnread
        self.isTyping = isTyping
        self.isPending = isPending
        self.isOnline = isOnline
        self.showMuteAction = showMuteAction
        self.draftText = draftText
        self.hasOngoingGroupCall = hasOngoingGroupCall
        self.ongoingGroupCallIsVideo = ongoingGroupCallIsVideo
        self.onSelect = onSelect
        self.onLongPress = onLongPress
        self.onTap = onTap
        self.onMute = onMute
        self.onUnMute = onUnMute
        self.onRead = onRead
        self.onArchive = onArchive
        self.onDelete = onDelete
    }
    
    var body: some View {
        ChatRowSelectableView(
            chat: chat,
            isMultiSelectMode: isMultiSelectMode,
            isSelected: isSelected,
            isMuted: isMuted,
            isMarkedUnread: isMarkedUnread,
            isTyping: isTyping,
            isPending: isPending,
            isOnline: isOnline,
            draftText: draftText,
            hasOngoingGroupCall: hasOngoingGroupCall,
            ongoingGroupCallIsVideo: ongoingGroupCallIsVideo,
            onSelect: onSelect,
            onLongPress: onLongPress,
            onTap: onTap,
            onArchive: onArchive,
            onDelete: onDelete
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .if(!isMultiSelectMode) { view in
            view
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    trailingSwipeActions
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    leadingSwipeActions
                }
        }
        .applyRTLEnvironment()
    }
    
    @ViewBuilder
    private var trailingSwipeActions: some View {
        Button {
            onDelete()
        } label: {
            SwiftUI.Image(ChatAssets.delete)
        }
        .tint(.clear)
        
        Button {
            onArchive()
        } label: {
            SwiftUI.Image(isArchived ? ChatAssets.archive : ChatAssets.archive)
        }
        .tint(.clear)
    }
    
    @ViewBuilder
    private var leadingSwipeActions: some View {
        // Toggle between Mark as Read and Mark as Unread
        Button {
            onRead()
        } label: {
            // Show appropriate icon based on current state
            if (chat.unreadCount ?? 0) > 0 || isMarkedUnread {
                SwiftUI.Image(ChatAssets.unread)  // Mark as Read
            } else {
                SwiftUI.Image(ChatAssets.unread)  // Mark as Unread
            }
        }
        .tint(.clear)

        if showMuteAction {
            Button {
                if isMuted {
                    onUnMute()
                } else {
                    onMute()
                }
            } label: {
                SwiftUI.Image(isMuted ? ChatAssets.unmute : ChatAssets.mute)
            }
            .tint(.clear)
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
