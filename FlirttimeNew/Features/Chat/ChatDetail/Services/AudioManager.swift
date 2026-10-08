//
//  AudioManager.swift
//  FlirttimeNew
//

import Foundation
import AVFoundation
import Combine
import Swinject
import RxSwift

// MARK: - Context Protocol

@MainActor
protocol AudioManagerContext: AnyObject {
    var selectedId: String { get }
    var isChannel: Bool { get }
    var channelId: String { get }
    var stateManager: ChatStateManagerProtocol { get }
    var tempMessageMapping: [String: ConversationMessage] { get set }
    var isoFormatter: ISO8601DateFormatter { get }
    var userListViewModel: ChatUserListViewModel { get }
    var messageService: ChatMessageServiceProtocol { get }
    var audioRecording: AudioRecordingState { get set }
    var audioPlayback: AudioPlaybackState { get set }
    var isAudioUploading: Bool { get set }
    var shouldAutoScroll: Bool { get set }
    var messages: [ConversationMessage] { get }
    var cancellables: Set<AnyCancellable> { get set }
    var replyingToMessage: ConversationMessage? { get set }

    func getCurrentUserId() -> String
    func handleError(_ error: ChatError, context: String)
    func markMessageAsFailed(tempId: String)
    func scheduleFailureTimeout(for tempId: String)
    func resolvedDisplayName(for senderId: String) -> String
    func setCachedMediaData(for messageId: String, data: Data)
    func getFileSize(for url: URL) -> String
    func ensureConversationReady(completion: @escaping (Bool) -> Void)
    func replaceTemporaryMessage(tempId: String, with serverMessage: ConversationMessage)
}

// MARK: - Audio Manager

@MainActor
final class AudioManager {

    private weak var context: AudioManagerContext?
    private let audioService: ChatAudioServiceProtocol
    private var playbackCancellables = Set<AnyCancellable>()
    private var messagePlaybackCancellable: AnyCancellable?

    init(context: AudioManagerContext, audioService: ChatAudioServiceProtocol) {
        self.context = context
        self.audioService = audioService
    }

    // MARK: - Send Audio

