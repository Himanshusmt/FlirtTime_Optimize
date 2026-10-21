//
//  ActiveUsersView.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI
import UIKit

struct ActiveUsersView: View {
    let users: [ChatMessageRow]
    let onUserTap: (ChatMessageRow) -> Void
    let onlineUserIds: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ChatStrings.chat_activeUsers.localizedString())
                    .font(.chatMedium(size: 16))
                Spacer()
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(uniqueActiveChatUsers.prefix(24), id: \.id) { user in
                        Button(action: {
                            onUserTap(user)
                        }) {
                            VStack(spacing: 4) {
                                ZStack(alignment: .bottomTrailing) {
                                    let userDetails = user.getUserDetails()
                                    UserAvatarView(
                                        urlString: userDetails?.profilePicture,
                                        isGroup: false,
                                        groupTitle: nil,
                                        groupParticipants: nil,
                                        userDetails: userDetails
                                    )

                                    // Online indicator
                                    Circle()
                                        .fill(kGreen)
                                        .frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(kWhite, lineWidth: 2))
                                        .offset(x: 4, y: -4)
                                }

                                let userDetails = user.getUserDetails()
                                Text(userDetails?.fullName ?? userDetails?.userName ?? user.title ?? "-")
                                    .font(.chatMedium(size: 12))
                                    .lineLimit(1)
                                    .frame(width: 60)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .animation(.default, value: uniqueActiveChatUsers.map { $0.id ?? "" })
            }
            .frame(height: 82)
        }
        .applyRTLEnvironment()
    }
    
    private var uniqueActiveChatUsers: [ChatMessageRow] {
        let uniqueUsers = users.reduce(into: [String: ChatMessageRow]()) { result, chatRow in
            if let userDetails = chatRow.getUserDetails(), let userId = userDetails.userId {
                result[userId] = chatRow
            }
        }

        // Filter for users that are online based on onlineUserIds, then sort alphabetically
        return Array(uniqueUsers.values).filter { chat in
            if chat.settings?.isBlocked == true { return false }
            if let userDetails = chat.getUserDetails(),
               let userId = userDetails.userId {
                if BlockedUsersManager.shared.isBlocked(id: userId) { return false }
                return onlineUserIds.contains(userId)
            }
            return false
        }.sorted { chat1, chat2 in
            let name1 = chat1.getUserDetails()?.fullName ?? chat1.getUserDetails()?.userName ?? chat1.title ?? ""
            let name2 = chat2.getUserDetails()?.fullName ?? chat2.getUserDetails()?.userName ?? chat2.title ?? ""
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
    }
}

// MARK: - Quick Moments strip (Design C)

enum ChatQuickMomentItem: Identifiable {
    case add
    case mine(QuickMomentTrayItem)
    case other(QuickMomentTrayItem)

    var id: String {
        switch self {
        case .add: return "add"
        case .mine(let item): return "mine-\(item.user?.id ?? "me")"
        case .other(let item): return "user-\(item.user?.id ?? item.latestAt ?? item.previewUrl ?? "unknown")"
        }
    }
}

struct ChatAddQuickMomentBubble: UIViewRepresentable {
    var avatarPath: String?

    func makeUIView(context: Context) -> QuickMomentAddBubbleView {
        let view = QuickMomentAddBubbleView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.configure(avatarPath: avatarPath)
        return view
    }

    func updateUIView(_ uiView: QuickMomentAddBubbleView, context: Context) {
        uiView.configure(avatarPath: avatarPath)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: QuickMomentAddBubbleView, context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }
}

struct ChatQuickMomentStatusRing: UIViewRepresentable {
    var segmentViewed: [Bool]
    var lineWidth: CGFloat = 3

    func makeUIView(context: Context) -> QuickMomentStatusRingView {
        let ring = QuickMomentStatusRingView()
        ring.backgroundColor = .clear
        ring.isUserInteractionEnabled = false
        ring.lineWidth = lineWidth
        ring.configure(segmentViewed: segmentViewed)
        return ring
    }

