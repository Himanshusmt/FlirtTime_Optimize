//
//  ChatListView.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI
import UIKit
import Combine
import Foundation
import Network

// MARK: - Group Participant Model
struct GroupParticipant: Identifiable, Equatable {
    let id: String
    let userId: String
    let role: String
    let userName: String
    let fullName: String
    let profilePicture: String?
    /// NEW API `isVerified` on conversation members
    let isVerified: Bool

    init(
        id: String,
        userId: String,
        role: String,
        userName: String,
        fullName: String,
        profilePicture: String?,
        isVerified: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.role = role
        self.userName = userName
        self.fullName = fullName
        self.profilePicture = profilePicture
        self.isVerified = isVerified
    }
}

enum ChatAction {
    case archive
    case mute
    case block
    case delete
    case label
}

struct ChatListView: View {
    @StateObject private var viewModel = ChatListViewModel()

    @ObservedObject var navigator: ChatListNavigator
    @StateObject private var actionsHandler = ChatActionsHandler()
    @ObservedObject private var chatNotificationState = ChatNotificationState.shared
    @State private var searchText: String = ""
    @State private var selectedTab: ChatTab = .allChats
    @State private var isMultiSelectMode: Bool = false
    @State private var selectedChats: Set<String> = []
    @State private var showMultiDeleteConfirmation: Bool = false
    @State private var showDeleteForEveryoneConfirmation: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    
    // Story data properties
    var storyData: OtherStoryResponseModel?
    var selfUserStoryData: StoryResponseModel?

