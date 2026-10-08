//
//  ChatRowSelectableView.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

private struct SelectionCircle: View {
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            if isSelected {
                SwiftUI.Image(ChatAssets.selected)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            } else {
                Circle()
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
            }
        }
    }
}

private struct MessagePreview: View {
    let chat: ChatMessageRow
    var isUnread: Bool = false
    /// True when another participant is actively typing in this conversation.
    var isTyping: Bool = false
    /// True when the current user has sent a message that has not yet been acked by the server.
    var isPending: Bool = false
    /// Draft text passed from parent so SwiftUI detects changes and re-renders.
    var draftText: String?
    /// Live group call (from list API / rejoin registry) — same copy as Join banner.
    var hasOngoingGroupCall: Bool = false
    var ongoingGroupCallIsVideo: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let userDetails = chat.getUserDetails()
            HStack(spacing: 6) {
                Text(chat.isGroup
                     ? (chat.title ?? "--")
                     : displayName(for: chat, userDetails: userDetails))
                    .font(isUnread ? .chatBold(size: 14) : .chatSemiBold(size: 14))
                    .lineLimit(1)

                // Show Group badge for group chats
                if chat.isGroup {
                    Text(ChatStrings.chat_groupBadge.localizedString())
                        .font(.chatRegular(size: 10))
                        .foregroundColor(Color.chatTextPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.06))
                        .cornerRadius(6)
                }

                // Show label if it exists
                if let labelArr = chat.settings?.label, labelArr.count > 0, let label = labelArr.first as? String, label.isNotEmpty {
                    let backgroundHex = chat.settings?.labelColor?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedHex: String = {
                        guard let backgroundHex, !backgroundHex.isEmpty else {
                            return LabelChatModal.labelColors[0]
                        }
                        return backgroundHex.hasPrefix("#") ? backgroundHex : "#\(backgroundHex)"
                    }()
                    Text(label)
                        .font(.chatRegular(size: 10))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: resolvedHex))
                        .cornerRadius(8)
                } else if let labelText = chat.settings?.labelText?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                          !labelText.isEmpty {
                    let backgroundHex = chat.settings?.labelColor?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedHex: String = {
                        guard let backgroundHex, !backgroundHex.isEmpty else {
                            return LabelChatModal.labelColors[0]
                        }
                        return backgroundHex.hasPrefix("#") ? backgroundHex : "#\(backgroundHex)"
                    }()
                    Text(labelText)
                        .font(.chatRegular(size: 10))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: resolvedHex))
                        .cornerRadius(8)
                }

                // Show blocked indicator if chat is blocked
                if chat.settings?.isBlocked == true {
                    SwiftUI.Image(systemName: "slash.circle")
                        .foregroundColor(.red)
                        .font(.chat(size: 16))
                }
            }

            subtitleRow
        }
    }
    
    private var messageStatus: String {
        chat.lastMessage?.status?.lowercased() ?? ""
    }
    
    private var readReceiptImage: String {

        switch messageStatus {

        case "sent":
            return ChatAssets.tickSent

        case "delivered":
            return ChatAssets.tickDelivered

        case "seen", "read":
            return ChatAssets.tickRead

        default:
            return ChatAssets.tickSent
        }
    }
    
    
    
    private var shouldShowReadReceipt: Bool {
        // Requires a real senderId matching current user — avoids nil==nil
        // showing a single tick on empty / newly opened conversations.
        chat.isLastMessageFromSelf
    }

