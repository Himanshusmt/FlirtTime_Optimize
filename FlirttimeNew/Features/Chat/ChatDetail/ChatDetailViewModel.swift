//
//  ChatDetailViewModel.swift
//  FlirttimeNew
//
//  Created by Awais on 05/08/25.
//

import SwiftUI
import AVFoundation
import Combine
import Foundation
import Swinject
import RxSwift

// MARK: - Chat Error Types
enum ChatError: Error, LocalizedError, CaseIterable {
    case networkConnectionLost
    case messageUploadFailed
    case audioRecordingFailed
    case audioPlaybackFailed
    case mediaUploadFailed
    case messageLoadFailed
    case userBlockedError
    case attachmentTooLarge
    case invalidMessageContent
    case socketConnectionFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .networkConnectionLost:
            return ChatStrings.chat_errorConnectionLost.localizedString()
        case .messageUploadFailed:
            return ChatStrings.chat_errorSendFailed.localizedString()
        case .audioRecordingFailed:
            return ChatStrings.chat_errorRecordingFailed.localizedString()
        case .audioPlaybackFailed:
            return ChatStrings.chat_errorAudioCorrupt.localizedString()
        case .mediaUploadFailed:
            return ChatStrings.chat_errorMediaUpload.localizedString()
        case .messageLoadFailed:
            return ChatStrings.chat_errorLoadMessages.localizedString()
        case .userBlockedError:
            return ChatStrings.chat_errorBlockedUserSend.localizedString()
        case .attachmentTooLarge:
            return ChatStrings.chat_errorFileTooLarge.localizedString()
        case .invalidMessageContent:
            return ChatStrings.chat_errorInvalidContent.localizedString()
        case .socketConnectionFailed:
            return ChatStrings.chat_errorRealtimeLost.localizedString()
        case .permissionDenied:
            return ChatStrings.chat_errorPermission.localizedString()
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .networkConnectionLost, .messageUploadFailed, .mediaUploadFailed, .messageLoadFailed, .socketConnectionFailed:
            return true
        case .audioRecordingFailed, .audioPlaybackFailed, .userBlockedError, .attachmentTooLarge, .invalidMessageContent, .permissionDenied:
            return false
        }
    }
}

// MARK: - Grouped State Structs

// MARK: - Typing Indicator State

struct TypingIndicatorState {
    var isTyping: Bool = false
    var senderName: String? = nil
    var senderId: String? = nil
}

struct AudioRecordingState {
    var isRecordingAudio: Bool = false
    var hasRecordedAudio: Bool = false
    var recordingDuration: Int = 0
    var recordedAudioDuration: String?
    var liveWaveAmplitudes: [CGFloat] = []
    var isPlayingRecordedAudio: Bool = false
    var isRecordedAudioPaused: Bool = false
    var recordedAudioProgress: Double = 0
    var recordedWaveSeed: String?
}

struct AudioPlaybackState {
    var currentlyPlayingMessageId: String?
    var currentlyPlayingStableId: String?
    var isPaused: Bool = false
    var playbackProgressByMessageId: [String: Double] = [:]
    var currentTime: Double = 0
    var duration: Double = 0

    func isCurrentMessage(id: String, stableId: String) -> Bool {
        if let playing = currentlyPlayingMessageId, !playing.isEmpty {
            if playing == id || playing == stableId { return true }
        }
        if let stable = currentlyPlayingStableId, !stable.isEmpty {
            if stable == id || stable == stableId { return true }
        }
        return false
    }

    func progress(id: String, stableId: String) -> Double {
        playbackProgressByMessageId[id]
            ?? playbackProgressByMessageId[stableId]
            ?? 0
    }
}

struct CallState {
    var isInCall: Bool = false
    var isShowingIncomingCallSheet: Bool = false
    var incomingCallData: [String: Any]?
    var dyteAuthToken: String?
    var isWaitingForCallResponse: Bool = false
}

// MARK: - Multi-Selection State
struct MessageSelectionState {
    var isSelectionMode: Bool = false
    var selectedMessageIds: Set<String> = []

    var selectionCount: Int {
        selectedMessageIds.count
    }

    var hasSelection: Bool {
        !selectedMessageIds.isEmpty
    }

    mutating func toggle() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedMessageIds.removeAll()
        }
    }

    mutating func toggleMessage(_ messageId: String) {
        if selectedMessageIds.contains(messageId) {
            selectedMessageIds.remove(messageId)
        } else {
            selectedMessageIds.insert(messageId)
        }
    }

    mutating func selectAll(from messageIds: [String]) {
        selectedMessageIds = Set(messageIds)
    }

    mutating func clear() {
        selectedMessageIds.removeAll()
    }

    mutating func exitSelectionMode() {
        isSelectionMode = false
        selectedMessageIds.removeAll()
    }

    func isSelected(_ messageId: String) -> Bool {
        selectedMessageIds.contains(messageId)
    }
}

// MARK: - Chat Detail ViewModel
@MainActor
final class ChatDetailViewModel: ObservableObject {
    
    // MARK: Grouped Published State (reduces objectWillChange fires)
    @Published var audioRecording = AudioRecordingState()
    @Published var audioPlayback = AudioPlaybackState()
    @Published var callState = CallState()
    @Published var selection = MessageSelectionState()

    @Published var groupedMessages: [MessageGroup] = []
    var messages: [ConversationMessage] = []
    
    @Published var firstUnreadMessageId: String? = nil
    var unreadCountOnOpen: Int = 0

    // MARK: - FRC (single source of truth via CoreData)
    static let useFRC = true
    private var messageFRC: ChatMessageFRC?
    var pendingRemovalCount = 0
    var locallyDeletedMessageIds: Set<String> = []

    // MARK: Published UI State — header
    @Published var userStatus: String = ""
    @Published var headerUserData: UserRes?
    @Published var groupTitle: String = ""
    @Published var groupParticipants: [GroupParticipant] = [] {
        didSet {
            mentionManager.allParticipants = groupParticipants
            mentionManager.isGroupChat = isGroupChat
        }
    }
    @Published var participantsCount: Int? = nil
    @Published var isGroupParticipant: Bool = true

    let mentionManager = MentionManager()
    @Published var conversationAvatarURL: String? = nil

    // MARK: Published UI State — input & composing
    @Published var replyingToMessage: ConversationMessage?
    @Published var editingMessage: ConversationMessage?
    @Published var editMessageText: String = ""
    @Published var isAudioUploading: Bool = false

    // MARK: Published UI State — loading & scrolling
    @Published var isLoadingMessages: Bool = false
    @Published var isLoadingOlderMessages: Bool = false
    @Published var pendingScrollToMessageId: String?
    /// Intentional navigation (pinned banner, reply jump) — always scrolls, ignores near-bottom gate.
    @Published var forceScrollToMessageId: String?
    @Published var shouldAutoScroll: Bool = true
    @Published var isAtBottom: Bool = true
    @Published var isInHistoricalWindow: Bool = false
    @Published var pendingReturnToLatest: Bool = false
    @Published var shouldScrollToBottomAfterWindowChange: Bool = false
    @Published var offBottomNewMessageIds: Set<String> = []
    @Published var channelFollowersCount: Int? = nil

    // MARK: Published UI State — overlays & alerts
    @Published var toastMessage: String?
    @Published var showDeleteMessageSheet: Bool = false
    @Published var selectedMessageForDelete: ConversationMessage?
    @Published var highlightedMessageId: String?
    @Published var isBlocked: Bool = false
    @Published var currentPinnedMessage: ConversationMessage?
    @Published var isJumpingToPinnedMessage: Bool = false

    var isPinStateRestoredFromCache: Bool = false
    @Published var shouldShowBlockView: Bool = false
    @Published var reactionListMessage: ConversationMessage?

    // MARK: Published UI State — typing indicator
    @Published var typingIndicator = TypingIndicatorState()

    @Published var showingTranslations: Set<String> = []
    @Published var pollSelectionMap: [String: String] = [:]
    var isSend: Bool = false
    var errorMessage: String?
    var currentError: ChatError?
    var canRetryLastError: Bool = false

    var deferredPrependMessages: [ConversationMessage] = []
    var isSilentPrepending: Bool = false
    var isLoadingHistory: Bool = false
    var editingMessageId: String?
    var sessionManager: SessionManager?
    let disposeBag = DisposeBag()
    // MARK: - Child Managers
    lazy var audioManager: AudioManager = AudioManager(context: self, audioService: self.audioService)
    lazy var mediaManager: MediaManager = MediaManager(context: self)

    // Layout cache for long threads (exposed for collection view)
    var messageRowHeightCache: [String: CGFloat] = [:]
    