    func sendAudioMessage() {
        guard let ctx = context else { return }
        guard let audioPath = audioService.stopRecording() else { return }
        ctx.isAudioUploading = true

        let audioURL = URL(fileURLWithPath: audioPath)
        guard let audioData = try? Data(contentsOf: audioURL) else {
            ctx.handleError(.audioRecordingFailed, context: "sendAudio.readAudioData")
            return
        }

        let fileSize = ctx.getFileSize(for: audioURL)
        let tempId = UUID().uuidString
        let replyToId = ctx.replyingToMessage?.id

        let audioDuration: Double = {
            if audioService.lastRecordedDuration > 0.05 {
                return audioService.lastRecordedDuration
            }
            // AVAudioPlayer is more reliable than sync AVAsset.duration for local m4a
            if let player = try? AVAudioPlayer(contentsOf: audioURL), player.duration > 0.05 {
                return player.duration
            }
            let assetSeconds = getAudioDuration(from: audioURL)
            if assetSeconds > 0.05 { return assetSeconds }
            return 0
        }()
        AppLogger.debug("Audio duration calculated: \(audioDuration) seconds (lastRecorded=\(audioService.lastRecordedDuration))")

        let storageResult = MediaStorageManager.shared.saveMedia(
            data: audioData,
            messageId: tempId,
            type: .audio
        )

        guard case .success(let localURL) = storageResult else {
            ctx.handleError(.mediaUploadFailed, context: "sendAudio.saveToDocuments")
            return
        }

        AppLogger.debug("Saved audio to Documents: \(tempId) (\(MediaStorageManager.shared.formatBytes(Int64(audioData.count))))")

        let filename = "audio_\(Date().timeIntervalSince1970).m4a"
        var metadata: [String: Any] = [
            "filename": filename,
            "filesize": "\(fileSize)",
            "clientTempId": tempId,
            // Store numeric duration so display helpers don't rely on string parsing
            "audio_duration": audioDuration,
            "audioDuration": audioDuration,
            "waveSeed": tempId
        ]
        if let replyToId = replyToId {
            metadata["reply_to_id"] = replyToId
        }

        var optimisticDict: [String: Any] = [
            "id": tempId,
            "conversationId": ctx.selectedId,
            "content": localURL.absoluteString,
            "messageType": "audio",
            "senderId": ctx.getCurrentUserId(),
            "createdAt": ctx.isoFormatter.string(from: Date()),
            "updatedAt": ctx.isoFormatter.string(from: Date()),
            "isEdited": false,
            "isDeleted": false,
            "status": "sending",
            "localMediaURL": localURL.absoluteString,
            "isTemporary": true,
            "metadata": metadata,
            "media": [[
                "id": tempId,
                "url": localURL.absoluteString,
                "type": "audio",
                "fileName": filename,
                "fileSize": fileSize,
                "duration": audioDuration
            ] as [String: Any]]
        ]
        if let r = ctx.replyingToMessage {
            let senderId = r.sender?.id ?? r.senderId ?? ""
            let resolvedName = ctx.resolvedDisplayName(for: senderId)
            let fullName = r.sender?.fullName ?? r.sender?.userDetails?.dataValues?.fullName ?? (resolvedName.contains(" ") ? resolvedName : "")
            let userName = r.sender?.userName ?? r.sender?.userDetails?.dataValues?.userName ?? (resolvedName.contains(" ") ? "" : resolvedName)
            let resolvedFullName = fullName.isEmpty ? resolvedName : fullName
            let resolvedUserName = userName.isEmpty ? resolvedName : userName
            optimisticDict["replyToId"] = [
                "id": r.id ?? "",
                "content": r.content ?? "",
                "type": r.messageType ?? r.type ?? "text",
                "sender": [
                    "id": senderId,
                    "userName": resolvedUserName,
                    "fullName": resolvedFullName
                ] as [String: Any]
            ] as [String: Any]
        }

        if let optimistic = ConversationMessage.fromDictionary(optimisticDict) {
            ctx.stateManager.addMessages([optimistic])
            ctx.tempMessageMapping[tempId] = optimistic
            PendingMessageStore.shared.save(tempId: tempId, message: optimistic, conversationId: ctx.selectedId)

            ctx.setCachedMediaData(for: tempId, data: audioData)
            ctx.shouldAutoScroll = true

            ctx.scheduleFailureTimeout(for: tempId)
        }

        audioService.clearRecording()
        var hiddenState = ctx.audioRecording
        hiddenState.isRecordingAudio = false
        hiddenState.hasRecordedAudio = false
        hiddenState.recordedAudioDuration = nil
        hiddenState.recordedAudioProgress = 0
        hiddenState.isPlayingRecordedAudio = false
        hiddenState.isRecordedAudioPaused = false
        hiddenState.recordedWaveSeed = nil
        ctx.audioRecording = hiddenState

        // Upload via NEW media/uploads (purpose: chat, kind: audio) → mediaId → REST send
        uploadChatAudioAndSend(
            tempId: tempId,
            audioData: audioData,
            filename: filename,
            filesize: fileSize,
            replyToId: replyToId,
            metadata: metadata
        )
    }