//    private var isMessageSeen: Bool {
//        let status = chat.lastMessage?.status?.lowercased() ?? ""
//        return status == "seen" || status == "read"
//    }
//
//    private var readReceiptColor: Color {
//        isMessageSeen ? .blue : .gray
//    }
    
    // MARK: - Subtitle row (typing / delivery tick + message preview)

    @ViewBuilder
    private var subtitleRow: some View {
        if chat.settings?.isBlocked == true {
               HStack(spacing: 3) {
                   Text(ChatStrings.chat_blockedUserHint.localizedString())
                       .font(.chatRegular(size: 12))
                       .foregroundColor(.red)
                       .lineLimit(1)
               }
               .transition(.opacity)
           }
       else if hasOngoingGroupCall {
            HStack(spacing: 4) {
                SwiftUI.Image(systemName: ongoingGroupCallIsVideo ? "video.fill" : "phone.fill")
                    .font(.chat(.semibold, size: 11))
                    .foregroundColor(Color(red: 0.13, green: 0.55, blue: 0.30))
                Text(ongoingGroupCallIsVideo ? "Group video call ongoing" : "Group call ongoing")
                    .font(.chatSemiBold(size: 12))
                    .foregroundColor(Color(red: 0.13, green: 0.55, blue: 0.30))
                    .lineLimit(1)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if isTyping {
            // show animated "typing…" in accent colour
            HStack(spacing: 3) {
                TypingDotsView()
                Text(ChatStrings.chat_typing.localizedString())
                    .font(.chatRegular(size: 12))
                    .foregroundColor(kAccent)
                    .lineLimit(1)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if let draft = draftText {
            HStack(spacing: 3) {
                Text(ChatStrings.chat_draft.localizedString())
                    .font(.chatSemiBold(size: 12))
                    .foregroundColor(kAccent)
                Text(draft)
                    .font(.chatRegular(size: 12))
                    .foregroundColor(kTextSecondary)
                    .lineLimit(1)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            HStack(spacing: 3) {
                if shouldShowReadReceipt {
                        SwiftUI.Image(readReceiptImage)
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .foregroundColor(.chatPrimary)
                    }

                Text(getMessagePreview(chat: chat))
                    .font(isUnread ? .chatBold(size: 12) : .chatRegular(size: 12))
                    .foregroundColor(isUnread ? .black : kTextSecondary)
                    .lineLimit(1)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func getMessagePreview(chat: ChatMessageRow) -> String {
        guard let lastMessage = chat.lastMessage else { return "" }

        let rawType = lastMessage.messageType?.lowercased() ?? ""
        let content = lastMessage.contentPreview?
            .htmlToString
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Text / system / unknown-empty → show the actual message text
        if rawType.isEmpty || rawType == "text" || rawType == "system" {
            return content
        }

        // Call log → "Audio call" / "Video call" (prefer server body when present)
        if rawType == "call" || rawType.contains("call") {
            return ConversationMessage.callPreviewText(
                content: lastMessage.contentPreview,
                messageType: rawType
            )
        }

        let typeName = ConversationMessage.messageTypeDisplayName(rawType)
        // Fallback: if type maps to generic "Message" but we have text, show the text
        if typeName.isEmpty
            || typeName == ChatStrings.chat_message.localizedString() {
            return content.isEmpty ? typeName : content
        }
        return typeName
    }

    private func displayName(for chat: ChatMessageRow, userDetails: (userId: String?, userName: String?, fullName: String?, profilePicture: String?)?) -> String {
        if let fullName = userDetails?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty {
            return fullName
        }

        if let userName = userDetails?.userName?.trimmingCharacters(in: .whitespacesAndNewlines), !userName.isEmpty {
            return userName
        }

        let title = chat.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty || isCurrentUserName(title, chat: chat) {
            return "--"
        }

        return title
    }

    private func isCurrentUserName(_ value: String, chat: ChatMessageRow) -> Bool {
        guard let current = chat.currentUserParticipant?.user?.userDetails?.first else { return false }
        let normalized = value.lowercased()
        let ownFull = current.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ownUser = current.userName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == ownFull || normalized == ownUser
    }
}

private struct TimeAndBadge: View {
    let chat: ChatMessageRow
    let isMuted: Bool
    var isMarkedUnread: Bool = false

    @State private var currentDate = Date()
    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let timestamp = chat.lastMessage?.createdAt,
               let date = iso8601Date(from: timestamp) {
                Text(timeAgoString(from: date, relativeTo: currentDate))
                    .font(.chatRegular(size: 10))
                    .foregroundColor(kGray)
            } else if let lastMessageAt = chat.lastMessageAt,
                     let date = iso8601Date(from: lastMessageAt) {
                Text(timeAgoString(from: date, relativeTo: currentDate))
                    .font(.chatRegular(size: 10))
                    .foregroundColor(kGray)
            }
            HStack(spacing: 4) {
                if isMuted {
                    SwiftUI.Image(ChatAssets.mute)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                UnreadBadge(count: chat.unreadCount ?? 0, isMarkedUnread: isMarkedUnread)
            }
        }
        .onReceive(refreshTimer) { newDate in
            currentDate = newDate
        }
    }
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func iso8601Date(from string: String) -> Date? {
        Self.isoFormatter.date(from: string)
    }

    private func timeAgoString(from date: Date, relativeTo baseDate: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: baseDate)
    }
}

struct ChatRowSelectableView: View {
    let chat: ChatMessageRow
    var isMultiSelectMode: Bool
    var isSelected: Bool
    var isMuted: Bool = false
    var isMarkedUnread: Bool = false
    /// True when another participant is actively typing in this conversation.
    var isTyping: Bool = false
    /// True when the current user has at least one unacked pending message in this conversation.
    var isPending: Bool = false
    /// True when the other participant (direct chat only) is currently online.
    var isOnline: Bool = false
    /// Draft text for this conversation, read by parent and passed down so SwiftUI tracks changes.
    var draftText: String? = nil
    var hasOngoingGroupCall: Bool = false
    var ongoingGroupCallIsVideo: Bool = false
    var onSelect: () -> Void
    var onLongPress: () -> Void
    var onTap: () -> Void
    var onArchive: (() -> Void)?
    var onDelete: (() -> Void)?
    var onMore: (() -> Void)?

    @ObservedObject private var iconCache = ConversationIconCache.shared

    /// Use the explicitly-passed draft text if available, otherwise fall back
    /// to reading from ConversationDraftStore for callers that don't pass it.
    private var effectiveDraftText: String? {
        if let draftText { return draftText }
        guard let id = chat.id, !id.isEmpty else { return nil }
        let text = ConversationDraftStore.shared.load(conversationId: id)
        guard let text, !text.isEmpty else { return nil }
        return text
    }
    
    var body: some View {
        mainContent
            .padding(8)
            .background(.white)
            .onTapGesture {
                if isMultiSelectMode {
                    onSelect()
                } else {
                    onTap()
                }
            }
            .onLongPressGesture {
                onLongPress()
            }
            .applyRTLEnvironment()
    }

    private var mainContent: some View {
        HStack(spacing: 16) {
            if isMultiSelectMode {
                Button(action: onSelect) {
                    SelectionCircle(isSelected: isSelected)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            UserAvatarView(
                urlString: (chat.isGroup || chat.type?.lowercased() == "channel") ? chat.avatar : chat.getUserDetails()?.profilePicture,
                isGroup: chat.isGroup || chat.type?.lowercased() == "channel",
                groupTitle: chat.title,
                groupParticipants: chat.participants,
                userDetails: chat.getUserDetails(),
                conversationId: chat.id,
                pendingIconImage: iconCache.image(forId: chat.id),
                verified: chat.otherParticipant?.resolvedIsVerified
                    ?? chat.otherParticipant?.userProfileData?.verified
                    ?? false,
                isOnline: isOnline
            )
            MessagePreview(
                chat: chat,
                isUnread: (chat.unreadCount ?? 0) > 0 || isMarkedUnread,
                isTyping: isTyping,
                isPending: isPending,
                draftText: effectiveDraftText,
                hasOngoingGroupCall: hasOngoingGroupCall,
                ongoingGroupCallIsVideo: ongoingGroupCallIsVideo
            )
            .animation(.easeInOut(duration: 0.2), value: isTyping)
            .animation(.easeInOut(duration: 0.2), value: hasOngoingGroupCall)
            Spacer()
            TimeAndBadge(chat: chat, isMuted: isMuted, isMarkedUnread: isMarkedUnread)
        }
    }
}




struct UserAvatarView: View {
    let urlString: String?
    let isGroup: Bool
    let groupTitle: String?
    let groupParticipants: [Participant]?
    let userDetails: (userId: String?, userName: String?, fullName: String?, profilePicture: String?)?
    var conversationId: String? = nil
    var pendingIconImage: UIImage? = nil
    var verified: Bool = false
    var isOnline: Bool = false

    var body: some View {
        avatarContent
            .overlay {
                if isOnline {
                    Circle()
                        .stroke(kGreen, lineWidth: 2)
                        .padding(-2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if verified {
                    SwiftUI.Image(ChatAssets.verified)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .offset(x: 1.5, y: 1.5)
                }
            }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if isGroup {
            let groupName = groupTitle ?? "Group"
            if let pending = pendingIconImage {
                SwiftUI.Image(uiImage: pending)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
            } else if let avatarUrl = urlString, !avatarUrl.isEmpty {
                let stableKey = conversationId.map { "group_\($0)" } ?? "group_\(abs(avatarUrl.hashValue))"
                CachedProfileImage(
                    userId: stableKey,
                    urlString: avatarUrl,
                    size: 54,
                    isGroup: true,
                    fallbackName: groupName
                )
            } else {
                AvatarUtils.createGroupAvatarView(
                    names: [groupName],
                    size: 54
                )
            }
        } else {
            // Individual user avatar - use cached version to prevent flickering
            let userId = userDetails?.userId ?? ""
            let userName = userDetails?.fullName ?? userDetails?.userName ?? groupTitle ?? "User"
            let profilePictureURL = urlString ?? userDetails?.profilePicture

            CachedProfileImage(
                userId: userId,
                urlString: profilePictureURL,
                size: 54,
                isGroup: false,
                fallbackName: userName
            )
        }
    }
}

struct UserNameRow: View {
    let name: String
    let verified: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.chatSemiBold(size: 14))
                .lineLimit(1)
            if verified {
                SwiftUI.Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(kBlue)
                    .font(.caption)
            }
        }
    }
}

struct UnreadBadge: View {
    let count: Int
    var isMarkedUnread: Bool = false

    var body: some View {
        if isMarkedUnread || count > 0 {
            ZStack {
                Circle()
                    .fill(kAccent)
                    .frame(width: 22, height: 22)
                if count > 0 {
                    Text("\(count)")
                        .font(.chatRegular(size: 10))
                        .foregroundColor(kWhite)
                }
            }
        }
    }
}

// MARK: - Typing Dots Indicator

/// Three animated dots that pulse in sequence — identical to WhatsApp's typing indicator.
private struct TypingDotsView: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(kAccent)
                    .frame(width: 4, height: 4)
                    .scaleEffect(phase == index ? 1.35 : 0.8)
                    .opacity(phase == index ? 1.0 : 0.45)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