    // MARK: - Toast Helper
    func showToastMessage(_ text: String, duration: TimeInterval = 2.0) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.toastMessage == text { self?.toastMessage = nil }
        }
    }

    private var heightCacheInsertionOrder: [String] = []

    func cacheMessageRowHeight(messageId: String, height: CGFloat) {
        guard height > 0 else { return }
        if messageRowHeightCache[messageId] != height {
            messageRowHeightCache[messageId] = height
            if heightCacheInsertionOrder.last != messageId {
                heightCacheInsertionOrder.append(messageId)
            }
            if messageRowHeightCache.count > 500 {
                for key in heightCacheInsertionOrder.prefix(100) {
                    messageRowHeightCache.removeValue(forKey: key)
                }
                heightCacheInsertionOrder.removeFirst(100)
            }
        }
    }
    
    var selectedId: String = ""
    var selectedUserChatID: String = ""
    var activeStatus: String = ""
    var user: UserRes?
    var selectedMessageId: String?
    var storyData: OtherStoryResponseModel?
    var selfUserStoryData: StoryResponseModel?
    var onConversationDeleted: (() -> Void)?
    
    var currentMeetingId: String?
    
    let userListViewModel: ChatUserListViewModel
    let messageService: ChatMessageServiceProtocol
    let audioService: ChatAudioServiceProtocol
    let socketService: ChatSocketServiceProtocol
    let mediaService: ChatMediaServiceProtocol
    let stateManager: ChatStateManagerProtocol
    let messageSyncCoordinator: ChatMessageSyncCoordinator
    let conversationRepository: ConversationRepositoryAsync?
    let messageRepository: MessageRepositoryAsync
    private let conversationPresentationStore = ConversationPresentationStore.shared
    
    var tempMessageMapping: [String: ConversationMessage] = [:]
    var mediaCacheData: [String: Data] { mediaManager.mediaCacheData }
    var mediaCacheInsertionOrder: [String] { mediaManager.mediaCacheInsertionOrder }
    let maxMediaCacheCount = 50

    var lastFailedMessageId: String?
    var isGroupChat: Bool = false
    // Channel context
    var isChannel: Bool = false
    var channelId: String = ""
    var channelShareLink: String?
    var channelName: String?
    var channelDescription: String?
    var isChannelAdmin: Bool = false
    @Published var isChannelFollowed: Bool = false
    @Published var hasResolvedChannelRole: Bool = false
    private let channelRepository = ChannelRepository()

    /// Load cached channel details from CoreData for instant display.
    func loadCachedChannelDetails() {
        guard !channelId.isEmpty else { return }
        guard let cached = channelRepository.getCachedChannel(id: channelId) else { return }
        if channelName == nil, !cached.name.isEmpty {
            channelName = cached.name
            groupTitle = cached.name
        }
        if let desc = cached.description {
            channelDescription = desc
        }
        if let followed = cached.hasFollowed {
            isChannelFollowed = followed
        }
        isChannelAdmin = cached.isAdmin ?? false
        if let count = cached.followersCount, channelFollowersCount == nil {
            channelFollowersCount = count
        }
        if let icon = cached.icon, !icon.isEmpty {
            conversationAvatarURL = icon
        }
        if let link = cached.resolvedShareURL?.absoluteString {
            channelShareLink = link
        }
        hasResolvedChannelRole = true
        AppLogger.debug("[ChannelCache] loaded cached details for channel=\(channelId)")
    }

    func resolvedChannelShareLink() -> String? {
        if let link = ChannelShareLinkBuilder.resolve(shareLink: channelShareLink, inviteSlug: nil) {
            return link
        }
        guard !channelId.isEmpty,
              let cached = channelRepository.getCachedChannel(id: channelId) else { return nil }
        return cached.resolvedShareURL?.absoluteString
    }

    func hydrateChannelShareLinkFromCacheIfNeeded() {
        guard resolvedChannelShareLink() == nil, !channelId.isEmpty,
              let cached = channelRepository.getCachedChannel(id: channelId),
              let link = cached.resolvedShareURL?.absoluteString else { return }
        channelShareLink = link
    }

    // MARK: - Session Bootstrap

    func prepareForDisplay(
        selectedId: String,
        selectedUserChatID: String,
        user: UserRes?,
        activeStatus: String,
        isGroupChat: Bool,
        groupTitle: String,
        groupParticipants: [GroupParticipant],
        isGroupParticipant: Bool,
        groupAvatarUrl: String,
        isChannel: Bool,
        channelId: String,
        isAlreadyFollowingChannel: Bool,
        canSendInChannel: Bool = false,
        onReady: @escaping () -> Void
    ) {
        // Reset state when switching conversations
        if self.selectedId != selectedId && !selectedId.isEmpty {
            hasPreloadedCachedMessages = false
            hasMorePages = true
            currentPage = 1
            lastLoadMoreTime = nil
            isLoadingHistory = false
            stateManager.setMessages([])
            messages = []
            groupedMessages = []
            isLoadingDirectPresence = false
            userStatus = ""
        }

        self.selectedUserChatID = selectedUserChatID
        self.user = user
        self.activeStatus = activeStatus
        self.isGroupChat = isGroupChat
        self.isChannel = isChannel
        self.channelId = channelId
        isChannelFollowed = isAlreadyFollowingChannel

        if isChannel {
            self.selectedId = ""
        } else {
            self.selectedId = selectedId
            reinitializeFRC()
        }

        if isChannel && !channelId.isEmpty {
            loadCachedChannelDetails()
            // Navigation already knows the user can post (e.g. just created / opened as owner).
            // Seed before API so the composer is visible immediately; API may refine later.
            if canSendInChannel {
                isChannelAdmin = true
                hasResolvedChannelRole = true
            }
        }

        if isGroupChat {
            setInitialGroupMetadata(
                title: groupTitle,
                participants: groupParticipants,
                isParticipant: isGroupParticipant,
                avatarUrl: groupAvatarUrl
            )
        } else {
            self.isGroupParticipant = true
        }

        // Profile/list user-block may not yet be on conversation.settings — seed overlay from local set.
        if !isGroupChat, !isChannel {
            let peerId = selectedUserChatID.isEmpty
                ? (user?.userId ?? user?.id ?? "")
                : selectedUserChatID
            if !peerId.isEmpty, BlockedUsersManager.shared.isBlocked(id: peerId) {
                applyBlockUIState(isBlocked: true)
            }
        }

        applySharedConversationPresentationState()

        // Re-subscribe to background uploads (cancellables cleared on cleanup)
        observeBackgroundUploads()

        if let user {
            setHeaderUserData(user)
        }

        // Notification tracking
        ChatNotificationState.shared.isInChatModule = true
        let trackedId = isChannel ? channelId : selectedId
        ChatNotificationState.shared.activeConversationId = trackedId.isEmpty ? nil : trackedId


        // Online status
        if !isGroupChat && !isChannel && !selectedUserChatID.isEmpty {
            socketService.setOtherUserId(selectedUserChatID)
            if ChatListSocketService.shared.onlineUserIds.contains(selectedUserChatID) {
                userStatus = ChatStrings.chat_online.localizedString()
            }
        } else {
            socketService.setOtherUserId(nil)
        }

        // Load messages based on entry path
        if isChannel {
            loadChannelSession(onReady: onReady)
        } else if !selectedId.isEmpty {
            loadExistingSession(selectedId: selectedId, onReady: onReady)
        } else {
            loadNewSession(selectedUserChatID: selectedUserChatID, onReady: onReady)
        }

        // FE: fetchConversation(id) as soon as group opens — members + count + sender names
        if isGroupChat, !selectedId.isEmpty {
            loadGroupMembersFromAPI()
        }

        // Direct chat: GET conversations/{id} for online / lastSeen / username subtitle
        if isDirectChat, !selectedId.isEmpty {
            loadDirectConversationPresenceFromAPI()
        }
    }

    private func loadChannelSession(onReady: @escaping () -> Void) {
        ChatNotificationState.clearNotifications(for: channelId)
        if !channelId.isEmpty {
            socketService.emitJoinChannel(channelId)
            markChannelAsRead()
        }
        if messages.isEmpty {
            loadMessages(page: 1)
        }
        resumeActiveSession()
        onReady()
    }
    
    func calculateFirstUnreadMessageId() {
        let myId = getCurrentUserId()
        // Find first message that is incoming and not yet read
        if let firstUnread = messages.first(where: { msg in
            let isIncoming = (msg.sender?.id ?? msg.senderId) != myId
            let isUnread = msg.deliveryStatus != .read
                && (msg.status?.lowercased() != "seen")
                && (msg.seenAt == nil)
            return isIncoming && isUnread
        }) {
            firstUnreadMessageId = firstUnread.id
            unreadCountOnOpen = messages.filter { msg in
                let isIncoming = (msg.sender?.id ?? msg.senderId) != myId
                let isUnread = msg.deliveryStatus != .read
                    && (msg.status?.lowercased() != "seen")
                    && (msg.seenAt == nil)
                return isIncoming && isUnread
            }.count
        } else {
            firstUnreadMessageId = nil
            unreadCountOnOpen = 0
        }
    }

    private func loadExistingSession(selectedId: String, onReady: @escaping () -> Void) {
        let injected = injectPreloadedMessages()
        if !self.selectedId.isEmpty {
            ChatNotificationState.shared.activeConversationId = self.selectedId
        }
        calculateFirstUnreadMessageId()
        markConversationAsRead()
        ChatNotificationState.clearNotifications(for: selectedId)
        if injected {
            scheduleBackgroundSyncAfterInjection()
        } else {
            refreshMessages()
        }
        resumeActiveSession()
        onReady()
    }

    private func loadNewSession(selectedUserChatID: String, onReady: @escaping () -> Void) {
        let existingId: String? = {
            guard !selectedUserChatID.isEmpty else { return nil }
            return (conversationRepository as? ConversationRepository)?
                .findConversationIdByParticipant(userId: selectedUserChatID)
        }()

        if let existingId = existingId {
            self.selectedId = existingId
            ChatNotificationState.shared.activeConversationId = existingId
            calculateFirstUnreadMessageId()
            markConversationAsRead()
            // Clear any lingering notifications for this conversation from the tray.
            ChatNotificationState.clearNotifications(for: existingId)
            let injected = injectPreloadedMessages()
            if injected {
                scheduleBackgroundSyncAfterInjection()
            } else {
                refreshMessages()
            }
            loadDirectConversationPresenceFromAPI()
            resumeActiveSession()
            onReady()
        } else {
            let injected = injectPreloadedMessages()
            ensureConversationReady { [weak self] success in
                guard let self else { return }
                if success && !self.selectedId.isEmpty {
                    ChatNotificationState.shared.activeConversationId = self.selectedId
                }
                if success {
                    self.calculateFirstUnreadMessageId()
                    self.markConversationAsRead()
                    // Clear notifications for the newly created conversation.
                    if !self.selectedId.isEmpty {
                        ChatNotificationState.clearNotifications(for: self.selectedId)
                    }
                    if injected {
                        self.scheduleBackgroundSyncAfterInjection()
                    } else {
                        self.refreshMessages()
                    }
                    self.loadDirectConversationPresenceFromAPI()
                }
                self.resumeActiveSession()
                onReady()
            }
        }
    }

    private func resumeActiveSession() {
        startSocketListening()
        startUserStatusEmitting()
        // Group members also loaded from prepareForDisplay; re-fetch on resume/reconnect path
        if isGroupChat {
            loadGroupMembersFromAPI()
        }
    }

    /// FE `fetchConversation` — GET /chat/conversations/{id}
    /// Loads `members` + `participantsCount` for subtitle, sender names, and group detail.
    private var isLoadingGroupDetail = false
    private var isLoadingDirectPresence = false

    /// Direct chat: GET /chat/conversations/{id} → online / lastSeen → header subtitle
    /// (both null → peer username).
    private func loadDirectConversationPresenceFromAPI() {
        guard isDirectChat, !selectedId.isEmpty else { return }
        guard !isLoadingDirectPresence else { return }
        guard let session = userListViewModel.sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self) else { return }

        let conversationId = selectedId
        isLoadingDirectPresence = true
        session.getConversationDetail(conversationId: conversationId)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] chat in
                    guard let self else { return }
                    self.isLoadingDirectPresence = false
                    guard self.selectedId == conversationId, self.isDirectChat else { return }

                    // Keep peer id / header in sync from detail payload
                    if let details = chat.getUserDetails() {
                        if self.selectedUserChatID.isEmpty, let peerId = details.userId, !peerId.isEmpty {
                            self.selectedUserChatID = peerId
                            self.socketService.setOtherUserId(peerId)
                            self.socketService.emitSubscribePresence(userIds: [peerId])
                        }
                        let needsHeader = (self.headerUserData?.userName ?? "").isEmpty
                            && (self.user?.userName ?? "").isEmpty
                        if needsHeader || self.headerUserData == nil {
                            let user = UserRes(
                                id: nil,
                                userId: details.userId,
                                userName: details.userName,
                                fullName: details.fullName,
                                type: nil,
                                profilePicture: nil,
                                isPrivate: nil,
                                verified: nil,
                                profilePictureDetails: ProfilePictureDetails(filePath: details.profilePicture),
                                follower_profile: nil,
                                isFollowing: nil,
                                isSelected: nil, searchedAt: nil
                            )
                            self.setHeaderUserData(user)
                            if self.user == nil { self.user = user }
                        }
                    }

                    self.applyOpenChatPresence(
                        chat.onlineStatus,
                        username: self.peerUsernameForPresenceFallback()
                    )
                },
                onFailure: { [weak self] error in
                    guard let self else { return }
                    self.isLoadingDirectPresence = false
                    AppLogger.debug("[DirectPresence] detail failed: \(error.localizedDescription)")
                    // Leave subtitle blank; nav bar centers the profile name.
                }
            )
            .disposed(by: disposeBag)
    }

    func peerUsernameForPresenceFallback() -> String {
        let candidates = [
            headerUserData?.userName,
            user?.userName,
        ]
        for raw in candidates {
            let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty { return name }
        }
        return ""
    }

    func applyOpenChatPresence(_ online: OnlineStatus?, username: String?) {
        let resolvedUsername = (username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? username
            : peerUsernameForPresenceFallback()

        guard let online else {
            userStatus = ""
            return
        }

        userStatus = online.openChatSubtitle(username: resolvedUsername)

        socketService.setPresencePrivacy(
            lastSeenVisibility: online.lastSeenVisibility ?? "everyone",
            onlineVisibility: online.onlineVisibility ?? "everyone",
            viewerIsContact: true
        )
    }

    private func loadGroupMembersFromAPI() {
        guard isGroupChat, !selectedId.isEmpty else { return }
        guard !isLoadingGroupDetail else { return }
        guard let session = userListViewModel.sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self) else { return }

        let conversationId = selectedId
        isLoadingGroupDetail = true
        session.getConversationDetail(conversationId: conversationId)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] chat in
                    guard let self else { return }
                    self.isLoadingGroupDetail = false
                    var row = chat
                    if row.type == nil || row.type?.isEmpty == true {
                        row.type = "group"
                    }
                    let mapped = self.mapGroupParticipants(row.participants)
                    AppLogger.debug("[GroupMembers] GET conversations/\(conversationId) members=\(mapped.count) count=\(row.participantsCount ?? -1)")

                    // Always apply title / count / members from detail (FE fetchConversation)
                    self.updateGroupMetadata(from: row)
                    Task { try? await self.conversationRepository?.saveConversation(row) }

                    // Newly added members miss `call:incoming` — Join banner comes from `activeCall`.
                    AgoraCallService.shared.syncOngoingGroupCalls(from: [row])

                    if mapped.isEmpty {
                        session.getConversationMembers(conversationId: conversationId)
                            .observe(on: MainScheduler.instance)
                            .subscribe(
                                onSuccess: { [weak self] members in
                                    guard let self, !members.isEmpty else { return }
                                    row.participants = members
                                    if row.participantsCount == nil || (row.participantsCount ?? 0) < members.count {
                                        row.participantsCount = members.count
                                    }
                                    self.updateGroupMetadata(from: row)
                                    Task { try? await self.conversationRepository?.saveConversation(row) }
                                },
                                onFailure: { error in
                                    AppLogger.debug("[GroupMembers] members endpoint failed: \(error.localizedDescription)")
                                }
                            )
                            .disposed(by: self.disposeBag)
                    }
                },
                onFailure: { [weak self] error in
                    guard let self else { return }
                    self.isLoadingGroupDetail = false
                    AppLogger.debug("[GroupMembers] detail failed: \(error.localizedDescription) — trying members endpoint")
                    session.getConversationMembers(conversationId: conversationId)
                        .observe(on: MainScheduler.instance)
                        .subscribe(
                            onSuccess: { [weak self] members in
                                guard let self, !members.isEmpty else { return }
                                var row = ChatMessageRow()
                                row.id = conversationId
                                row.type = "group"
                                row.participants = members
                                row.participantsCount = members.count
                                self.updateGroupMetadata(from: row)
                            },
                            onFailure: { err in
                                AppLogger.debug("[GroupMembers] members fallback failed: \(err.localizedDescription)")
                            }
                        )
                        .disposed(by: self.disposeBag)
                }
            )
            .disposed(by: disposeBag)
    }

    /// Save current channel details to CoreData for future offline access.
    func persistChannelDetails() {
        guard !channelId.isEmpty else { return }
        channelRepository.saveChannelDetails(
            id: channelId,
            isAdmin: isChannelAdmin,
            isFollowed: isChannelFollowed,
            followersCount: channelFollowersCount,
            name: channelName,
            icon: conversationAvatarURL,
            shareLink: resolvedChannelShareLink() ?? channelShareLink
        )
    }

    var otherUserProfileData: ChatUserProfileData?
    /// Full GET users/{id} payload — passed into FollowersProfile to avoid UI flash.
    var otherUserDetails: OtherUserResponse?
    /// In-flight peer profile prefetch so header tap can await instead of opening empty.
    private var otherUserProfilePrefetchTask: Task<Void, Never>?
    private var isOpeningPeerProfile = false

    /// Seed used when pushing FollowersProfile from chat (no empty → filled flash).
    struct PeerProfileNavigationSeed {
        let user: UserRes
        let profile: ChatUserProfileData?
        let details: OtherUserResponse?
    }

    typealias SenderInfo = (fullName: String?, userName: String?, profilePicture: String?)
    private var senderCache: [String: SenderInfo] = [:]
    private var replyPreviewCacheById: [String: ConversationMessage] = [:]
    private var inFlightReplyPreviewFetchIds: Set<String> = []
    private var replyPreviewFetchCooldownUntil: [String: Date] = [:]
    private var inFlightScrollResolveIds: Set<String> = []

    var prefetchedLiveWindow: [ConversationMessage]? = nil
    var isPrefetchingLiveWindow = false

    func findSenderByUserId(_ userId: String) -> SenderInfo? {
        if let cached = senderCache[userId] { return cached }
        guard let msg = messages.first(where: { ($0.sender?.id ?? $0.senderId) == userId }) else { return nil }
        let info: SenderInfo = (
            msg.sender?.fullName ?? msg.sender?.userDetails?.dataValues?.fullName,
            msg.sender?.userName ?? msg.sender?.userDetails?.dataValues?.userName,
            msg.sender?.profilePicture ?? msg.sender?.userDetails?.dataValues?.profilePicture
        )
        senderCache[userId] = info
        return info
    }

    func resolvedDisplayName(for senderId: String) -> String {
        guard !senderId.isEmpty else { return "" }

        if let p = groupParticipants.first(where: { $0.userId == senderId || $0.id == senderId }) {
            return GroupParticipantDisplay.displayName(fullName: p.fullName, userName: p.userName, fallback: "")
        }

        if senderId == selectedUserChatID {
            let peer = headerUserData ?? user
            if let name = GroupParticipantDisplay.cleanName(peer?.fullName) { return name }
            if let name = GroupParticipantDisplay.cleanName(peer?.userName) { return name }
            if let name = GroupParticipantDisplay.cleanName(groupTitle) { return name }
        }

        if senderId == getCurrentUserId() {
            let me = userListViewModel.sessionManager?.user
                ?? sessionManager?.user
                ?? Container.sharedContainer.resolve(SessionManager.self)?.user
            if let name = GroupParticipantDisplay.cleanName(me?.fullName) { return name }
            if let name = GroupParticipantDisplay.cleanName(me?.userName) { return name }
        }

        if let info = findSenderByUserId(senderId) {
            if let name = GroupParticipantDisplay.cleanName(info.fullName) { return name }
            if let name = GroupParticipantDisplay.cleanName(info.userName) { return name }
        }
        return ""
    }

    /// Participants used for bubble/reply name resolution.
    /// For 1:1 chats, synthesizes peer + current user so reply previews don't show "Unknown".
    func participantsForMessageDisplay() -> [GroupParticipant] {
        if isGroupChat || isChannel {
            return groupParticipants
        }

        var result: [GroupParticipant] = []

        let peerId = selectedUserChatID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !peerId.isEmpty {
            let peer = headerUserData ?? user
            let resolved = resolvedDisplayName(for: peerId)
            result.append(
                GroupParticipant(
                    id: peerId,
                    userId: peerId,
                    role: "member",
                    userName: GroupParticipantDisplay.cleanName(peer?.userName) ?? resolved,
                    fullName: GroupParticipantDisplay.cleanName(peer?.fullName) ?? resolved,
                    profilePicture: peer?.profilePicture
                )
            )
        }

        let myId = getCurrentUserId().trimmingCharacters(in: .whitespacesAndNewlines)
        if !myId.isEmpty {
            let me = userListViewModel.sessionManager?.user
                ?? sessionManager?.user
                ?? Container.sharedContainer.resolve(SessionManager.self)?.user
            let resolved = resolvedDisplayName(for: myId)
            result.append(
                GroupParticipant(
                    id: myId,
                    userId: myId,
                    role: "member",
                    userName: GroupParticipantDisplay.cleanName(me?.userName) ?? resolved,
                    fullName: GroupParticipantDisplay.cleanName(me?.fullName) ?? resolved,
                    profilePicture: me?.profilePicture
                )
            )
        }

        return result
    }

    /// Rebuilds sender cache — called lazily, not on every message list update
    private var senderCacheNeedsRebuild = true

    /// Mark sender cache as stale so it rebuilds on next lookup
    func invalidateSenderCache() {
        senderCacheNeedsRebuild = true
    }

    func rebuildSenderCache() {
        guard senderCacheNeedsRebuild else { return }
        senderCacheNeedsRebuild = false
        senderCache.removeAll(keepingCapacity: true)
        for msg in messages {
            let senderId = msg.sender?.id ?? msg.senderId ?? ""
            guard !senderId.isEmpty, senderCache[senderId] == nil else { continue }
            senderCache[senderId] = (
                msg.sender?.fullName ?? msg.sender?.userDetails?.dataValues?.fullName,
                msg.sender?.userName ?? msg.sender?.userDetails?.dataValues?.userName,
                msg.sender?.profilePicture ?? msg.sender?.userDetails?.dataValues?.profilePicture
            )
        }
    }

    // Conversation presence polling timer (1-to-1 chats only)
    var conversationStatusTimer: Timer?
    var presenceReconnectObserver: NSObjectProtocol?
    var hasEmittedMarkSeen = false

    // Typing indicator timers
    var typingHideTimer: Timer?
    var typingKeepAliveTimer: Timer?
    var typingStopWorkItem: DispatchWorkItem?
    var isTyping = false

    /// `true` when the current conversation is a 1-to-1 direct chat.
    var isDirectChat: Bool {
        !isChannel && !isGroupChat
    }
    
    var pageSize: Int
    var currentPage: Int = 1
    var hasMorePages: Bool = true

    var isInitialLoad: Bool = true
    var initialScrollSettledAt: Date?
    private var isEnsuringConversation: Bool = false
    /// Completions waiting while a create-conversation request is already in flight.
    private var ensureConversationWaiters: [(Bool) -> Void] = []
    var hasPreloadedCachedMessages: Bool = false
    var hasInitialLoadStarted: Bool = false

    /// Duration (seconds) after initial scroll settles during which FRC view updates
    /// are suppressed to prevent the "animated top-to-bottom" transition on multi-page chats.
    private let initialSettlingDuration: TimeInterval = 3.0

    /// True during the initial settling window after messages first appear.
    var isInInitialSettlingWindow: Bool {
        guard let settledAt = initialScrollSettledAt else { return false }
        return Date().timeIntervalSince(settledAt) < initialSettlingDuration
    }

    /// Background tasks that must be cancelled on cleanup.
    var backgroundTasks: [String: Task<Void, Never>] = [:]

    var messageRetryAttempts: [String: Int] = [:]
    var activeMediaUploads: Set<String> = []
    @Published var mediaUploadTempIds: Set<String> = []
    var inFlightPollVotes: [String: Int] = [:]
    var pendingPollVoteWorkItem: [String: DispatchWorkItem] = [:]

    var lastLoadMoreTime: Date?
    let loadMoreCooldown: TimeInterval = 1.0

    /// Tracks recently seen pin system message IDs to deduplicate across socket events.
    var recentPinSystemMessageIds: Set<String> = []

    /// Pending pin state changes that have been applied in-memory but not yet written to CoreData.
    /// Applied over FRC results in silentSync to prevent the FRC race condition from reverting them.
    var pendingPinUpdates: [String: Bool] = [:]
    /// Pending delivery ticks (sent/delivered/seen) — FRC/CoreData races must not downgrade these.
    var pendingStatusUpdates: [String: MessageDeliveryStatus] = [:]
    var pendingDeletions: [String: ConversationMessage] = [:]

    var inFlightOlderBeforeDate: Date?

    var cancellables = Set<AnyCancellable>()
    var typingEventsCancellable: AnyCancellable?
    var isSyncingNewMessages = false
    var isPrefetchingOlderMessages = false
    var lastOlderPrefetchTime: Date?
    let olderPrefetchCooldown: TimeInterval = 1.2
    let isoFormatter: ISO8601DateFormatter

    // Debounced last-message update
    var lastMessageUpdateTimer: Timer?
    var lastMessageUpdatePending: ConversationMessage?
    
    init(userListViewModel: ChatUserListViewModel,
         conversationRepository: ConversationRepositoryAsync? = nil,
         messageRepository: MessageRepositoryAsync? = nil,
         messageService: ChatMessageServiceProtocol? = nil,
         audioService: ChatAudioServiceProtocol? = nil,
         socketService: ChatSocketServiceProtocol? = nil,
         mediaService: ChatMediaServiceProtocol? = nil,
         stateManager: ChatStateManagerProtocol? = nil,
         pageSize: Int = 40,
         initialChannelFollowersCount: Int? = nil,
         initialIsBlocked: Bool = false) {

        self.userListViewModel = userListViewModel
        if let initial = initialChannelFollowersCount {
            self.channelFollowersCount = initial
        }
        self.isBlocked = initialIsBlocked
        self.shouldShowBlockView = initialIsBlocked
        // Use repositories which conform to async protocols
        self.conversationRepository = conversationRepository ?? ConversationRepository()
        let resolvedMessageRepository = messageRepository ?? MessageRepository()
        self.messageRepository = resolvedMessageRepository
        
        let resolvedStateManager = stateManager ?? ChatStateManager()
        self.stateManager = resolvedStateManager
        
        guard let sessionManager = userListViewModel.sessionManager ?? Container.sharedContainer.resolve(SessionManager.self) else {
            fatalError("SessionManager dependency is missing; ensure it is registered in Container.sharedContainer")
        }
        self.sessionManager = sessionManager
        
        self.messageService = messageService ?? ChatMessageService(sessionManager: sessionManager, userListViewModel: userListViewModel)
        self.audioService = audioService ?? ChatAudioService()
        self.socketService = socketService ?? ChatSocketService(userListViewModel: userListViewModel)
        self.mediaService = mediaService ?? ChatMediaService(sessionManager: sessionManager)
        self.messageSyncCoordinator = ChatMessageSyncCoordinator(messageRepository: resolvedMessageRepository,
                                                                 stateManager: resolvedStateManager)
        self.toastMessage = nil // Initialize toastMessage

        self.pageSize = max(1, pageSize)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter

        // Set up delegate for block/delete callbacks
        userListViewModel.delegate = self as ChatUserListViewModelDelegate

        setupServiceBindings()
        observeSocketLifecycle()
        setupGroupMembersListener()
        setupConversationPresentationListener()
        PendingMessageStore.shared.clearStale()

        // FRC: single source of truth via CoreData (feature-flagged)
        if Self.useFRC {
            setupFRC()
        }
    }
    
    private func setupGroupMembersListener() {
        // Local add/remove/refresh from GroupDetailViewModel (and socket-driven list updates)
        NotificationCenter.default.publisher(for: NSNotification.Name("GroupMembersUpdated"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let groupId = notification.userInfo?["groupId"] as? String,
                      groupId == self.selectedId else { return }
                let action = notification.userInfo?["action"] as? String

                if action == "local_add" {
                    if let newParticipants = notification.userInfo?["newParticipants"] as? [GroupParticipant] {
                        for p in newParticipants {
                            if !self.groupParticipants.contains(where: { $0.userId == p.userId }) {
                                self.groupParticipants.append(p)
                            }
                        }
                        if let count = notification.userInfo?["membersCount"] as? Int {
                            self.participantsCount = count
                        } else {
                            self.participantsCount = self.groupParticipants.count
                        }
                        self.refreshHeaderData()
                    }
                } else if action == "removed" {
                    if let memberId = notification.userInfo?["memberId"] as? String {
                        self.groupParticipants.removeAll { $0.userId == memberId || $0.id == memberId }
                    }
                    if let count = notification.userInfo?["membersCount"] as? Int {
                        self.participantsCount = max(0, count)
                    } else if let count = self.participantsCount, count > 0 {
                        self.participantsCount = count - 1
                    } else {
                        self.participantsCount = self.groupParticipants.count
                    }
                    self.refreshHeaderData()
                    // Confirm with group detail API
                    self.loadGroupMembersFromAPI()
                } else if action == "refreshed" {
                    if let members = notification.userInfo?["members"] as? [GroupParticipant], !members.isEmpty {
                        self.groupParticipants = members
                    }
                    if let count = notification.userInfo?["membersCount"] as? Int {
                        self.participantsCount = max(count, self.groupParticipants.count)
                    } else {
                        self.participantsCount = self.groupParticipants.count
                    }
                    self.refreshHeaderData()
                } else {
                    self.loadGroupMembersFromAPI()
                }
            }
            .store(in: &cancellables)

        // Listen for channel-updated socket event to refresh header avatar/name while viewing a channel
        ChatSocketManager.shared.listenToEvent(SocketEvent.channelUpdated.rawValue) { [weak self] data in
            guard let self,
                  self.isChannel,
                  let ack = data.first as? [String: Any],
                  let chanDict = (ack["data"] as? [String: Any]) ?? (ack["channel"] as? [String: Any]),
                  let id = chanDict["id"] as? String ?? chanDict["_id"] as? String,
                  id == self.channelId else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let name = chanDict["name"] as? String
                let icon = chanDict["icon"] as? String
                let description = chanDict["description"] as? String
                let followersCount = chanDict["followersCount"] as? Int
                if let followersCount {
                    self.channelFollowersCount = followersCount
                }
                self.conversationPresentationStore.update(
                    conversationId: id,
                    title: name,
                    avatarURL: icon,
                    description: description
                )
                self.persistChannelDetails()
            }
        }

        NotificationCenter.default.publisher(for: .conversationIconUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let conversationId = notification.userInfo?["conversationId"] as? String,
                      let iconURL = notification.userInfo?["iconURL"] as? String,
                      !iconURL.isEmpty,
                      conversationId == self.selectedId || (self.isChannel && conversationId == self.channelId)
                else { return }
                self.conversationPresentationStore.update(
                    conversationId: conversationId,
                    avatarURL: iconURL
                )
                self.refreshHeaderData()
            }
            .store(in: &cancellables)

        // Listen for channel follow state changes to update follower count
        NotificationCenter.default.publisher(for: .channelFollowStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, self.isChannel else { return }
                let channelId = notification.userInfo?["channelId"] as? String
                guard channelId == self.channelId else { return }
                if let serverCount = notification.userInfo?["followersCount"] as? Int {
                    self.channelFollowersCount = serverCount
                } else {
                    let isFollowing = notification.userInfo?["isFollowing"] as? Bool ?? false
                    let current = self.channelFollowersCount ?? 0
                    self.channelFollowersCount = max(0, isFollowing ? current + 1 : current - 1)
                }
            }
            .store(in: &cancellables)
    }

    private func setupConversationPresentationListener() {
        conversationPresentationStore.$snapshots
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySharedConversationPresentationState()
            }
            .store(in: &cancellables)
    }

    func applySharedConversationPresentationState() {
        let ids = [selectedId, channelId].filter { !$0.isEmpty }
        guard let snapshot = conversationPresentationStore.latestSnapshot(for: ids) else { return }

        if let title = snapshot.title, !title.isEmpty {
            groupTitle = title
            if isChannel {
                channelName = title
            }
        }

        if let avatarURL = snapshot.avatarURL, !avatarURL.isEmpty {
            conversationAvatarURL = avatarURL
        }

        if isChannel, let description = snapshot.description {
            channelDescription = description
        }
    }
    
    deinit {
        cleanup()
    }
    
    func handleError(_ error: ChatError, context: String = "") {
        DispatchQueue.main.async {
            self.currentError = error
            self.errorMessage = error.localizedDescription
            self.canRetryLastError = error.isRetryable
            AppLogger.debug("ChatError [\(context)]: \(error.localizedDescription)")
        }
    }
    
    func clearError() {
        currentError = nil
        errorMessage = nil
        canRetryLastError = false
    }
    
    func retryLastAction() {
        clearError()
    }
    
    func startReply(to message: ConversationMessage) -> Bool {
        if(!isChannel) {
            // Already replying to this message — no-op
            if replyingToMessage?.id == message.id { return false }
            // Discard any competing actions — latest action wins
            cancelEdit()
            if selection.isSelectionMode { exitSelectionMode() }
            replyingToMessage = message
            return true
        }
        return false
    }
    
    func cancelReply() {
        replyingToMessage = nil
    }
    
    func startEdit(message: ConversationMessage) {
        // Discard any competing actions — latest action wins
        cancelReply()
        if selection.isSelectionMode { exitSelectionMode() }
        editingMessage = message
        editingMessageId = message.id
        editMessageText = message.content ?? ""
    }
    
    func cancelEdit() {
        editingMessage = nil
        editingMessageId = nil
        editMessageText = ""
    }
    
    // MARK: - Background Upload Observation

    private func observeBackgroundUploads() {
        BackgroundUploadService.shared.taskProgressChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tempId in
                guard let self, let status = BackgroundUploadService.shared.status(for: tempId) else {
                    self?.mediaUploadTempIds.remove(tempId)
                    return
                }
                let stillMapped = self.tempMessageMapping[tempId] != nil
                if case .failed = status {
                    if stillMapped {
                        self.markMessageAsFailed(tempId: tempId)
                    }
                    self.mediaUploadTempIds.remove(tempId)
                } else if status != .completed {
                    // Only show spinner while the optimistic bubble is still present
                    if stillMapped {
                        self.mediaUploadTempIds.insert(tempId)
                    } else {
                        self.mediaUploadTempIds.remove(tempId)
                    }
                } else {
                    self.mediaUploadTempIds.remove(tempId)
                }
            }
            .store(in: &cancellables)

        BackgroundUploadService.shared.uploadDidComplete
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }
                // Always clear spinner state, even if socket already replaced the temp bubble
                self.mediaUploadTempIds.remove(result.tempId)
                guard self.tempMessageMapping[result.tempId] != nil else { return }
                self.replaceTemporaryMessage(tempId: result.tempId, with: result.serverMessage)
                if self.lastFailedMessageId == result.tempId || self.currentError == .messageUploadFailed {
                    self.lastFailedMessageId = nil
                    self.currentError = nil
                    self.canRetryLastError = false
                }
            }
            .store(in: &cancellables)
    }

    private func setupServiceBindings() {
        Publishers.CombineLatest4(
            audioService.isRecording.removeDuplicates(),
            audioService.hasRecordedAudio.removeDuplicates(),
            audioService.recordingDuration.removeDuplicates(),
            audioService.liveWaveAmplitudes
        )
        .throttle(for: .milliseconds(60), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] (isRecording, hasRecorded, duration, amplitudes) in
            guard let self = self else { return }
            var state = self.audioRecording
            state.isRecordingAudio = isRecording
            state.hasRecordedAudio = hasRecorded
            state.recordingDuration = duration
            state.recordedAudioDuration = self.formatDuration(duration)
            state.liveWaveAmplitudes = amplitudes
            if hasRecorded && !isRecording && state.recordedWaveSeed == nil {
                state.recordedWaveSeed = UUID().uuidString
            }
            self.audioRecording = state
        }
        .store(in: &cancellables)
        
        stateManager.groupedMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] grouped in
                guard let self = self else { return }
                // Skip if groupedMessages was already set synchronously
                // (e.g. by applyInjectedMessages / displayInitialMessages)
                if self.groupedMessages == grouped { return }
                // When FRC is the source of truth, the stateManager may contain fewer
                // messages than the FRC (e.g. when the FRC fast-path was taken and
                // stateManager was never fully populated). Guard against accidentally
                // replacing the complete FRC-sourced list with a partial stateManager state.
                if Self.useFRC && self.pendingRemovalCount == 0 {
                    let currentCount = self.groupedMessages.reduce(0) { $0 + $1.messages.count }
                    let newCount = grouped.reduce(0) { $0 + $1.messages.count }
                    guard newCount >= currentCount else { return }
                }
                if self.pendingRemovalCount > 0 {
                    self.pendingRemovalCount -= 1
                }
                self.groupedMessages = grouped
                let flatMessages = grouped.flatMap { $0.messages }
                self.syncPollSelectionMap(from: flatMessages)
                self.handleMessageListUpdate(flatMessages)
            }
            .store(in: &cancellables)
        
        stateManager.isLoadingMessages
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isLoadingMessages = value
            }
            .store(in: &cancellables)
        
        socketService.messageReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleNewSocketMessage(message)
            }
            .store(in: &cancellables)

        socketService.messageAcknowledged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleMessageAcknowledgment(message)
            }
            .store(in: &cancellables)

        socketService.messageReactionUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.applyServerReactionUpdate(messageId: message.id, serverMessage: message)
            }
            .store(in: &cancellables)

        socketService.messageEdited
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleMessageEdited(message)
            }
            .store(in: &cancellables)

        socketService.messageTranslation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (message: ConversationMessage) in
                self?.handleMessageTranslation(message)
            }
            .store(in: &cancellables)

        socketService.messageDeleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleMessageDeleted(message)
            }
            .store(in: &cancellables)

        // Pin message real-time updates
        socketService.pinMessageUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.handlePinMessageUpdate(update)
            }
            .store(in: &cancellables)

        // Real-time message status updates (delivered / seen) for messages sent by the current user
        socketService.messageStatusUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.handleConversationMessageStatusUpdate(payload)
            }
            .store(in: &cancellables)
    }
    
    private func observeSocketLifecycle() {
        socketService.conversationDeleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationId in
                guard let self = self else { return }
                if conversationId == self.selectedId {
                    self.onConversationDeleted?()
                }
            }
            .store(in: &cancellables)
        

        socketService.conversationSettingsUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self = self else { return }
                // FE sample is flat `{ conversationId, isMuted }` — also accept nested `settings`.
                guard let parsed = SocketAckParser.conversationSettings(from: payload),
                      parsed.conversationId == self.selectedId else { return }
                if let blocked = SocketAckParser.boolValue(from: parsed.settings["isBlocked"]) {
                    self.applyBlockUIState(isBlocked: blocked)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ChatBlockStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let info = notification.userInfo ?? [:]
                if let cid = info["conversationId"] as? String, !cid.isEmpty {
                    guard cid == self.selectedId else { return }
                } else if let peerId = info["peerUserId"] as? String, !peerId.isEmpty {
                    let currentPeer = self.selectedUserChatID.isEmpty
                        ? (self.user?.userId ?? self.user?.id ?? "")
                        : self.selectedUserChatID
                    guard peerId == currentPeer else { return }
                } else {
                    return
                }
                if let blocked = info["isBlocked"] as? Bool {
                    self.applyBlockUIState(isBlocked: blocked)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .userBlocked)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let peerId = notification.object as? String,
                      !peerId.isEmpty else { return }
                let currentPeer = self.selectedUserChatID.isEmpty
                    ? (self.user?.userId ?? self.user?.id ?? "")
                    : self.selectedUserChatID
                guard peerId == currentPeer else { return }
                self.applyBlockUIState(isBlocked: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .userUnblocked)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let peerId = notification.object as? String,
                      !peerId.isEmpty else { return }
                let currentPeer = self.selectedUserChatID.isEmpty
                    ? (self.user?.userId ?? self.user?.id ?? "")
                    : self.selectedUserChatID
                guard peerId == currentPeer else { return }
                self.applyBlockUIState(isBlocked: false)
            }
            .store(in: &cancellables)

        socketService.forwardMessageAck
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                self?.handleForwardMessageAck(response)
            }
            .store(in: &cancellables)

        // Real-time conversation presence (1-to-1 only); update `userStatus` label in header
        socketService.conversationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statusText in
                guard let self = self, self.isDirectChat else { return }
                // Empty / privacy-hidden (nobody) → blank subtitle; name stays centered.
                self.userStatus = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .store(in: &cancellables)

        // MARK: - Message Status Updates (Real-time)
        MessageStatusManager.shared.onStatusChanged = { [weak self] messageId, newStatus in
            self?.handleMessageStatusUpdate(messageId: messageId, status: newStatus)
        }
        MessageStatusManager.shared.onMessageUpdated = { [weak self] message in
            self?.handleMessageStatusMessageUpdate(message)
        }

        // Channel: incoming messages and send acks
        socketService.channelMessageReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleIncomingChannelMessage(message)
            }
            .store(in: &cancellables)

        socketService.sendChannelMessageAck
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ack in
                self?.handleSendChannelMessageAck(ack)
            }
            .store(in: &cancellables)


        NotificationCenter.default.publisher(for: .chatSocketDidConnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.resetTimeoutsAfterReconnect()
                // Delta sync on reconnect — catches messages missed while disconnected
                guard self.hasInitialLoadStarted else { return }
                self.syncNewMessagesFromAPI()
                self.retryPendingMessagesAfterReconnect()
                self.retryFailedMessagesOnReconnect()
            }
            .store(in: &cancellables)
    }

    // MARK: - FRC Setup

    func reinitializeFRC() {
        messageFRC?.invalidate()
        messageFRC = nil
        guard Self.useFRC else { return }
        setupFRC()
    }

    private func setupFRC() {
        guard !selectedId.isEmpty else { return }
        let frc = ChatMessageFRC(
            conversationId: selectedId,
            context: CoreDataManager.shared.viewContext
        )
        frc.onMessagesChanged = { [weak self] groups in
            guard let self else { return }

            let filteredGroups: [MessageGroup]
            if self.locallyDeletedMessageIds.isEmpty {
                filteredGroups = groups
            } else {
                filteredGroups = groups.compactMap { group in
                    let msgs = group.messages.filter { !self.locallyDeletedMessageIds.contains($0.id) }
                    return msgs.isEmpty ? nil : MessageGroup(date: group.date, messages: msgs)
                }
            }

            let withPins = self.applyPendingPinUpdates(to: filteredGroups)
            let withStatus = self.applyPendingStatusUpdates(to: withPins)
            let correctedGroups = self.applyPendingDeletions(to: withStatus)

            let oldCount = self.groupedMessages.reduce(0) { $0 + $1.messages.count }
            let newCount = correctedGroups.reduce(0) { $0 + $1.messages.count }
            let oldLastId = self.groupedMessages.last?.messages.last?.id
            let newLastId = correctedGroups.last?.messages.last?.id

            if !self.tempMessageMapping.isEmpty {
                let flat = correctedGroups.flatMap { $0.messages }
                let existingIds = Set(flat.map { $0.id })
                let pendingToAdd = self.tempMessageMapping.values.filter { msg in
                    !existingIds.contains(msg.id)
                }
                var merged = flat
                if !pendingToAdd.isEmpty {
                    merged.append(contentsOf: pendingToAdd)
                    merged.sort { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
                }
                // Keep the highest tick we already know about (temp + pending + cache)
                merged = merged.map { self.messageWithBestKnownDeliveryStatus($0) }
                self.messages = merged
                self.stateManager.silentSync(merged)
                let newGroups = self.applyPendingDeletions(
                    to: self.applyPendingStatusUpdates(
                        to: self.stateManager.getGroupedMessagesSnapshot()
                    )
                )
                if self.groupedMessages != newGroups {
                    self.groupedMessages = newGroups
                    self.syncPollSelectionMap(from: newGroups.flatMap { $0.messages })
                }
                return
            }

            if oldCount == newCount, oldLastId == newLastId, oldLastId != nil {

                let flat = correctedGroups.flatMap { $0.messages }.map {
                    self.messageWithBestKnownDeliveryStatus($0)
                }
                self.messages = flat
                self.stateManager.silentSync(flat)
                if self.groupedMessages != correctedGroups {
                    self.groupedMessages = self.applyPendingStatusUpdates(to: correctedGroups)
                    self.syncPollSelectionMap(from: correctedGroups.flatMap { $0.messages })
                }
                return
            }

            if self.isInInitialSettlingWindow {
                let flat = correctedGroups.flatMap { $0.messages }.map {
                    self.messageWithBestKnownDeliveryStatus($0)
                }
                self.messages = flat
                self.stateManager.silentSync(flat)
                self.scheduleDeferredSettlingUpdate()
                AppLogger.debug("[ChatMessageFRC] suppressed view update during settling: old=\(oldCount) new=\(newCount)")
                return
            }

            let flat = correctedGroups.flatMap { $0.messages }.map {
                self.messageWithBestKnownDeliveryStatus($0)
            }
            self.messages = flat
            self.groupedMessages = self.applyPendingStatusUpdates(to: correctedGroups)
            self.stateManager.silentSync(flat)
        }
        frc.fetch()
        messageFRC = frc
        AppLogger.debug("[ChatMessageFRC] initialized for conversation=\(selectedId)")
    }

    private func scheduleDeferredSettlingUpdate() {
        guard backgroundTasks["_deferredSettling"] == nil else { return }
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.initialSettlingDuration ?? 3.0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                let groups = self.stateManager.getGroupedMessagesSnapshot()
                if self.groupedMessages != groups {
                    AppLogger.debug("[ChatMessageFRC] applying deferred settling update: \(groups.reduce(0) { $0 + $1.messages.count }) messages")
                    self.groupedMessages = groups
                }
            }
        }
        backgroundTasks["_deferredSettling"] = task
    }

    nonisolated private func cleanup() {
        MainActor.assumeIsolated {
            // Stop socket listening
            socketService.stopListening()

            // Stop conversation-status polling
            conversationStatusTimer?.invalidate()
            conversationStatusTimer = nil
            if let existing = presenceReconnectObserver {
                NotificationCenter.default.removeObserver(existing)
                presenceReconnectObserver = nil
            }

            // Cancel all background tasks (prevents timer stacking across navigations)
            backgroundTasks.values.forEach { $0.cancel() }
            backgroundTasks.removeAll()

            // Clear message status
            MessageStatusManager.shared.onStatusChanged = nil
            MessageStatusManager.shared.onMessageUpdated = nil

            // Stop audio services
            if audioRecording.isRecordingAudio || audioRecording.hasRecordedAudio {
                audioService.clearRecording()
            }
            audioService.stopRecordedAudio()
            if let playingId = audioPlayback.currentlyPlayingMessageId {
                audioService.stopMessageAudio(messageId: playingId)
            }

            // Clear state
            stateManager.clearMessages()

            // Invalidate FRC
            messageFRC?.invalidate()
            messageFRC = nil
            // Preserve temp messages that BackgroundUploadService is still working on
            let activeIds = BackgroundUploadService.shared.activeTaskIds(for: selectedId)
            tempMessageMapping = tempMessageMapping.filter { activeIds.contains($0.key) }
            mediaManager.clearCache()

            // Cancel all subscriptions (this is the most important)
            typingEventsCancellable?.cancel()
            typingEventsCancellable = nil
            cancellables.removeAll()
        }
    }

    // MARK: - Channel Handlers
    /// FE ChannelThreadPage `onNew`: append if new id; own sends may also arrive via socket after REST.
    private func handleIncomingChannelMessage(_ message: ConversationMessage) {
        guard isChannel else { return }
        let msgChannelId = message.channelId ?? ""
        guard msgChannelId.isEmpty || msgChannelId == channelId else { return }

        if tryMatchAndReplaceTemporaryMessage(with: message) {
            autoDownloadMediaIfNeeded(message)
            return
        }
        if !message.id.isEmpty, stateManager.messageById(message.id) != nil {
            stateManager.updateMessage(message)
            return
        }
        stateManager.addMessages([message])
        autoDownloadMediaIfNeeded(message)
        shouldAutoScroll = true

        let isFromSelf = (message.sender?.id ?? message.senderId) == getCurrentUserId()
        if !isFromSelf {
            markChannelAsRead(messageId: message.id)
        }
    }

    private func handleSendChannelMessageAck(_ ack: [String: Any]) {
        guard let ackData = ack["data"] as? [String: Any],
              let metaObj = ackData["metadata"] as? [String: Any],
              let clientTempId = metaObj["clientTempId"] as? String,
              tempMessageMapping[clientTempId] != nil else { return }

        var merged: [String: Any] = ackData
        if merged["channelId"] == nil {
            merged["channelId"] = channelId
        }
        // Channel messages only show pending → sent
        merged["status"] = "sent"
        merged["statuses"] = nil
        if (merged["sentAt"] as? String ?? "").isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            merged["sentAt"] = formatter.string(from: Date())
        }

        if let updated = ConversationMessage.fromDictionary(merged) {
            // Copy media files from tempId to serverId and update state
            replaceTemporaryMessage(tempId: clientTempId, with: updated)
        }
    }
    
    func handleMessageListUpdate(_ newMessages: [ConversationMessage]) {
        let previousLastId = messages.last?.id
        let wasEmpty = messages.isEmpty
        let previousCount = messages.count

        if previousCount == newMessages.count && previousLastId == newMessages.last?.id {
            let firstChanged = (newMessages.first?.id != messages.first?.id)
            let lastChanged = (newMessages.last?.updatedAt != messages.last?.updatedAt)
            if !firstChanged && !lastChanged {
                // Same-count update (edit, reaction, status) — check if any message actually changed
                var hasChange = false
                for (new, old) in zip(newMessages, messages) {
                    if new.content != old.content || new.isEdited != old.isEdited
                        || new.updatedAt != old.updatedAt || new.reactions != old.reactions
                        || new.poll != old.poll || new.status != old.status {
                        hasChange = true
                        break
                    }
                }
                if !hasChange { return }
            }
        }

        messages = newMessages
        senderCacheNeedsRebuild = true  // Mark dirty, rebuild lazily on first lookup

        guard let latestId = newMessages.last?.id else { return }

        if isInitialLoad {
            isInitialLoad = false
            initialScrollSettledAt = Date()

            return
        }

        if wasEmpty {
            triggerScrollToBottom(for: latestId)
            return
        }

        // Check if this is a pagination load or a new message
        let isNewMessage = newMessages.count > previousCount && newMessages.last?.id != previousLastId

        if isLoadingOlderMessages {
            // Don't scroll when loading older messages — preserve scroll position
            return
        }

        if let settledAt = initialScrollSettledAt,
           Date().timeIntervalSince(settledAt) < initialSettlingDuration {
            return
        }

        // Only scroll to bottom for new messages and only when showing the live tail
        // (not a pinned-message historical window — that window suppresses auto-scroll).
        if isNewMessage, let lastNew = newMessages.last, shouldAutoScrollForNewMessage(lastNew), !isInHistoricalWindow {
            triggerScrollToBottom(for: latestId)
        }
    }
    
    private func triggerScrollToBottom(for messageId: String) {
        pendingScrollToMessageId = messageId
    }
    
    private func shouldAutoScrollForNewMessage(_ message: ConversationMessage) -> Bool {
        if isLoadingOlderMessages { return false }
        return shouldAutoScroll
    }
    
    var recordedAudioDurationDisplay: String? {
        audioRecording.recordedAudioDuration
    }

    private func formatDuration(_ seconds: Int) -> String {
        guard seconds >= 0 else { return "00:00" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    func setInitialGroupMetadata(title: String, participants: [GroupParticipant], isParticipant: Bool, avatarUrl: String = "") {
        groupTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        groupParticipants = participants
        isGroupParticipant = isParticipant
        if !avatarUrl.isEmpty {
            conversationAvatarURL = avatarUrl
        } else if isChannel && !channelId.isEmpty {
            // Avatar wasn't passed (race: socket ack not yet received) — look up from CoreData cache
            Task { [weak self] in
                guard let self else { return }
                let cached = await ChannelRepository().getCachedChannels()
                if let match = cached.first(where: { $0.id == self.channelId }),
                   let icon = match.icon, !icon.isEmpty {
                    await MainActor.run { self.conversationAvatarURL = icon }
                }
            }
        }
    }
    
    func refreshHeaderData() {
        guard !selectedId.isEmpty else { return }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                guard let chat = try await self.conversationRepository?.getConversation(id: self.selectedId) else { return }

                if chat.isGroup {
                    self.updateGroupMetadata(from: chat)
                } else if let details = chat.getUserDetails() {
                    let shouldUpdateHeader = (self.headerUserData?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
                    (self.headerUserData?.userName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

                    if shouldUpdateHeader {
                        let user = UserRes(
                            id: nil,
                            userId: details.userId,
                            userName: details.userName,
                            fullName: details.fullName,
                            type: nil,
                            profilePicture: nil,
                            isPrivate: nil,
                            verified: nil,
                            profilePictureDetails: ProfilePictureDetails(filePath: details.profilePicture),
                            follower_profile: nil,
                            isFollowing: nil,
                            isSelected: nil, searchedAt: nil
                        )
                        await MainActor.run { self.headerUserData = user }
                    }
                }
            } catch {
                AppLogger.debug("refreshHeaderData: failed to resolve conversation metadata: \(error)")
            }
        }

        prefetchUserProfile()
    }

    /// Hydrate from `UserProfileCache` so navigation can reuse prior profile paints.
    private func hydrateOtherUserProfileFromCacheIfNeeded() {
        guard otherUserProfileData == nil else { return }
        let cachedUserId = resolvedPeerUserId()
        guard !cachedUserId.isEmpty,
              let cached = UserProfileCache.shared.get(forUserId: cachedUserId) else { return }
        otherUserProfileData = cached
        applyUserProfileToHeader(cached)
    }

    func resolvedPeerUserId() -> String {
        let candidates = [
            selectedUserChatID,
            headerUserData?.userId,
            headerUserData?.id,
            user?.userId,
            user?.id,
            otherUserProfileData?.userId,
            otherUserDetails?.userId
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func resolvedPeerUserName() -> String {
        let candidates = [
            headerUserData?.userName,
            user?.userName,
            otherUserProfileData?.userName,
            otherUserDetails?.userName
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    /// Warm peer profile while chat is open (presence + FollowersProfile seed).
    private func prefetchUserProfile() {
        guard groupParticipants.isEmpty, !isChannel else { return }
        hydrateOtherUserProfileFromCacheIfNeeded()
        // Already have a full seed — still refresh quietly in background if nothing in flight.
        guard otherUserProfilePrefetchTask == nil else { return }
        let peerId = resolvedPeerUserId()
        let peerName = resolvedPeerUserName()
        guard !peerId.isEmpty || !peerName.isEmpty else { return }
        // Skip network if we already have profile + details for this peer.
        if otherUserProfileData != nil, otherUserDetails != nil { return }

        otherUserProfilePrefetchTask = Task { [weak self] in
            await self?.fetchAndStoreOtherUserProfile(userId: peerId, userName: peerName)
            await MainActor.run { [weak self] in
                self?.otherUserProfilePrefetchTask = nil
            }
        }
    }

    /// Awaitable seed for opening FollowersProfile without flashing empty UI.
    @MainActor
    func ensureOtherUserProfileForNavigation() async -> PeerProfileNavigationSeed? {
        guard !isOpeningPeerProfile else { return nil }
        isOpeningPeerProfile = true
        defer { isOpeningPeerProfile = false }

        hydrateOtherUserProfileFromCacheIfNeeded()

        if otherUserProfileData == nil || otherUserDetails == nil {
            if let task = otherUserProfilePrefetchTask {
                await task.value
            } else {
                let peerId = resolvedPeerUserId()
                let peerName = resolvedPeerUserName()
                if !peerId.isEmpty || !peerName.isEmpty {
                    await fetchAndStoreOtherUserProfile(userId: peerId, userName: peerName)
                }
            }
            hydrateOtherUserProfileFromCacheIfNeeded()
        }

        guard let targetUser = headerUserData ?? user else { return nil }
        return PeerProfileNavigationSeed(
            user: targetUser,
            profile: otherUserProfileData,
            details: otherUserDetails
        )
    }

    private func fetchAndStoreOtherUserProfile(userId: String, userName: String) async {
        guard let sessionManager = userListViewModel.sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self) else { return }

        let trimmedId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty || !trimmedName.isEmpty else { return }

        do {
            // Prefer UUID path — avoids users/?q= search round-trip.
            let response: OtherUserResponse
            if !trimmedId.isEmpty {
                response = try await sessionManager.getUserById(trimmedId).value
            } else {
                response = try await sessionManager.getProfile(userName: trimmedName).value
            }
            applyOtherUserResponseToChat(response)
            AppLogger.debug("[ChatProfile] Prefetched profile for \(trimmedName.isEmpty ? trimmedId : trimmedName)")
        } catch {
            AppLogger.debug("[ChatProfile] Prefetch failed for \(trimmedName.isEmpty ? trimmedId : trimmedName): \(error)")
        }
    }

    /// Normalize NEW flat users/{id} into chat seed + header + cache.
    @MainActor
    private func applyOtherUserResponseToChat(_ response: OtherUserResponse) {
        otherUserDetails = response

        var profile = response.user_profile_data ?? ChatUserProfileData.from(otherUser: response)
        if let following = response.isFollowing {
            profile.isFollowing = following
        }
        if let ownerFollowing = response.isOwnerFollowingVisitor {
            profile.isOwnerFollowingVisitor = ownerFollowing
        }
        if response.isRequestedByMe == true
            || response.relationshipStatus?.lowercased() == "requested" {
            profile.isRequestedByMe = true
            profile.isFollowing = false
        }
        if let requestedToMe = response.isRequestedToMe {
            profile.isRequestedToMe = requestedToMe
        }
        if let blocked = response.isBlocked {
            profile.isBlock = blocked
        }
        if let blockedByOwner = response.isBlockedByOwner {
            profile.isBlockedByOwner = blockedByOwner
        }

        otherUserProfileData = profile
        if let uid = profile.userId ?? response.userId, !uid.isEmpty {
            UserProfileCache.shared.set(profile, forUserId: uid)
        }

        var updated = headerUserData ?? user ?? UserRes(
            id: nil, userId: nil, userName: nil, fullName: nil, link: nil, bio: nil, type: nil,
            profilePicture: nil, isPrivate: nil, verified: nil,
            profilePictureDetails: nil, follower_profile: nil, isFollowing: nil,
            isSelected: nil, searchedAt: nil
        )
        let resolvedId = response.userId ?? updated.userId ?? updated.id
        updated.id = resolvedId
        updated.userId = resolvedId
        if let name = response.fullName ?? response.displayName, !name.isEmpty {
            updated.fullName = name
        }
        if let name = response.userName, !name.isEmpty {
            updated.userName = name
        }
        updated.isPrivate = response.isPrivate ?? updated.isPrivate
        updated.verified = response.verified ?? updated.verified
        updated.isFollowing = profile.isFollowing
        updated.isOwnerFollowingVisitor = profile.isOwnerFollowingVisitor
        updated.isRequestedByMe = profile.isRequestedByMe
        updated.bio = response.bio ?? updated.bio
        if let pic = response.profilePictureDetails?.filePath ?? response.profilePicture, !pic.isEmpty {
            updated.profilePicture = pic
            updated.profilePictureDetails = ProfilePictureDetails(filePath: pic)
        }
        updated.user_profile_data = profile
        headerUserData = updated
        if user != nil {
            user = updated
        }

        if isDirectChat {
            applyPresenceFromUserDetails(response)
        }
    }
    
    // MARK: - Helpers

    func applyUserProfileToHeader(_ profileData: ChatUserProfileData) {
        guard !isGroupChat else { return }
        otherUserProfileData = profileData
        if let uid = profileData.userId {
            UserProfileCache.shared.set(profileData, forUserId: uid)
        }

        var updated = headerUserData ?? user ?? UserRes(
            id: nil, userId: nil, userName: nil, fullName: nil, link: nil, bio: nil, type: nil,
            profilePicture: nil, isPrivate: nil, verified: nil,
            profilePictureDetails: nil, follower_profile: nil, isFollowing: nil,
            isSelected: nil, searchedAt: nil
        )
        updated.userId = profileData.userId
        if let name = profileData.fullName, !name.isEmpty { updated.fullName = name }
        if let name = profileData.userName, !name.isEmpty { updated.userName = name }
        if let pic = profileData.profileImage, !pic.isEmpty {
            updated.profilePicture = pic
            updated.profilePictureDetails = ProfilePictureDetails(filePath: pic)
        }
        updated.verified = profileData.verified
        updated.isFollowing = profileData.isFollowing
        updated.isOwnerFollowingVisitor = profileData.isOwnerFollowingVisitor
        updated.bio = profileData.bio
        headerUserData = updated

        // Refresh my_contacts privacy once relationship is known
        let viewerIsContact = (profileData.isFollowing == true)
            || (profileData.isOwnerFollowingVisitor == true)
        socketService.updateViewerIsContact(viewerIsContact)
        if isDirectChat, !selectedUserChatID.isEmpty {
            socketService.emitSubscribePresence(userIds: [selectedUserChatID])
        }
    }

    private func applyPendingPinUpdates(to groups: [MessageGroup]) -> [MessageGroup] {
        guard !pendingPinUpdates.isEmpty else { return groups }
        return groups.map { group in
            MessageGroup(date: group.date, messages: group.messages.map { msg in
                guard let pendingState = pendingPinUpdates[msg.id] else { return msg }
                var corrected = msg
                corrected.isPinned = pendingState
                return corrected
            })
        }
    }

    /// Re-apply in-memory / cached ticks so FRC CoreData races cannot downgrade seen → delivered.
    func applyPendingStatusUpdates(to groups: [MessageGroup]) -> [MessageGroup] {
        groups.map { group in
            MessageGroup(
                date: group.date,
                messages: group.messages.map { messageWithBestKnownDeliveryStatus($0) }
            )
        }
    }

    func messageWithBestKnownDeliveryStatus(_ message: ConversationMessage) -> ConversationMessage {
        let current = MessageDeliveryStatus.from(
            status: message.status,
            sentAt: message.sentAt,
            deliveredAt: message.deliveredAt,
            seenAt: message.seenAt
        )
        var best = current
        if let pending = pendingStatusUpdates[message.id], pending > best {
            best = pending
        }
        let cached = MessageStatusManager.shared.status(for: message.id)
        if cached != .unknown, cached > best {
            best = cached
        }
        // Temp rows may be keyed separately from server id
        if let tempId = message.metadata?["clientTempId"]?.value as? String, !tempId.isEmpty {
            if let pending = pendingStatusUpdates[tempId], pending > best {
                best = pending
            }
            let tempCached = MessageStatusManager.shared.status(for: tempId)
            if tempCached != .unknown, tempCached > best {
                best = tempCached
            }
        }
        guard best > current, best != .unknown else { return message }
        return message.withStatus(best)
    }

    func registerPendingDeliveryStatus(_ status: MessageDeliveryStatus, for messageIds: [String]) {
        guard status != .unknown else { return }
        for id in messageIds where !id.isEmpty {
            let current = pendingStatusUpdates[id] ?? .unknown
            if status > current {
                pendingStatusUpdates[id] = status
            }
            MessageStatusManager.shared.cacheStatus(id, status: status)
        }
    }

    func applyPendingDeletions(to groups: [MessageGroup]) -> [MessageGroup] {
        guard !pendingDeletions.isEmpty else { return groups }
        return groups.map { group in
            MessageGroup(date: group.date, messages: group.messages.map { msg in
                guard let deleted = pendingDeletions[msg.id] else { return msg }
                return deleted
            })
        }
    }
    
    // MARK: - Pin Message Update Handler
    func handlePinMessageUpdate(_ update: PinMessageUpdate) {
        // Ignore pin events for other conversations (open chat / wrong room)
        if !update.conversationId.isEmpty, update.conversationId != selectedId {
            return
        }

        let stateMgr = stateManager
        let snapshot = stateMgr.getGroupedMessagesSnapshot().flatMap(\.messages)

        // Always clear every other in-memory pin when a new pin arrives (one-pin model).
        // Server may omit `unpinnedMessageIds`.
        let fallbackUnpinnedIds: [String]
        if update.isPinned {
            fallbackUnpinnedIds = snapshot.compactMap { msg in
                guard msg.id != update.messageId, msg.isPinned == true else { return nil }
                return msg.id
            }
        } else {
            fallbackUnpinnedIds = []
        }
        let idsToUnpin = Array(
            Set((update.unpinnedMessageIds + fallbackUnpinnedIds).filter { !$0.isEmpty && $0 != update.messageId })
        )

        // Update in-memory state for the pinned message
        if var msg = stateMgr.messageById(update.messageId) {
            msg.isPinned = update.isPinned
            stateMgr.updateMessage(msg)
        }

        // Unpin any previously pinned messages provided by server (or inferred fallback).
        for uid in idsToUnpin {
            if var msg = stateMgr.messageById(uid) {
                msg.isPinned = false
                stateMgr.updateMessage(msg)
            }
        }

        groupedMessages = stateMgr.getGroupedMessagesSnapshot()

        // Update banner: show pinned message or hide it
        if update.isPinned {
            if let live = stateMgr.messageById(update.messageId) {
                currentPinnedMessage = live
            } else {
                // Message not in memory yet — hydrate banner + pin flag from API
                refreshPinnedMessageFromAPI()
            }
        } else if currentPinnedMessage?.id == update.messageId {
            currentPinnedMessage = nil
        }
        handleMessageListUpdate(groupedMessages.flatMap(\.messages))

        let convIdForCache = update.conversationId.isEmpty ? selectedId : update.conversationId
        if !convIdForCache.isEmpty {
            ChatDataPreloader.shared.storePinState(for: convIdForCache, message: currentPinnedMessage)
        }

        // Register pending pin updates so the FRC callback cannot revert them before CoreData writes complete.
        pendingPinUpdates[update.messageId] = update.isPinned
        for uid in idsToUnpin { pendingPinUpdates[uid] = false }

        let pinnedMsgSnapshot = currentPinnedMessage  // capture before any async hop
        Task { [weak self] in
            guard let self else { return }
            let repo = messageRepository
            if update.isPinned {
                try? await repo.clearOtherPinnedMessages(
                    in: convIdForCache,
                    except: update.messageId
                )
            }
            // Pin: save full message object so CoreData always has it, then set the flag.
            if update.isPinned, let msg = pinnedMsgSnapshot ?? stateMgr.messageById(update.messageId) {
                try? await repo.saveMessages([msg], conversationId: convIdForCache)
                try? await repo.updateMessagePinStatus(id: update.messageId, isPinned: true)
            } else {
                try? await repo.updateMessagePinStatus(id: update.messageId, isPinned: update.isPinned)
            }
            for uid in idsToUnpin {
                try? await repo.updateMessagePinStatus(id: uid, isPinned: false)
            }
            // CoreData writes are done — remove pending overrides so FRC can manage pin state normally.
            await MainActor.run {
                self.pendingPinUpdates.removeValue(forKey: update.messageId)
                for uid in idsToUnpin { self.pendingPinUpdates.removeValue(forKey: uid) }
            }
        }
    }

    func setSelectedMessageId(_ messageId: String, force: Bool = false) {
        // Request a scroll to the message; highlighting will be applied after scroll completes
        if force {
            forceScrollToMessageId = messageId
        } else {
            pendingScrollToMessageId = messageId
        }
        if stateManager.messageById(messageId) == nil {
            ensureMessageLoadedForScroll(messageId, force: force)
        }
    }

    func refreshCurrentPinnedMessage() {
        Task { [weak self] in
            guard let self else { return }
            let pinned = try? await self.messageRepository.getPinnedMessage(for: self.selectedId)
            await MainActor.run {
                self.currentPinnedMessage = pinned
            }
        }
    }

    func message(byId id: String) -> ConversationMessage? {
        stateManager.messageById(id)
    }

    private func ensureMessageLoadedForScroll(_ messageId: String, force: Bool = false) {
        guard !messageId.isEmpty, !selectedId.isEmpty else { return }
        if inFlightScrollResolveIds.contains(messageId) { return }
        inFlightScrollResolveIds.insert(messageId)

        let conversationIdAtStart = selectedId

        Task { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor in
                    self.inFlightScrollResolveIds.remove(messageId)
                }
            }

            if self.stateManager.messageById(messageId) != nil { return }

            var targetMessage: ConversationMessage?
            do {
                targetMessage = try await self.messageRepository.getMessage(id: messageId)
            } catch {
                return
            }

            if targetMessage == nil {
                var anchorDate = self.parseISO8601Date(self.messages.first?.createdAt) ?? Date()
                var attempts = 0
                let maxAttempts = 8

                while attempts < maxAttempts, targetMessage == nil {
                    attempts += 1
                    do {
                        let response = try await self.messageService.loadMessagesBeforeAsync(
                            conversationId: conversationIdAtStart,
                            beforeDate: anchorDate.addingTimeInterval(0.001),
                            page: 1,
                            limit: self.pageSize
                        )

                        let batch = response.data.data.messages.filter { $0.isDeleted != true }
                        guard !batch.isEmpty else { break }

                        try? await self.messageRepository.saveMessages(batch, conversationId: conversationIdAtStart)
                        targetMessage = batch.first(where: { $0.id == messageId })

                        if targetMessage != nil { break }
                        if let oldestInBatch = batch.first,
                           let oldestDate = self.parseISO8601Date(oldestInBatch.createdAt) {
                            anchorDate = oldestDate
                        } else {
                            break
                        }
                    } catch {
                        break
                    }
                }
            }

            guard let target = targetMessage else { return }
            guard self.selectedId == conversationIdAtStart else { return }

            let anchorDate = self.parseISO8601Date(target.createdAt) ?? Date()
            let halfWindow = max(12, self.pageSize / 2)

            async let olderTask = try? self.messageRepository.getMessagesBefore(
                conversationId: conversationIdAtStart,
                beforeDate: anchorDate,
                limit: halfWindow
            )
            async let newerTask = try? self.messageRepository.getMessagesAfter(
                conversationId: conversationIdAtStart,
                afterDate: anchorDate,
                limit: halfWindow
            )

            let older = await olderTask ?? []
            let newer = await newerTask ?? []

            var window = older + [target] + newer
            guard !window.isEmpty else { return }

            var seen = Set<String>()
            window = window.filter { msg in
                guard !msg.id.isEmpty else { return false }
                return seen.insert(msg.id).inserted
            }
            window.sort { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
            let normalizedWindow = window

            await MainActor.run {
                guard self.selectedId == conversationIdAtStart else { return }
                self.stateManager.setMessages(normalizedWindow)
                let groups = self.stateManager.getGroupedMessagesSnapshot()
                self.groupedMessages = groups
                self.handleMessageListUpdate(groups.flatMap { $0.messages })
                if force {
                    self.forceScrollToMessageId = messageId
                } else {
                    self.pendingScrollToMessageId = messageId
                }
                self.isInHistoricalWindow = true
                AppLogger.debug(
                    "[HistoricalWindow] entered conversation=\(conversationIdAtStart) targetId=\(messageId) windowCount=\(normalizedWindow.count) oldestId=\(normalizedWindow.first?.id ?? "nil") newestId=\(normalizedWindow.last?.id ?? "nil")"
                )
                self.prefetchLiveWindowIfNeeded()
            }
        }
    }

    func replyPreviewMessage(for parentMessage: ConversationMessage) -> ConversationMessage? {
        guard let replyRef = parentMessage.replyToId,
              let replyId = replyRef.id,
              !replyId.isEmpty else { return nil }

        if let live = stateManager.messageById(replyId) {
            return live
        }

        if let cached = replyPreviewCacheById[replyId] {
            return cached
        }

        return synthesizeReplyPreviewMessage(from: replyRef, fallbackCreatedAt: parentMessage.createdAt)
    }

    func warmReplyPreviewIfNeeded(for parentMessage: ConversationMessage) {
        guard let replyRef = parentMessage.replyToId,
              let replyId = replyRef.id,
              !replyId.isEmpty,
              !selectedId.isEmpty else { return }

        if stateManager.messageById(replyId) != nil || replyPreviewCacheById[replyId] != nil {
            return
        }

        if let cooldown = replyPreviewFetchCooldownUntil[replyId], cooldown > Date() {
            return
        }

        if inFlightReplyPreviewFetchIds.contains(replyId) {
            return
        }

        inFlightReplyPreviewFetchIds.insert(replyId)

        Task { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor in
                    self.inFlightReplyPreviewFetchIds.remove(replyId)
                }
            }

            let localMessage: ConversationMessage?
            do {
                localMessage = try await self.messageRepository.getMessage(id: replyId)
            } catch {
                localMessage = nil
            }

            if let local = localMessage {
                await MainActor.run {
                    self.replyPreviewCacheById[replyId] = local
                    self.replyPreviewFetchCooldownUntil.removeValue(forKey: replyId)
                    self.objectWillChange.send()
                }
                return
            }

            let anchorDate = self.parseISO8601Date(parentMessage.createdAt) ?? Date()

            do {
                let response = try await self.messageService.loadMessagesBeforeAsync(
                    conversationId: self.selectedId,
                    beforeDate: anchorDate.addingTimeInterval(0.001),
                    page: 1,
                    limit: self.pageSize
                )

                let fetched = response.data.data.messages.filter { $0.isDeleted != true }
                if !fetched.isEmpty {
                    try? await self.messageRepository.saveMessages(fetched, conversationId: self.selectedId)
                }

                let target = fetched.first(where: { $0.id == replyId })
                await MainActor.run {
                    if let target {
                        self.replyPreviewCacheById[replyId] = target
                        self.replyPreviewFetchCooldownUntil.removeValue(forKey: replyId)
                    } else {
                        self.replyPreviewCacheById[replyId] = self.synthesizeReplyPreviewMessage(from: replyRef, fallbackCreatedAt: parentMessage.createdAt)
                        self.replyPreviewFetchCooldownUntil[replyId] = Date().addingTimeInterval(30)
                    }
                    self.objectWillChange.send()
                }
            } catch {
                await MainActor.run {
                    self.replyPreviewCacheById[replyId] = self.synthesizeReplyPreviewMessage(from: replyRef, fallbackCreatedAt: parentMessage.createdAt)
                    self.replyPreviewFetchCooldownUntil[replyId] = Date().addingTimeInterval(30)
                    self.objectWillChange.send()
                }
            }
        }
    }

    private func synthesizeReplyPreviewMessage(from replyRef: ReplyToMessage, fallbackCreatedAt: String?) -> ConversationMessage {
        let sender = ConversationMessageSender(
            id: replyRef.sender.id,
            userName: replyRef.sender.userName,
            fullName: replyRef.sender.fullName,
            profilePicture: nil,
            userDetails: nil
        )

        return ConversationMessage(
            id: replyRef.id ?? UUID().uuidString,
            conversationId: selectedId,
            sender: sender,
            type: replyRef.type,
            messageType: replyRef.type,
            content: replyRef.content,
            media: replyRef.media,
            thumbnail: replyRef.thumbnail,
            serverLocation: replyRef.location,
            createdAt: fallbackCreatedAt ?? "",
            poll: replyRef.poll
        )
    }

    private func parseISO8601Date(_ dateString: String?) -> Date? {
        guard let dateString, !dateString.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
    
    func getSelectedPollOptionId(for messageId: String) -> String? {
        return pollSelectionMap[messageId]
    }
    
    func setSelectedPollOptionId(for messageId: String, optionId: String?) {
        if let optionId = optionId {
            pollSelectionMap[messageId] = optionId
        } else {
            pollSelectionMap.removeValue(forKey: messageId)
        }
    }

    func syncPollSelectionMap(from messages: [ConversationMessage]) {
        let currentUserId = getCurrentUserId()
        guard !currentUserId.isEmpty else { return }
        for message in messages {
            guard let poll = message.poll, !message.id.isEmpty else { continue }
            let ids = poll.resolvedMyOptionIds(currentUserId: currentUserId)
            if let first = ids.first {
                if pollSelectionMap[message.id] != first {
                    pollSelectionMap[message.id] = first
                }
            }
        }
    }
    
    
    private func updateGroupMetadata(from chat: ChatMessageRow) {
        let mappedParticipants = mapGroupParticipants(chat.participants)
        let resolvedTitle = chat.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiCount = chat.participantsCount ?? 0
        let resolvedCount = max(apiCount, mappedParticipants.count)

        AppLogger.debug("[GroupDetail] members=\(mappedParticipants.count) participantsCount=\(resolvedCount) title=\(resolvedTitle)")

        DispatchQueue.main.async {
            if !mappedParticipants.isEmpty {
                self.groupParticipants = mappedParticipants
            }

            // Always prefer live API count (FE: conv.participantsCount)
            if resolvedCount > 0 {
                self.participantsCount = resolvedCount
            }

            if !resolvedTitle.isEmpty {
                self.groupTitle = resolvedTitle
            } else if self.groupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.groupTitle = ChatStrings.chat_groupChat.localizedString()
            }

            if let participation = chat.isGroupParticipant, participation {
                self.isGroupParticipant = true
            } else if chat.deletedAt != nil {
                self.isGroupParticipant = false
            } else if chat.isGroup, self.isGroupParticipant == false {
                self.isGroupParticipant = true
            }

            if let avatar = chat.avatar, !avatar.isEmpty {
                self.conversationAvatarURL = avatar
            }

            self.applySharedConversationPresentationState()
        }
    }
    
    private func mapGroupParticipants(_ participants: [Participant]?) -> [GroupParticipant] {
        guard let participants = participants else {
            return []
        }

        let result = participants.compactMap { participant -> GroupParticipant? in
            guard let userId = participant.userId ?? participant.user?.userId ?? participant.user?.id ?? participant.id,
                  participant.isActive != false else {
                return nil
            }

            let details = participant.user?.userDetails?.first
            // Never fall back to userId for display — that shows UUIDs in the UI
            let userName = GroupParticipantDisplay.cleanName(
                details?.userName
                    ?? participant.user?.username
            )
            let fullName = GroupParticipantDisplay.cleanName(
                details?.fullName
                    ?? participant.user?.fullName
            ) ?? userName
            let profilePicture = details?.profilePictureDetails?.filePath
                ?? details?.profilePicture
                ?? participant.user?.profileImage
            let isVerified = participant.resolvedIsVerified

            return GroupParticipant(
                id: participant.id ?? userId,
                userId: userId,
                role: participant.role ?? "member",
                userName: userName ?? "",
                fullName: fullName ?? "",
                profilePicture: profilePicture,
                isVerified: isVerified
            )
        }

        return result
    }
    
    // MARK: - Conversation Creation
    func ensureConversationReady(completion: @escaping (Bool) -> Void) {
        if !selectedId.isEmpty {
            completion(true)
            return
        }

        // New Chat opens ensure in parallel with messaging/calls — wait instead of failing.
        if isEnsuringConversation {
            ensureConversationWaiters.append(completion)
            return
        }

        guard !selectedUserChatID.isEmpty else {
            completion(false)
            return
        }
        guard let session = userListViewModel.sessionManager
                ?? sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self) else {
            AppLogger.debug("ensureConversationReady: SessionManager missing")
            completion(false)
            return
        }

        isEnsuringConversation = true

        Task { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            do {
                // POST /chat/conversations { type: "direct", participantIds }
                let dict = try await self.createDirectConversationAsync(
                    session: session,
                    participantId: self.selectedUserChatID
                )
                let newId = Self.conversationId(fromCreateResponse: dict)
                let conversation = self.buildNewConversation(newId)
                await MainActor.run {
                    self.selectedId = newId
                    if !newId.isEmpty {
                        ChatNotificationState.shared.activeConversationId = newId
                        ChatSocketManager.shared.joinConversationRoom(newId)
                    } else {
                        AppLogger.debug("ensureConversationReady: missing id in response keys=\(dict.keys.sorted())")
                    }
                    if let conversation = conversation {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ChatConversationUpsert"),
                            object: nil,
                            userInfo: ["conversation": conversation]
                        )
                        Task {
                            try? await self.conversationRepository?.saveConversation(conversation)
                        }
                    }
                    self.finishEnsureConversation(success: !newId.isEmpty, primary: completion)
                }
            } catch {
                AppLogger.debug("Failed to create conversation: \(error)")
                await MainActor.run {
                    self.finishEnsureConversation(success: false, primary: completion)
                }
            }
        }
    }

    private static func conversationId(fromCreateResponse response: [String: Any]) -> String {
        if let id = response["id"] as? String, !id.isEmpty { return id }
        if let id = response["conversationId"] as? String, !id.isEmpty { return id }
        if let data = response["data"] as? [String: Any] {
            if let id = data["id"] as? String, !id.isEmpty { return id }
            if let id = data["conversationId"] as? String, !id.isEmpty { return id }
            if let conversation = data["conversation"] as? [String: Any] {
                if let id = conversation["id"] as? String, !id.isEmpty { return id }
                if let id = conversation["conversationId"] as? String, !id.isEmpty { return id }
            }
        }
        if let conversation = response["conversation"] as? [String: Any] {
            if let id = conversation["id"] as? String, !id.isEmpty { return id }
            if let id = conversation["conversationId"] as? String, !id.isEmpty { return id }
        }
        return ""
    }

    private func finishEnsureConversation(success: Bool, primary: @escaping (Bool) -> Void) {
        isEnsuringConversation = false
        let waiters = ensureConversationWaiters
        ensureConversationWaiters.removeAll()
        primary(success)
        waiters.forEach { $0(success) }
    }

    @discardableResult
    private func buildNewConversation(_ conversationId: String) -> ChatMessageRow? {
        guard !conversationId.isEmpty, !selectedUserChatID.isEmpty else { return nil }
        let otherUser = user ?? headerUserData
        let currentUserId = getCurrentUserId()

        let otherUserDetail = UserDetail(
            userName: otherUser?.userName,
            fullName: otherUser?.fullName,
            profilePicture: otherUser?.profilePictureDetails?.filePath ?? otherUser?.profilePicture,
            profilePictureDetails: otherUser?.profilePictureDetails
        )
        let otherParticipant = Participant(
            id: nil,
            conversationId: conversationId,
            userId: selectedUserChatID,
            role: nil,
            joinedAt: nil,
            leftAt: nil,
            isActive: true,
            createdAt: nil,
            updatedAt: nil,
            user: ParticipantUser(id: selectedUserChatID, userDetails: [otherUserDetail], isOnline: nil)
        )

        let currentUser = userListViewModel.sessionManager?.user
        let currentUserDetail = UserDetail(
            userName: currentUser?.userName,
            fullName: currentUser?.fullName,
            profilePicture: currentUser?.profilePictureDetails?.filePath ?? currentUser?.profilePicture,
            profilePictureDetails: currentUser?.profilePictureDetails
        )
        let currentUserParticipant = Participant(
            id: nil,
            conversationId: conversationId,
            userId: currentUserId,
            role: nil,
            joinedAt: nil,
            leftAt: nil,
            isActive: true,
            createdAt: nil,
            updatedAt: nil,
            user: ParticipantUser(id: currentUserId, userDetails: [currentUserDetail], isOnline: nil)
        )

        var conversation = ChatMessageRow()
        conversation.id = conversationId
        conversation.type = "direct"
        conversation.participants = [currentUserParticipant, otherParticipant]
        return conversation
    }

    /// `POST /chat/conversations` — `{ type: "direct", participantIds: [peer] }`
    private func createDirectConversationAsync(
        session: SessionManager,
        participantId: String
    ) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            session.createChatConversation(
                participantIds: [participantId],
                type: "direct"
            )
            .subscribe(onSuccess: { dict in
                continuation.resume(returning: dict)
            }, onFailure: { error in
                continuation.resume(throwing: error)
            })
        }
    }
    
    /// Share-card preflight — succeeds only when the viewer can access the entity.
    enum SharedEntityKind {
        case post
        case reel
        case vibe
    }

    func fetchSharedEntity(
        id: String,
        kind: SharedEntityKind,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.failure(APIError.apiError("Shared posts are not supported in FlirtTime")))
    }
    
}

// MARK: - AudioManagerContext Conformance
extension ChatDetailViewModel: AudioManagerContext { }


// MARK: - MediaManagerContext Conformance
extension ChatDetailViewModel: MediaManagerContext { }