    func updateUIView(_ uiView: QuickMomentStatusRingView, context: Context) {
        uiView.lineWidth = lineWidth
        uiView.configure(segmentViewed: segmentViewed)
    }
}

struct ChatQuickMomentsStrip: View {
    let tray: QuickMomentTray?
    var ownPhotoURL: String?
    var onlineUserIds: Set<String> = []
    var onAdd: () -> Void
    var onOpen: (QuickMomentTrayItem, Bool) -> Void

    private let bubbleSize: CGFloat = 70
    private let avatarSize: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ChatStrings.chat_quickMoments.localizedString())
                .font(.chatMedium(size: 14))
                .foregroundColor(Color.chatTextPrimary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { item in
                        momentCell(item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .applyRTLEnvironment()
    }

    private var items: [ChatQuickMomentItem] {
        var result: [ChatQuickMomentItem] = [.add]
        if let me = tray?.me, me.hasActive {
            result.append(.mine(me))
        }
        for user in tray?.users ?? [] where user.hasActive {
            result.append(.other(user))
        }
        return result
    }

    @ViewBuilder
    private func momentCell(_ item: ChatQuickMomentItem) -> some View {
        switch item {
        case .add:
            Button(action: onAdd) {
                ChatAddQuickMomentBubble(avatarPath: ownPhotoURL ?? tray?.me?.user?.photo)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a moment")
        case .mine(let trayItem):
            Button { onOpen(trayItem, true) } label: {
                statusBubble(
                    photoURL: trayItem.user?.photo ?? ownPhotoURL,
                    title: timeLabel(for: trayItem),
                    segments: trayItem.statusRingSegmentViewed(isMine: true),
                    titleColor: Color(uiColor: AppColor.DoveGray),
                    isOnline: false
                )
            }
            .buttonStyle(.plain)
        case .other(let trayItem):
            let userId = trayItem.user?.id ?? ""
            let unread = trayItem.statusRingSegmentViewed(isMine: false).contains(false)
            Button { onOpen(trayItem, false) } label: {
                statusBubble(
                    photoURL: trayItem.user?.photo ?? trayItem.previewUrl,
                    title: displayName(for: trayItem),
                    segments: trayItem.statusRingSegmentViewed(isMine: false),
                    titleColor: unread ? Color.chatPrimary : Color(uiColor: AppColor.DoveGray),
                    isOnline: !userId.isEmpty && onlineUserIds.contains(userId)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func statusBubble(
        photoURL: String?,
        title: String,
        segments: [Bool],
        titleColor: Color,
        isOnline: Bool
    ) -> some View {
        VStack(spacing: 8) {
            ZStack {
                ChatQuickMomentStatusRing(segmentViewed: segments, lineWidth: 3)
                    .frame(width: bubbleSize, height: bubbleSize)

                CachedProfileImage(
                    userId: photoURL ?? title,
                    urlString: photoURL,
                    size: avatarSize,
                    isGroup: false,
                    fallbackName: title
                )

                if isOnline {
                    Circle()
                        .fill(kGreen)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 24, y: 24)
                }
            }
            .frame(width: bubbleSize, height: bubbleSize)

            Text(title)
                .font(.chatMedium(size: 12))
                .foregroundColor(titleColor)
                .lineLimit(1)
                .frame(width: bubbleSize + 4)
        }
    }

    private func timeLabel(for item: QuickMomentTrayItem) -> String {
        if let text = item.timeText, !text.isEmpty { return text }
        let createdAt = item.stories.first?.createdAt ?? item.latestAt
        let ago = MomentsDate.timeAgo(from: createdAt)
        return ago.isEmpty ? "now" : ago
    }

    private func displayName(for item: QuickMomentTrayItem) -> String {
        let fullName = item.user?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fullName.isEmpty { return fullName }
        let name = item.user?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "—" : name
    }
}
