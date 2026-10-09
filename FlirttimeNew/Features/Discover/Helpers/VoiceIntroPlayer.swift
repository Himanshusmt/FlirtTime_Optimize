//
//  VoiceIntroPlayer.swift
//  FlirttimeNew
//
//  Plays one voice introduction at a time. Never starts on its own; playback is always user initiated.
//

import AVFoundation

final class VoiceIntroPlayer: NSObject {

    static let shared = VoiceIntroPlayer()

    /// Posted on the main queue; `object` is the player. Read `playingProfileID` and `progress` from it.
    static let stateDidChange = Notification.Name("VoiceIntroPlayerStateDidChange")

    private(set) var playingProfileID: Int?
    private(set) var progress: Double = 0
    private var player: AVPlayer?
    private var timeObserver: Any?
    private let synthesizer = AVSpeechSynthesizer()
    private var progressTimer: Timer?
    private var startedAt: Date?
    private var duration: TimeInterval = 0

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ intro: VibeVoiceIntro, profileID: Int) {
        if playingProfileID == profileID {
            stop()
        } else {
            play(intro, profileID: profileID)
        }
    }

    func play(_ intro: VibeVoiceIntro, profileID: Int) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        playingProfileID = profileID
        duration = intro.duration

        if let url = intro.audioURL {
            let player = AVPlayer(url: url)
            self.player = player
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self, let item = player.currentItem else { return }
                let total = item.duration.seconds.isFinite ? item.duration.seconds : self.duration
                let progress = total > 0 ? time.seconds / total : 0
                if progress >= 1 {
                    self.stop()
                } else {
                    self.notify(progress: progress)
                }
            }
            player.play()
        } else {
            let utterance = AVSpeechUtterance(string: intro.transcript)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            synthesizer.speak(utterance)
            startedAt = Date()
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let startedAt = self.startedAt, self.duration > 0 else { return }
                self.notify(progress: min(Date().timeIntervalSince(startedAt) / self.duration, 0.99))
            }
        }
        notify(progress: 0)
    }

    func stop() {
        guard playingProfileID != nil else { return }
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        progressTimer?.invalidate()
        progressTimer = nil
        startedAt = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        playingProfileID = nil
        notify(progress: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func notify(progress: Double) {
        self.progress = progress
        NotificationCenter.default.post(name: VoiceIntroPlayer.stateDidChange, object: self)
    }
}

extension VoiceIntroPlayer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.stop()
        }
    }
}
