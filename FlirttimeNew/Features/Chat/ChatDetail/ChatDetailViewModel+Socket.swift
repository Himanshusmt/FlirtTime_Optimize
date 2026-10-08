//
//  ChatDetailViewModel+Socket.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import Foundation
import Combine

extension ChatDetailViewModel {

    func startSocketListening() {
        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "chat-detail-start")
        socketService.startListening()
        typingEventsCancellable?.cancel()
        subscribeToTypingEvents()
    }

    func stopSocketListening() {
        socketService.stopListening()
        stopTypingHideTimer()
        typingKeepAliveTimer?.invalidate()
        typingKeepAliveTimer = nil
        typingStopWorkItem?.cancel()
        typingStopWorkItem = nil
        typingEventsCancellable?.cancel()
        typingEventsCancellable = nil
    }

    func startUserStatusEmitting() {
        if selectedId.isEmpty {
            ensureConversationReady { [weak self] success in
                guard let self = self, success else { return }
                self.socketService.emitUserStatus(status: "online", conversationId: self.selectedId, userId: self.getCurrentUserId())
                self.startConversationStatusPolling()
            }
        } else {
            socketService.emitUserStatus(status: "online", conversationId: selectedId, userId: getCurrentUserId())
            startConversationStatusPolling()
        }
    }

    func stopUserStatusEmitting() {
        stopConversationStatusPolling()
    }

    // MARK: - Conversation Status (1-to-1 chats)

    func startConversationStatusPolling() {
        stopConversationStatusPolling()
        guard isDirectChat else { return }

        // FE: subscribePresence([peerId]) via presence:get; realtime via presence:update.
        // Do NOT call OLD chat:conversation:status:get — on NEW backend it returns empty
        // privacy payloads and clears the subtitle after a real presence:update.
        let peerId = selectedUserChatID
        if !peerId.isEmpty {
            socketService.setOtherUserId(peerId)
            socketService.emitSubscribePresence(userIds: [peerId])
            // Seed from list presence cache immediately
            if ChatListSocketService.shared.onlineUserIds.contains(peerId),
               userStatus.isEmpty {
                userStatus = ChatStrings.chat_online.localizedString()
            }
        }

        // Re-ask presence after socket reconnect
        if let existing = presenceReconnectObserver {
            NotificationCenter.default.removeObserver(existing)
            presenceReconnectObserver = nil
        }
        presenceReconnectObserver = NotificationCenter.default.addObserver(
            forName: .chatSocketDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isDirectChat else { return }
            let peer = self.selectedUserChatID
            guard !peer.isEmpty else { return }
            self.socketService.setOtherUserId(peer)
            self.socketService.emitSubscribePresence(userIds: [peer])
        }
    }

    private func stopConversationStatusPolling() {
        conversationStatusTimer?.invalidate()
        conversationStatusTimer = nil
        if let existing = presenceReconnectObserver {
            NotificationCenter.default.removeObserver(existing)
            presenceReconnectObserver = nil
        }
    }

    // MARK: - Typing Indicator
    func userDidType() {
        let conversationId = selectedId
        let userId = getCurrentUserId()
        guard !conversationId.isEmpty, !userId.isEmpty else { return }

        typingStopWorkItem?.cancel()

        if !isTyping {
            isTyping = true
            socketService.emitTyping(conversationId: conversationId, userId: userId)
            startTypingKeepAlive(conversationId: conversationId, userId: userId)
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isTyping = false
            self.typingKeepAliveTimer?.invalidate()
            self.typingKeepAliveTimer = nil
            self.socketService.emitStopTyping(conversationId: conversationId, userId: userId)
        }

        typingStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func startTypingKeepAlive(conversationId: String, userId: String) {
        typingKeepAliveTimer?.invalidate()
        typingKeepAliveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isTyping else {
                    self?.typingKeepAliveTimer?.invalidate()
                    return
                }
                self.socketService.emitTyping(conversationId: conversationId, userId: userId)
            }
        }
    }

    private func subscribeToTypingEvents() {
        typingEventsCancellable = socketService.typingReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.handleReceivedTyping(payload)
            }
    }

    private func handleReceivedTyping(_ payload: TypingPayload) {
        // Ignore events for other conversations
        guard payload.conversationId == selectedId else { return }
        // Ignore own typing events
        guard payload.userId != getCurrentUserId() else { return }

        if payload.isTyping {
            typingIndicator = TypingIndicatorState(
                isTyping: true,
                senderName: payload.senderName.isEmpty ? nil : payload.senderName,
                senderId: payload.userId
            )
            scheduleTypingHide()
        } else {
            stopTypingHideTimer()
            typingIndicator = TypingIndicatorState()
        }
    }

    private func scheduleTypingHide() {
        stopTypingHideTimer()
        typingHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.typingIndicator = TypingIndicatorState()
        }
    }

    private func stopTypingHideTimer() {
        typingHideTimer?.invalidate()
        typingHideTimer = nil
    }

    func clearTypingIndicator() {
        stopTypingHideTimer()
        typingIndicator = TypingIndicatorState()
    }

    func userStoppedTyping() {
        typingStopWorkItem?.cancel()
        typingStopWorkItem = nil
        typingKeepAliveTimer?.invalidate()
        typingKeepAliveTimer = nil
        guard isTyping else { return }
        isTyping = false
        let conversationId = selectedId
        let userId = getCurrentUserId()
        guard !conversationId.isEmpty, !userId.isEmpty else { return }
        socketService.emitStopTyping(conversationId: conversationId, userId: userId)
    }
}
