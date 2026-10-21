//
//  ChatTabsView.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

enum ChatInboxSection: String, CaseIterable, Identifiable {
    case chats
    case calls

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .chats: return ChatStrings.chat_chats.localizedString()
        case .calls: return ChatStrings.chat_calls.localizedString()
        }
    }

    var iconName: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .calls: return "phone.fill"
        }
    }
}

struct ChatInboxSegmentedControl: View {
    @Binding var selectedSection: ChatInboxSection
    @Namespace private var segmentNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChatInboxSection.allCases) { section in
                let isSelected = selectedSection == section
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 6) {
                        SwiftUI.Image(systemName: section.iconName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(section.localizedTitle)
                            .font(.chatMedium(size: 15))
                            .lineLimit(1)
                    }
                    .foregroundColor(isSelected ? .white : Color.chatTextPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.chatPrimary)
                                .matchedGeometryEffect(id: "inbox-pill", in: segmentNamespace)
                                .shadow(color: Color.chatPrimary.opacity(0.35), radius: 8, x: 0, y: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white))
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Dummy Calls UI

struct DummyCallItem: Identifiable {
    enum Direction { case incoming, outgoing, missed }
    enum Media { case audio, video }

    let id: String
    let name: String
    let initials: String
    let direction: Direction
    let media: Media
    let time: String
    let duration: String?
}

struct ChatCallsDummyListView: View {
    var searchText: String = ""

    private let dummyCalls: [DummyCallItem] = [
        DummyCallItem(id: "1", name: "Riya", initials: "R", direction: .missed, media: .video, time: "2m ago", duration: nil),
        DummyCallItem(id: "2", name: "Maya", initials: "M", direction: .outgoing, media: .audio, time: "18m ago", duration: "4:12"),
        DummyCallItem(id: "3", name: "Priya", initials: "P", direction: .incoming, media: .video, time: "1h ago", duration: "12:08"),
        DummyCallItem(id: "4", name: "Meera", initials: "M", direction: .outgoing, media: .video, time: "Yesterday", duration: "1:45"),
        DummyCallItem(id: "5", name: "Tanya", initials: "T", direction: .missed, media: .audio, time: "Yesterday", duration: nil),
        DummyCallItem(id: "6", name: "Nisha", initials: "N", direction: .incoming, media: .audio, time: "Mon", duration: "8:33"),
        DummyCallItem(id: "7", name: "Sara", initials: "S", direction: .outgoing, media: .audio, time: "Sun", duration: "2:09")
    ]

    var body: some View {
        let rows = filteredCalls
        if rows.isEmpty {
            VStack(spacing: 12) {
                SwiftUI.Image(systemName: "phone")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(Color.chatTextTertiary)
                Text(ChatStrings.chat_noCallsYet.localizedString())
                    .font(.chatMedium(size: 16))
                    .foregroundColor(.chatTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(rows) { call in
                callRow(call)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 0)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 80)
            }
        }
    }

    private var filteredCalls: [DummyCallItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return dummyCalls }
        return dummyCalls.filter { $0.name.lowercased().contains(query) }
    }

    private func callRow(_ call: DummyCallItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.chatPrimarySoft)
                    .frame(width: 54, height: 54)
                Text(call.initials)
                    .font(.chatSemiBold(size: 18))
                    .foregroundColor(Color.chatPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(call.name)
                    .font(.chatSemiBold(size: 15))
                    .foregroundColor(call.direction == .missed ? Color.chatPrimary : Color.chatTextPrimary)

                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: directionIcon(call))
                        .font(.system(size: 11, weight: .semibold))
                    Text(subtitle(call))
                        .font(.chatRegular(size: 12))
                }
                .foregroundColor(call.direction == .missed ? Color.chatPrimary : Color.chatTextSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text(call.time)
                    .font(.chatRegular(size: 11))
                    .foregroundColor(Color.chatTextTertiary)
                SwiftUI.Image(systemName: call.media == .video ? "video.fill" : "phone.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.chatPrimary)
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 6)
    }

    private func directionIcon(_ call: DummyCallItem) -> String {
        switch call.direction {
        case .incoming: return "arrow.down.left"
        case .outgoing: return "arrow.up.right"
        case .missed: return "phone.down.fill"
        }
    }

    private func subtitle(_ call: DummyCallItem) -> String {
        let kind: String
        switch call.direction {
        case .incoming: kind = "Incoming"
        case .outgoing: kind = "Outgoing"
        case .missed: kind = "Missed"
        }
        let media = call.media == .video ? ChatStrings.chat_video.localizedString() : ChatStrings.chat_audio.localizedString()
        if let duration = call.duration {
            return "\(kind) \(media) · \(duration)"
        }
        return "\(kind) \(media)"
    }
}

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