    init(navigator: ChatListNavigator = ChatListNavigator(),
         storyData: OtherStoryResponseModel? = nil,
         selfUserStoryData: StoryResponseModel? = nil) {
        self.navigator = navigator
        self.storyData = storyData
        self.selfUserStoryData = selfUserStoryData
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                headerView
                if !isMultiSelectMode {
                    SearchBar(searchText: $searchText)
                        .padding(.bottom, 8)
                }
                chatListView
            }
        }
        .overlay(
            ChatActionOverlay(
                actionsHandler: actionsHandler,
                viewModel: viewModel
            )
        )
        .onAppear {
            viewModel.onAppear()
            ChatNotificationState.shared.isInChatModule = true
            ChatNotificationState.shared.isChatListViewReady = true

            // Wire up the pop-refresh callback used by ChatListContainerViewController
            navigator.onChatDetailPopped = { [weak viewModel] in
                DispatchQueue.main.async {
                        viewModel?.refresh()
                    }
            }
        }
        .onDisappear {
            ChatNotificationState.shared.isInChatModule = false
            ChatNotificationState.shared.isChatListViewReady = false
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !viewModel.isLoading {
                        viewModel.refresh()
                    }
                }
            }
        }
        // Refresh when returning from pushed/presented screens (SwiftUI fallback path)
        .onChange(of: navigator.navigateToChatDetail) { isActive in
            if !isActive { viewModel.refresh() }
        }
        .onReceive(chatNotificationState.$pendingChatNavigation.compactMap { $0 }) { navData in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            chatNotificationState.pendingChatNavigation = nil

            if let activeId = ChatNotificationState.shared.activeConversationId,
               !activeId.isEmpty, activeId == navData.chatId {
                return
            }
            if !navData.chatId.isEmpty {
                viewModel.clearUnreadCountOptimistically(chatId: navData.chatId)
            }

            if ChatNotificationState.shared.isShowingChatDetail {
                navigator.navigateTo(data: navData)
            } else if navigator.navigateToChatDetail {
                navigator.navigateToChatDetail = false
                navigator.navigateTo(data: navData)
            } else {
                navigator.navigateTo(data: navData)
            }
        }
        .alert(String(format: ChatStrings.chat_deleteChats.localizedString(), selectedChats.count), isPresented: $showMultiDeleteConfirmation) {
            Button(ChatStrings.delete.localizedString(), role: .destructive) {
                performMultiDelete()
            }
            Button(ChatStrings.cancel.localizedString(), role: .cancel) { }
        } message: {
            Text(String(format: ChatStrings.chat_deleteChatsConfirmation.localizedString(), selectedChats.count))
        }
        .alert(ChatStrings.chat_deleteForEveryone.localizedString(), isPresented: $showDeleteForEveryoneConfirmation) {
            Button(ChatStrings.chat_deleteForEveryone.localizedString(), role: .destructive) {
                performMultiDeleteForEveryone()
            }
            Button(ChatStrings.chat_cancel.localizedString(), role: .cancel) { }
        } message: {
            Text(ChatStrings.chat_deleteForEveryoneDescription.localizedString())
        }
        .applyRTLEnvironment()
    }
    
    private var headerView: some View {
        Group {
            if isMultiSelectMode {
                multiSelectBar
            } else {
                ChatListHeader()
            }
        }
    }
    
    private var activeUsersSection: some View {
        ActiveUsersView(
            users: activeUsers,
            onUserTap: { chat in
                navigator.navigateToChat(from: .activeUser(chat))
            },
            onlineUserIds: viewModel.onlineUserIds
        )
        .padding(.top, 12)
    }
    
    private var chatListView: some View {
        Group {
            let allChats = filteredPinnedChats + filteredChats
            if allChats.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    SwiftUI.Image(ChatAssets.emptyState)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                    Text(ChatStrings.chat_noChatsYet.localizedString())
                        .font(.chatMedium(size: 16))
                        .foregroundColor(.chatTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if selectedTab == .allChats {
                        pinnedChatsSection
                    }
                    regularChatsSection
                }
                .listStyle(.plain)
                .background(Color.clear)
                .scrollDismissesKeyboard(.interactively)
                // Clearance above floating tab bar (SwiftUI List ignores UIKit contentInset overrides).
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 80)
                }
                .refreshable {
                    guard !viewModel.isLoading else { return }
                    await refreshChats()
                }
            }
        }
    }
    
    private var pinnedChatsSection: some View {
        Group {
            if selectedTab == .allChats && !filteredPinnedChats.isEmpty {
                Section {
                    ForEach(filteredPinnedChats, id: \.id) { chat in
                        chatRow(chat: chat)
                    }
                } header: {
                    pinnedChatsHeader
                }
            }
        }
    }
    
    private var regularChatsSection: some View {
        Section {
            ForEach(filteredChats, id: \.id) { chat in
                chatRow(chat: chat)
            }
        } header: {
            if !filteredChats.isEmpty {
                regularChatsHeader
            }
        }
    }
    
    private var pinnedChatsHeader: some View {
        HStack {
            HStack(spacing: 6) {
                SwiftUI.Image(systemName: "bell.fill")
                    .foregroundColor(kGray)
                Text(ChatStrings.chat_pinnedChats.localizedString())
                    .font(.chatRegular(size: 14))
                    .foregroundColor(Color.chatTextTertiary)
            }
            .padding(.horizontal, 12)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets())
    }
    
    private var regularChatsHeader: some View {
        Group {
            switch selectedTab {
            case .allChats:
                Text(ChatStrings.chat_chats.localizedString())
                    .font(.chatBold(size: 16))
                    .foregroundColor(kTextBlack)
                    .padding(.vertical, 4)
            case .groups:
                Text(ChatStrings.chat_groups.localizedString())
                    .font(.chatBold(size: 16))
                    .foregroundColor(kTextBlack)
                    .padding(.vertical, 4)
            case .channel:
                Text(ChatStrings.chat_channels.localizedString())
                    .font(.chatBold(size: 16))
                    .foregroundColor(kTextBlack)
                    .padding(.vertical, 4)
            case .archived:
                SwiftUI.EmptyView()
            }
        }
    }
    
    // MARK: - Chat Row Methods
    private func chatRow(chat: ChatMessageRow) -> some View {
        let chatId = chat.id ?? ""
        let draft: String? = {
            guard !chatId.isEmpty else { return nil }
            let text = ConversationDraftStore.shared.load(conversationId: chatId)
            guard let text, !text.isEmpty else { return nil }
            return text
        }()
        let isGroupOrChannel = chat.isGroup || (chat.type?.lowercased() == "channel")
        let isOnline = !isGroupOrChannel
            && (chat.getUserDetails()?.userId.map { viewModel.onlineUserIds.contains($0) } ?? false)
        // Touch revision so SwiftUI re-renders when ongoing-call registry changes.
        _ = viewModel.ongoingGroupCallRevision
        let ongoing = chat.isGroup ? viewModel.ongoingGroupCall(for: chatId) : nil
        return ChatRowView(
            chat: chat,
            isMultiSelectMode: isMultiSelectMode,
            isSelected: selectedChats.contains(chatId),
            isMuted: (chat.settings?.isMuted == true) || viewModel.isMuted(chatId: chatId),
            isArchived: chat.isArchived,
            isMarkedUnread: viewModel.isMarkedUnread(chatId: chatId),
            isTyping: viewModel.typingConversationIds.contains(chatId),
            isPending: viewModel.pendingConversationIds.contains(chatId),
            isOnline: isOnline,
            draftText: draft,
            hasOngoingGroupCall: ongoing != nil,
            ongoingGroupCallIsVideo: ongoing?.type == .video,
            onSelect: { handleChatSelect(chat: chat) },
            onLongPress: { handleChatLongPress(chat: chat) },
            onTap: { handleChatTap(chat: chat) },
            onMute: {
                actionsHandler.showAction(.mute, for: chat)
            },
            onUnMute: {
                handleUnmuteChat(chat: chat)
            },
            onRead: {
                viewModel.toggleChatReadStatus(chatId: chatId)
            },
            onArchive: {
                actionsHandler.showAction(.archive, for: chat)
            },
            onDelete: {
                actionsHandler.showAction(.delete, for: chat)
            }
        )
    }

    
    // MARK: - Action Handlers
    private func handleChatSelect(chat: ChatMessageRow) {
        let chatId = chat.id ?? ""
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedChats.contains(chatId) {
                selectedChats.remove(chatId)
            } else {
                selectedChats.insert(chatId)
            }
            if selectedChats.isEmpty {
                isMultiSelectMode = false
            }
        }
    }
    
    private func handleChatLongPress(chat: ChatMessageRow) {
        if !isMultiSelectMode {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            withAnimation(.easeInOut(duration: 0.25)) {
                isMultiSelectMode = true
                selectedChats = [chat.id ?? ""]
            }
        }
    }
    

    
    private func handleChatTap(chat: ChatMessageRow) {
        if !isMultiSelectMode {
            let unread = chat.unreadCount ?? 0
            if let chatId = chat.id, ((chat.unreadCount ?? 0) > 0 || viewModel.isMarkedUnread(chatId: chatId)) {
                viewModel.clearUnreadCountOptimistically(chatId: chatId)
                NotificationCenter.default.post(
                    name: NSNotification.Name("ChatUnreadCountUpdated"),
                    object: nil,
                    userInfo: ["conversationId": chatId]
                )
            }
            navigator.navigateToChat(from: .existingChat(chat), unreadCount: unread)
        }
    }
    
    private func handleUnmuteChat(chat: ChatMessageRow) {
        let chatId = chat.id ?? ""
        viewModel.unmuteChat(id: chatId)
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private var multiSelectBar: some View {
        let unpinnedSelectedCount = selectedChats.filter { !viewModel.isPinned(chatId: $0) }.count
        let currentPinnedCount = viewModel.pinnedChatIds.count
        let canPin = !selectedChatIsPinned && (currentPinnedCount + unpinnedSelectedCount <= 3)
        return MultiSelectActionBar(
            selectedCount: selectedChats.count,
            totalChatsCount: filteredChats.count + filteredPinnedChats.count,
            hasPinnedChats: selectedChatIsPinned,
            canPinMoreChats: canPin,
            hasBlockedChats: selectedChatIsBlocked,
            hasUnreadChats: selectedChatIsUnread,
            hasMutedChats: selectedChatsHaveMuted,
            hasUnmutedChats: selectedChatsHaveUnmuted,
            hasGroupChatsSelected: selectedChatsContainGroup,
            isSingleDirectChatSelected: isSingleDirectChatSelected,
            onCancel: {
                isMultiSelectMode = false
                selectedChats.removeAll()
            },
            onAction: { action in
                handleMultiSelectAction(action)
            }
        )
    }
    
    private var selectedChatIsPinned: Bool {
        guard !selectedChats.isEmpty else { return false }
        return selectedChats.allSatisfy { viewModel.isPinned(chatId: $0) }
    }
    
    private var selectedChatIsBlocked: Bool {
        // Only check for single selection since block/unblock is only for single selection
        guard selectedChats.count == 1, let chatId = selectedChats.first else {
            return false
        }
        return viewModel.isBlockedChat(chatId: chatId)
    }
    
    private var selectedChatIsUnread: Bool {
        // Check for multi-select - returns true if ANY selected chat is unread (actual or marked)
        if selectedChats.count > 1 {
            return selectedChats.contains { chatId in
                let chat = viewModel.chats.first(where: { $0.id == chatId })
                let hasUnreadCount = (chat?.unreadCount ?? 0) > 0
                let isMarkedUnread = viewModel.isMarkedUnread(chatId: chatId)
                return hasUnreadCount || isMarkedUnread
            }
        }
        // Single selection check
        guard let chatId = selectedChats.first else {
            return false
        }
        let chat = viewModel.chats.first(where: { $0.id == chatId })
        let hasUnreadCount = (chat?.unreadCount ?? 0) > 0
        let isMarkedUnread = viewModel.isMarkedUnread(chatId: chatId)
        return hasUnreadCount || isMarkedUnread
    }

    private var selectedChatsHaveMuted: Bool {
        return selectedChats.contains { chatId in
            viewModel.isMuted(chatId: chatId)
        }
    }
    
    private var selectedChatsHaveUnmuted: Bool {
        return selectedChats.contains { chatId in
            !viewModel.isMuted(chatId: chatId)
        }
    }
    
    private var selectedChatsContainGroup: Bool {
        return selectedChats.contains { chatId in
            guard let chat = viewModel.chats.first(where: { $0.id == chatId }) else { return false }
            return chat.isGroup
        }
    }

    private var isSingleDirectChatSelected: Bool {
        guard selectedChats.count == 1, let chatId = selectedChats.first,
              let chat = viewModel.chats.first(where: { $0.id == chatId }) else { return false }
        let type = chat.type?.lowercased() ?? ""
        // Treat any non-group / non-channel row as a direct chat (API may omit type)
        return !chat.isGroup && type != "group" && type != "channel"
    }

    private var activeUsers: [ChatMessageRow] {
        return viewModel.activeUsers
    }
    
    private var pinnedChats: [ChatMessageRow] {
        return viewModel.pinnedChats
    }
    
    private var filteredPinnedChats: [ChatMessageRow] {
        let basePinned = pinnedChats
        
        if searchText.isEmpty {
            return basePinned
        } else {
            return basePinned.filter {
                let userDetails = $0.getUserDetails()
                return (userDetails?.fullName?.lowercased().contains(searchText.lowercased()) ?? false) ||
                       (userDetails?.userName?.lowercased().contains(searchText.lowercased()) ?? false) ||
                       ($0.title?.lowercased().contains(searchText.lowercased()) ?? false)
            }
        }
    }
    
    private var filteredChats: [ChatMessageRow] {
        let base: [ChatMessageRow]
        switch selectedTab {
        case .allChats:
            // Only show unpinned and unarchived chats in the main list (blocked chats are still visible)
            base = viewModel.unpinnedChats.filter { chat in
                !chat.isArchived
            }
        case .groups:
            base = viewModel.chats.filter { chat in 
                chat.isGroup && !chat.isArchived
            }
        case .channel:
            base = []
        case .archived:
            base = viewModel.chats.filter { chat in
                chat.isArchived
            }
        }
        
        if searchText.isEmpty {
            return base
        } else {
            return base.filter { chat in
                let searchTerm = searchText.lowercased()
                
                // Search in group chat titles
                if chat.isGroup {
                    return chat.title?.lowercased().contains(searchTerm) ?? false
                } 
                // Search in direct chat user details
                else if let userDetails = chat.getUserDetails() {
                    return (userDetails.fullName?.lowercased().contains(searchTerm) ?? false) ||
                           (userDetails.userName?.lowercased().contains(searchTerm) ?? false)
                }
                
                return false
            }
        }
    }
    
    private var filteredArchivedChats: [ChatMessageRow] {
        let base = viewModel.chats.filter { chat in
            chat.isArchived
        }
        
        if searchText.isEmpty {
            return base
        } else {
            return base.filter { chat in
                let searchTerm = searchText.lowercased()
                
                // Search in group chat titles
                if chat.isGroup {
                    return chat.title?.lowercased().contains(searchTerm) ?? false
                } 
                // Search in direct chat user details
                else if let userDetails = chat.getUserDetails() {
                    return (userDetails.fullName?.lowercased().contains(searchTerm) ?? false) ||
                           (userDetails.userName?.lowercased().contains(searchTerm) ?? false)
                }
                
                return false
            }
        }
    }
    
    private func handleMultiSelectAction(_ action: MultiSelectAction) {
        let ids = selectedChats
        switch action {
        case .selectAll:
            // Select all chats in current view
            let allChatIds = (filteredPinnedChats + filteredChats).compactMap { $0.id }
            selectedChats = Set(allChatIds)
        case .deselectAll:
            selectedChats.removeAll()
        case .delete:
            showMultiDeleteConfirmation = true
        case .deleteForEveryone:
            showDeleteForEveryoneConfirmation = true
        case .archive:
            let chatsToArchive = ids.compactMap { id in
                viewModel.chats.first(where: { $0.id == id })
            }
            
            for chat in chatsToArchive {
                let chatId = chat.id ?? ""
                viewModel.updateChatArchiveStatus(chatId: chatId, isArchived: true)
            }
            
            selectedChats.removeAll()
            isMultiSelectMode = false
        case .mute:
            for id in ids {
                viewModel.muteChat(id: id)
            }
            selectedChats.removeAll()
            isMultiSelectMode = false
        case .unmute:
            for id in ids {
                viewModel.unmuteChat(id: id)
            }
            selectedChats.removeAll()
            isMultiSelectMode = false
        case .pin:
            for id in ids {
                viewModel.pinChat(id: id)
            }
            selectedChats.removeAll()
            isMultiSelectMode = false
        case .unpin:
            for id in ids {
                viewModel.unpinChat(id: id)
            }
            selectedChats.removeAll()
            isMultiSelectMode = false
        case .block:
            if let firstChatId = ids.first,
               let firstChat = viewModel.chats.first(where: { $0.id == firstChatId }) {
                actionsHandler.showAction(.block, for: firstChat)
            }
            selectedChats.removeAll()
            isMultiSelectMode = false
        case .unblock:
            for id in ids {
                viewModel.unblockChat(chatId: id)
            }
            selectedChats.removeAll()
            isMultiSelectMode = false
        case .markUnread:
            for id in ids {
                viewModel.markChatAsUnread(chatId: id)
            }
            selectedChats.removeAll()
            isMultiSelectMode = false
        case .markAsRead:
            for id in ids {
                viewModel.markChatAsRead(chatId: id)
            }
            selectedChats.removeAll()
            isMultiSelectMode = false
        case .label:
            if let firstChatId = ids.first,
               let firstChat = viewModel.chats.first(where: { $0.id == firstChatId }) {
                actionsHandler.showAction(.label, for: firstChat)
            }
            isMultiSelectMode = false
        case .lock:
            break
        }
    }


    private func performMultiDelete() {
        let ids = Array(selectedChats)
        viewModel.deleteConversations(ids: ids, forEveryone: false)
        selectedChats.removeAll()
        isMultiSelectMode = false
        showMultiDeleteConfirmation = false
    }

    private func performMultiDeleteForEveryone() {
        let ids = Array(selectedChats)
        viewModel.deleteConversations(ids: ids, forEveryone: true)
        selectedChats.removeAll()
        isMultiSelectMode = false
        showDeleteForEveryoneConfirmation = false
    }

    private func getChatName(_ chat: ChatMessageRow) -> String {
        if chat.isGroup {
            return chat.title ?? ChatStrings.chat_groupChat.localizedString()
        } else {
            let userDetails = chat.getUserDetails()
            return userDetails?.fullName ?? userDetails?.userName ?? "Unknown"
        }
    }
    
    @MainActor
    private func refreshChats() async {
        viewModel.forceRefreshChats()

        let deadline = ContinuousClock.now + .seconds(15)
        while viewModel.isLoading, ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    @MainActor
    private func refreshArchivedChats() async {
        viewModel.loadArchivedChats()

        let deadline = ContinuousClock.now + .seconds(15)
        while viewModel.isLoadingArchived, ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}




final class NetworkMonitor: ObservableObject {

    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")
    private var disconnectDebounce: DispatchWorkItem?

    @Published var isConnected: Bool = true
    /// True when the current satisfied (or last) path uses cellular.
    private(set) var usesCellular: Bool = false

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                self.usesCellular = path.usesInterfaceType(.cellular)
                if path.status == .satisfied {
                    self.disconnectDebounce?.cancel()
                    self.disconnectDebounce = nil
                    self.isConnected = true
                } else {
                    // Brief Wi-Fi↔LTE / captive flaps must not drop a live call UI.
                    let work = DispatchWorkItem { [weak self] in
                        self?.isConnected = false
                    }
                    self.disconnectDebounce?.cancel()
                    self.disconnectDebounce = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
                }
            }
        }

        monitor.start(queue: queue)
    }
}
