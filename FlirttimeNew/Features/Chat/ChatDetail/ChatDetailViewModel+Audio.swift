//
//  ChatDetailViewModel+Audio.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import Foundation
import AVFoundation

extension ChatDetailViewModel {

    func sendAudioMessage() {
        guard !isBlocked, !shouldShowBlockView else {
            handleError(.userBlockedError, context: "sendAudioMessage.blocked")
            return
        }
        audioManager.sendAudioMessage()
    }

    func startRecording() {
        audioManager.startRecording()
    }

    func stopRecording() {
        audioManager.stopRecording()
    }

    func playRecordedAudio() {
        audioManager.playRecordedAudio()
    }

    func stopRecordedAudio() {
        audioManager.stopRecordedAudio()
    }

    func stopMessageAudio() {
        // Placeholder for compatibility with legacy UI hooks
    }

    func startAudioRecording() {
        audioManager.startRecording()
    }

    func stopAudioRecording() {
        audioManager.stopRecording()
    }

    func cancelAudioRecordingAndDiscard() {
        audioManager.cancelAudioRecordingAndDiscard()
    }

    func deleteRecordedAudio() {
        audioManager.deleteRecordedAudio()
    }

    func discardRecording() {
        audioManager.cancelAudioRecordingAndDiscard()
    }

    func pauseRecordedAudio() {
        audioManager.pauseRecordedAudio()
    }

    func resumeRecordedAudio() {
        audioManager.resumeRecordedAudio()
    }

    func toggleRecordedAudioPlayback() {
        let state = audioRecording
        if state.isPlayingRecordedAudio && !state.isRecordedAudioPaused {
            pauseRecordedAudio()
        } else if state.isRecordedAudioPaused {
            resumeRecordedAudio()
        } else {
            playRecordedAudio()
        }
    }

    func sendRecordedAudio() {
        guard !isBlocked, !shouldShowBlockView else {
            handleError(.userBlockedError, context: "sendRecordedAudio.blocked")
            return
        }
        audioManager.sendRecordedAudio()
    }

    func toggleMessageAudio(for message: ConversationMessage) {
        audioManager.toggleMessageAudio(for: message)
    }

    func playMessageAudio(messageId: String) {
        audioManager.playMessageAudio(messageId: messageId)
    }

    func stopMessageAudio(messageId: String) {
        audioManager.stopMessageAudio(messageId: messageId)
    }

    func isPlaying(message: ConversationMessage) -> Bool {
        return audioManager.isPlaying(message: message)
    }

    func progress(for message: ConversationMessage) -> Double {
        return audioManager.progress(for: message)
    }
}
