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

// MARK: - Call History UI

struct CallHistoryItem: Identifiable, Equatable {
    enum Direction: Equatable { case incoming, outgoing, missed }
    enum Media: Equatable { case audio, video }

    let id: String
    let conversationId: String
    let peerId: String
    let name: String
    let avatarURL: String?
    let initials: String
    let direction: Direction
    let media: Media
    let isGroup: Bool
    let time: String
    let duration: String?

    init(call: AgoraCallDto, currentUserId: String) {
        id = call.id
        conversationId = call.conversationId
        isGroup = call.resolvedIsGroup
        media = call.type == .video ? .video : .audio

        let meId = currentUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiDirection = (call.direction ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isOutgoing = apiDirection == "outgoing" || (!meId.isEmpty && call.callerId == meId)
        let peer = call.peer(relativeTo: meId)
        peerId = {
            if let peer, !peer.id.isEmpty { return peer.id }
            if isOutgoing { return call.calleeId }
            return call.callerId
        }()
        name = call.displayTitle(relativeTo: meId)
        avatarURL = peer?.profilePicture
        initials = CallHistoryItem.initials(from: name)

        if apiDirection == "missed" || call.status == .missed {
            direction = .missed
        } else if !isOutgoing, call.status == .declined || call.status == .rejected || call.status == .busy {
            direction = .missed
        } else if apiDirection == "incoming" {
            direction = .incoming
        } else {
            direction = isOutgoing ? .outgoing : .incoming
        }

        let timestamp = call.startedAt ?? call.createdAt ?? call.endedAt
        time = CallHistoryItem.relativeTime(from: timestamp)
        duration = CallHistoryItem.durationLabel(call: call)
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }

    private static func relativeTime(from raw: String?) -> String {
        guard let date = parseDate(raw) else { return "" }
        return date.timeAgoDisplay()
    }

    private static func durationLabel(call: AgoraCallDto) -> String? {
        if let seconds = call.duration, seconds > 0 {
            return formatDuration(seconds)
        }
        if let start = parseDate(call.startedAt), let end = parseDate(call.endedAt) {
            let seconds = end.timeIntervalSince(start)
            guard seconds > 0 else { return nil }
            return formatDuration(seconds)
        }
        return nil
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let minutes = total / 60
        let remainder = total % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return String(format: "%d:%02d:%02d", hours, mins, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return fallback.date(from: raw)
    }
}

struct ChatCallsListView: View {
    @ObservedObject var viewModel: ChatListViewModel
    var searchText: String = ""
    var onStartCall: ((CallHistoryItem) -> Void)?

    var body: some View {
        let rows = filteredCalls
        if viewModel.isLoadingCallHistory && rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
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
                    .onAppear {
                        viewModel.loadMoreCallHistoryIfNeeded(currentItem: call)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteCallHistoryItem(id: call.id)
                        } label: {
                            Label(ChatStrings.delete.localizedString(), systemImage: "trash")
                        }
                    }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 0)
            .refreshable {
                viewModel.refreshCallHistory()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 80)
            }
        }
    }

    private var filteredCalls: [CallHistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.callHistory }
        return viewModel.callHistory.filter { $0.name.lowercased().contains(query) }
    }

    private func callRow(_ call: CallHistoryItem) -> some View {
        HStack(spacing: 14) {
            CachedProfileImage(
                userId: call.peerId.isEmpty ? call.id : call.peerId,
                urlString: call.avatarURL,
                size: 54,
                isGroup: call.isGroup,
                fallbackName: call.name
            )

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
                Button {
                    if let onStartCall {
                        onStartCall(call)
                    } else {
                        viewModel.startCall(from: call)
                    }
                } label: {
                    SwiftUI.Image(systemName: call.media == .video ? "video.fill" : "phone.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.chatPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private func directionIcon(_ call: CallHistoryItem) -> String {
        switch call.direction {
        case .incoming: return "arrow.down.left"
        case .outgoing: return "arrow.up.right"
        case .missed: return "phone.down.fill"
        }
    }

    private func subtitle(_ call: CallHistoryItem) -> String {
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

/// Chats / Archived filter shown below Quick Moments.
/// Archived stays hidden until at least one conversation is archived.
struct ChatTabsView: View {
    @Binding var selectedTab: ChatTab
    var showsArchived: Bool = false

    private var tabs: [ChatTab] {
        showsArchived ? [.allChats, .archived] : [.allChats]
    }

    var body: some View {
        HStack(spacing: 20) {
            ForEach(tabs) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.localizedTitle)
                        .font(isSelected ? .chatBold(size: 16) : .chatMedium(size: 16))
                        .foregroundColor(isSelected ? kTextBlack : Color.chatTextTertiary)
                        .overlay(alignment: .bottom) {
                            if isSelected {
                                Capsule()
                                    .fill(Color.chatPrimary)
                                    .frame(height: 2)
                                    .offset(y: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .applyRTLEnvironment()
    }
}