    func retryAudioSend(tempId: String, message: ConversationMessage) {
        guard let ctx = context else { return }
        let contentPath = message.content ?? ""
        let metadata = extractMetadata(from: message, tempId: tempId)

        // Prefer re-send with existing mediaId
        if let mediaId = message.metadata?["mediaId"]?.value as? String, !mediaId.isEmpty {
            finalizeAudioSend(
                tempId: tempId,
                displayURL: contentPath,
                mediaId: mediaId,
                filename: metadata["filename"] as? String ?? "voice.m4a",
                filesize: metadata["filesize"] as? String ?? "",
                replyToId: message.replyToId?.id,
                metadata: metadata
            )
            return
        }

        let localAudioURL = MediaStorageManager.shared.getMediaURL(messageId: tempId, type: .audio)
            ?? URL(string: contentPath)
        guard let localURL = localAudioURL,
              let audioData = try? Data(contentsOf: localURL) else {
            ctx.markMessageAsFailed(tempId: tempId)
            return
        }
        ctx.isAudioUploading = true
        let filename = metadata["filename"] as? String ?? "audio_\(Date().timeIntervalSince1970).m4a"
        let filesize = metadata["filesize"] as? String ?? "\(audioData.count)"
        uploadChatAudioAndSend(
            tempId: tempId,
            audioData: audioData,
            filename: filename,
            filesize: filesize,
            replyToId: message.replyToId?.id,
            metadata: metadata
        )
    }

    private func uploadChatAudioAndSend(
        tempId: String,
        audioData: Data,
        filename: String,
        filesize: String,
        replyToId: String?,
        metadata: [String: Any]
    ) {
        guard let ctx = context,
              let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else {
            context?.isAudioUploading = false
            context?.markMessageAsFailed(tempId: tempId)
            return
        }

        _ = sessionManager.uploadViaMediaUploadsSession(
            data: audioData,
            purpose: "chat",
            kind: "audio",
            contentType: "audio/mp4",
            fileName: filename
        )
        .subscribe(
            onSuccess: { [weak self] (mediaId: String) in
                DispatchQueue.main.async {
                    guard let self, let ctx = self.context else { return }
                    ctx.isAudioUploading = false
                    var meta = metadata
                    meta["mediaId"] = mediaId
                    self.finalizeAudioSend(
                        tempId: tempId,
                        displayURL: mediaId,
                        mediaId: mediaId,
                        filename: filename,
                        filesize: filesize,
                        replyToId: replyToId,
                        metadata: meta
                    )
                }
            },
            onFailure: { [weak self] (error: Error) in
                DispatchQueue.main.async {
                    guard let self, let ctx = self.context else { return }
                    ctx.isAudioUploading = false
                    ctx.markMessageAsFailed(tempId: tempId)
                    ctx.handleError(.mediaUploadFailed, context: "sendAudio.upload")
                    AppLogger.debug("sendAudio upload error: \(error.localizedDescription)")
                }
            }
        )
    }

    private func extractMetadata(from message: ConversationMessage, tempId: String) -> [String: Any] {
        var metadata: [String: Any] = [:]
        for (key, value) in message.metadata ?? [:] {
            metadata[key] = value.value
        }
        metadata["clientTempId"] = tempId
        if let replyId = message.replyToId?.id { metadata["reply_to_id"] = replyId }
        return metadata
    }

