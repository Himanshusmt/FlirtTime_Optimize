//
//  ChatTabsView.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

enum ChatTab: String, CaseIterable, Identifiable {
    case allChats = "All Chats"
    case groups = "Groups"
//    case calls = "Calls"
    case channel = "Channel"
    case archived = "Archived"
    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .allChats: return ChatStrings.chat_chats.localizedString()
        case .groups:   return ChatStrings.chat_groups.localizedString()
        case .channel:  return ChatStrings.chat_channels.localizedString()
        case .archived: return ChatStrings.chat_archived.localizedString()
        }
    }

    var iconName: String {
        switch self {
        case .allChats: return "text.bubble"
        case .groups:   return "person.2"
        case .channel:  return "megaphone"
        case .archived: return "archivebox"
        }
    }

    static var visibleTabs: [ChatTab] {
        allCases.filter { $0 != .groups && $0 != .channel }
    }
}

struct ChatTabsView: View {
    @Binding var selectedTab: ChatTab
    var body: some View {
        HStack(spacing: 12) {
            ForEach(ChatTab.visibleTabs) { tab in
                let isSelected = selectedTab == tab
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 6) {
                        SwiftUI.Image(systemName: tab.iconName)
                            .font(.chat(.medium, size: 14))
                        Text(tab.localizedTitle)
                            .font(.chatMedium(size: 13))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(isSelected ? kAccent : Color.chatTextSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 50)
                            .strokeBorder(isSelected ? kAccent : Color.chatSeparator, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal)
        .applyRTLEnvironment()
    }
}