    private func finalizeAudioSend(tempId: String,
                                   displayURL: String,
                                   mediaId: String,
                                   filename: String,
                                   filesize: String,
                                   replyToId: String?,
                                   metadata: [String: Any]) {
        guard let ctx = context else { return }

        if let temp = ctx.tempMessageMapping[tempId] {
            let messageDict: [String: Any] = [
                "id": temp.id ?? tempId,
                "conversationId": temp.conversationId ?? ctx.selectedId,
                "content": displayURL,
                "messageType": temp.messageType ?? temp.type ?? "audio",
                "senderId": temp.sender?.id ?? ctx.getCurrentUserId(),
                "createdAt": temp.createdAt ?? ctx.isoFormatter.string(from: Date()),
                "updatedAt": temp.updatedAt ?? ctx.isoFormatter.string(from: Date()),
                "isEdited": temp.isEdited ?? false,
                "isDeleted": temp.isDeleted ?? false,
                "status": "sending",
                "localMediaURL": temp.content ?? "",
                "displayURL": displayURL,
                "isTemporary": true,
                "metadata": metadata
            ]

            if let updatedMessage = ConversationMessage.fromDictionary(messageDict) {
                ctx.stateManager.replaceMessage(tempId: tempId, with: updatedMessage)
                ctx.tempMessageMapping[tempId] = updatedMessage
            }
        }

        if ctx.isChannel {
            guard let session = Container.sharedContainer.resolve(SessionManager.self) else {
                ctx.markMessageAsFailed(tempId: tempId)
                ctx.handleError(.audioRecordingFailed, context: "sendAudio")
                return
            }
            // FE: POST chat/channels/messages
            _ = session.sendChannelChatMessage(
                channelId: ctx.channelId,
                body: nil,
                type: "audio",
                mediaIds: [mediaId],
                clientMessageId: tempId,
                replyToId: replyToId
            )
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] serverMessage in
                    guard let self, let ctx = self.context else { return }
                    var msg = serverMessage
                    var meta = msg.metadata ?? [:]
                    if meta["clientTempId"] == nil {
                        meta["clientTempId"] = AnyCodable(tempId)
                        msg.metadata = meta
                    }
                    ctx.replaceTemporaryMessage(tempId: tempId, with: msg)
                },
                onFailure: { [weak self] _ in
                    guard let ctx = self?.context else { return }
                    ctx.markMessageAsFailed(tempId: tempId)
                    ctx.handleError(.audioRecordingFailed, context: "sendAudio")
                }
            )
        } else {
            let started = ctx.messageService.sendViaREST(
                conversationId: ctx.selectedId,
                type: "audio",
                body: nil as String?,
                mediaIds: [mediaId],
                location: nil as [String: Any]?,
                poll: nil as [String: Any]?,
                clientMessageId: tempId,
                replyToId: replyToId
            ) { [weak self] result in
                guard let self, let ctx = self.context else { return }
                switch result {
                case .success(let serverMessage):
                    ctx.replaceTemporaryMessage(tempId: tempId, with: serverMessage)
                case .failure:
                    ctx.markMessageAsFailed(tempId: tempId)
                    ctx.handleError(.audioRecordingFailed, context: "sendAudio")
                }
            }
            if !started {
                ctx.markMessageAsFailed(tempId: tempId)
                ctx.handleError(.audioRecordingFailed, context: "sendAudio")
            }
        }

        // Clear reply state after sending
        ctx.replyingToMessage = nil
    }

    // MARK: - Recording Controls

    func startRecording() {
        audioService.startRecording()
    }

    func stopRecording() {
        _ = audioService.stopRecording()
    }

    func playRecordedAudio() {
        audioService.playRecordedAudio()
        bindRecordedPlaybackProgress()
    }

    func stopRecordedAudio() {
        audioService.stopRecordedAudio()
    }

    func pauseRecordedAudio() {
        audioService.pauseRecordedAudio()
        if let ctx = context {
            var state = ctx.audioRecording
            state.isRecordedAudioPaused = true
            ctx.audioRecording = state
        }
    }

    func resumeRecordedAudio() {
        audioService.resumeRecordedAudio()
        if let ctx = context {
            var state = ctx.audioRecording
            state.isRecordedAudioPaused = false
            ctx.audioRecording = state
        }
    }

    private func bindRecordedPlaybackProgress() {
        playbackCancellables.removeAll()
        guard let service = audioService as? ChatAudioService else { return }
        service.$recordedPlaybackProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self, let ctx = self.context else { return }
                var state = ctx.audioRecording
                state.recordedAudioProgress = progress
                if !state.isRecordedAudioPaused {
                    state.isPlayingRecordedAudio = true
                }
                ctx.audioRecording = state
            }
            .store(in: &playbackCancellables)

        service.$isRecordedPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self, let ctx = self.context else { return }
                var state = ctx.audioRecording
                state.isPlayingRecordedAudio = playing
                if !playing {
                    state.isRecordedAudioPaused = false
                    state.recordedAudioProgress = 0
                }
                ctx.audioRecording = state
            }
            .store(in: &playbackCancellables)

        service.$isRecordedPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                guard let self, let ctx = self.context else { return }
                var state = ctx.audioRecording
                state.isRecordedAudioPaused = paused
                ctx.audioRecording = state
            }
            .store(in: &playbackCancellables)
    }

    func cancelAudioRecordingAndDiscard() {
        discardRecording()
    }

    func deleteRecordedAudio() {
        discardRecording()
    }

    func discardRecording() {
        guard let ctx = context else { return }
        _ = audioService.stopRecording()

        if ctx.audioRecording.isPlayingRecordedAudio {
            audioService.stopRecordedAudio()
        }

        audioService.clearRecording()
        var state = ctx.audioRecording
        state.recordedAudioDuration = nil
        state.recordedAudioProgress = 0
        state.isPlayingRecordedAudio = false
        state.isRecordedAudioPaused = false
        state.recordedWaveSeed = nil
        ctx.audioRecording = state

        AppLogger.debug("Audio recording discarded and cleaned up")
    }

    func sendRecordedAudio() {
        AppLogger.debug("Send recorded audio called")
        sendAudioMessage()
    }

    // MARK: - Message Audio Playback

    func toggleMessageAudio(for message: ConversationMessage) {
        let messageId = message.id.isEmpty ? message.stableId : message.id
        guard !messageId.isEmpty else { return }
        let stableId = message.stableId

        if let currentId = context?.audioPlayback.currentlyPlayingMessageId,
           context?.audioPlayback.isCurrentMessage(id: messageId, stableId: stableId) == true {
            if context?.audioPlayback.isPaused == true {
                resumeMessageAudio(messageId: currentId)
            } else {
                pauseMessageAudio(messageId: currentId)
            }
        } else if let currentId = context?.audioPlayback.currentlyPlayingMessageId {
            stopMessageAudio(messageId: currentId)
            playMessageAudio(messageId: messageId)
        } else {
            playMessageAudio(messageId: messageId)
        }
    }

    func playMessageAudio(messageId: String) {
        guard let ctx = context else { return }

        guard let message = ctx.messages.first(where: {
            $0.id == messageId || $0.stableId == messageId
        }) else {
            AppLogger.debug("playMessageAudio: message not found for id \(messageId)")
            return
        }

        let playbackId = message.id.isEmpty ? message.stableId : message.id
        let stableId = message.stableId

        let audioURL: URL? = {
            if let local = localAudioFileURL(for: message) {
                return local
            }
            if let resolved = message.resolvedMediaURL, !resolved.isFileURL {
                return resolved
            }
            if let urlString = message.media?.first?.url,
               urlString.lowercased().hasPrefix("http"),
               let url = URL(string: urlString) {
                return url
            }
            if let content = message.content,
               content.lowercased().hasPrefix("http"),
               let url = URL(string: content) {
                return url
            }
            return nil
        }()

        guard let audioURL else {
            AppLogger.debug("playMessageAudio: could not resolve URL for message \(playbackId)")
            ctx.handleError(.audioPlaybackFailed, context: "playMessageAudio")
            return
        }

        let metadataDuration = audioDurationSeconds(from: message) ?? 0
        ctx.audioPlayback.isPaused = false
        ctx.audioPlayback.currentlyPlayingMessageId = playbackId
        ctx.audioPlayback.currentlyPlayingStableId = stableId
        ctx.audioPlayback.currentTime = 0
        ctx.audioPlayback.duration = metadataDuration
        ctx.audioPlayback.playbackProgressByMessageId[playbackId] = 0
        if !stableId.isEmpty {
            ctx.audioPlayback.playbackProgressByMessageId[stableId] = 0
        }

        messagePlaybackCancellable?.cancel()
        messagePlaybackCancellable = audioService.playMessageAudio(messageId: playbackId, audioURL: audioURL)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self, let ctx = self.context else { return }
                let stillThisMessage = ctx.audioPlayback.currentlyPlayingMessageId == playbackId
                    || ctx.audioPlayback.currentlyPlayingStableId == stableId
                ctx.audioPlayback.playbackProgressByMessageId[playbackId] = nil
                ctx.audioPlayback.playbackProgressByMessageId[stableId] = nil
                guard stillThisMessage else { return }
                ctx.audioPlayback.currentTime = 0
                if case .finished = completion {
                    ctx.audioPlayback.currentlyPlayingMessageId = nil
                    ctx.audioPlayback.currentlyPlayingStableId = nil
                    ctx.audioPlayback.isPaused = false
                    ctx.audioPlayback.duration = metadataDuration
                }
            }, receiveValue: { [weak self] progress in
                guard let self = self, let ctx = self.context else { return }
                var duration = metadataDuration
                var currentTime = progress * max(duration, 0.001)
                if let service = self.audioService as? ChatAudioService {
                    if service.lastPlaybackDuration > 0.05 {
                        duration = service.lastPlaybackDuration
                    }
                    currentTime = service.lastPlaybackCurrentTime
                }
                ctx.audioPlayback.duration = duration
                ctx.audioPlayback.currentTime = currentTime
                ctx.audioPlayback.playbackProgressByMessageId[playbackId] = progress
                if !stableId.isEmpty {
                    ctx.audioPlayback.playbackProgressByMessageId[stableId] = progress
                }
            })

        AppLogger.debug("Playing audio for message: \(playbackId) -> \(audioURL)")
    }

    func pauseMessageAudio(messageId: String) {
        guard let ctx = context else { return }
        audioService.pauseMessageAudio(messageId: messageId)
        ctx.audioPlayback.isPaused = true
        AppLogger.debug("Paused audio for message: \(messageId)")
    }

    func resumeMessageAudio(messageId: String) {
        guard let ctx = context else { return }
        ctx.audioPlayback.isPaused = false
        audioService.resumeMessageAudio(messageId: messageId)
        AppLogger.debug("Resumed audio for message: \(messageId)")
    }

    func stopMessageAudio(messageId: String) {
        guard let ctx = context else { return }
        audioService.stopMessageAudio(messageId: messageId)
        let stableId = ctx.audioPlayback.currentlyPlayingStableId
        ctx.audioPlayback.playbackProgressByMessageId[messageId] = nil
        if let stableId {
            ctx.audioPlayback.playbackProgressByMessageId[stableId] = nil
        }
        ctx.audioPlayback.currentTime = 0
        if ctx.audioPlayback.currentlyPlayingMessageId == messageId
            || ctx.audioPlayback.currentlyPlayingStableId == messageId {
            ctx.audioPlayback.currentlyPlayingMessageId = nil
            ctx.audioPlayback.currentlyPlayingStableId = nil
            ctx.audioPlayback.isPaused = false
        }
        AppLogger.debug("Stopping audio for message: \(messageId)")
    }

    // MARK: - Query Helpers

    func isPlaying(message: ConversationMessage) -> Bool {
        guard context?.audioPlayback.isCurrentMessage(id: message.id, stableId: message.stableId) == true else {
            return false
        }
        return context?.audioPlayback.isPaused != true
    }

    func progress(for message: ConversationMessage) -> Double {
        context?.audioPlayback.progress(id: message.id, stableId: message.stableId) ?? 0.0
    }

    // MARK: - Private Helpers

    private func getAudioDuration(from url: URL) -> Double {
        if let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 {
            let seconds = player.duration
            if !seconds.isNaN && !seconds.isInfinite {
                return seconds
            }
        }

        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        let seconds = CMTimeGetSeconds(duration)

        if seconds.isNaN || seconds.isInfinite || seconds < 0 {
            AppLogger.debug("Invalid audio duration calculated, returning 0")
            return 0
        }

        return seconds
    }
}
