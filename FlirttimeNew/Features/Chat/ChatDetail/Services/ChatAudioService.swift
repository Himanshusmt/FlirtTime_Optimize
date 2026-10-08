//
//  ChatAudioService.swift
//  FlirttimeNew
//
//  Created by Awais on 25/09/25.
//

import Foundation
import AVFoundation
import Combine

protocol ChatAudioServiceProtocol {
    var isRecording: AnyPublisher<Bool, Never> { get }
    var hasRecordedAudio: AnyPublisher<Bool, Never> { get }
    var recordingDuration: AnyPublisher<Int, Never> { get }
    var liveWaveAmplitudes: AnyPublisher<[CGFloat], Never> { get }
    var lastRecordedDuration: Double { get }

    func startRecording()
    func stopRecording() -> String?
    func playRecordedAudio()
    func pauseRecordedAudio()
    func resumeRecordedAudio()
    func stopRecordedAudio()
    func playMessageAudio(messageId: String, audioURL: URL) -> AnyPublisher<Double, Never>
    func pauseMessageAudio(messageId: String)
    func resumeMessageAudio(messageId: String)
    func stopMessageAudio(messageId: String)
    func clearRecording()
}

class ChatAudioService: NSObject, ChatAudioServiceProtocol {

    static let shared = ChatAudioService()

    // MARK: - Published Properties
    @Published private var _isRecording: Bool = false
    @Published private var _hasRecordedAudio: Bool = false
    @Published private var _recordingDuration: Int = 0
    @Published private var _liveWaveAmplitudes: [CGFloat] = []
    @Published private(set) var recordedPlaybackProgress: Double = 0
    @Published private(set) var isRecordedPlaying: Bool = false
    @Published private(set) var isRecordedPaused: Bool = false

    var isRecording: AnyPublisher<Bool, Never> { $_isRecording.eraseToAnyPublisher() }
    var hasRecordedAudio: AnyPublisher<Bool, Never> { $_hasRecordedAudio.eraseToAnyPublisher() }
    var recordingDuration: AnyPublisher<Int, Never> { $_recordingDuration.eraseToAnyPublisher() }
    var liveWaveAmplitudes: AnyPublisher<[CGFloat], Never> { $_liveWaveAmplitudes.eraseToAnyPublisher() }

    // MARK: - Private Properties
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var waveformTimer: Timer?
    private var recordingSession: AVAudioSession?
    private var recordedAudioURL: URL?
    private var messageAudioPlayers: [String: AVAudioPlayer] = [:]
    private var playbackTimers: [String: Timer] = [:]
    private var recordedPlaybackTimer: Timer?
    private var currentlyPlayingMessageId: String?
    private(set) var lastRecordedDuration: Double = 0
    private(set) var lastPlaybackDuration: Double = 0
    private(set) var lastPlaybackCurrentTime: Double = 0

    // Active playback subject for pause/resume
    private var activePlaybackSubject: PassthroughSubject<Double, Never>?

    struct MessagePlaybackSnapshot {
        let messageId: String
        let progress: Double
        let duration: Double
        let currentTime: Double
        let isPlaying: Bool
    }

    func activePlaybackSnapshot() -> MessagePlaybackSnapshot? {
        guard let id = currentlyPlayingMessageId,
              let player = messageAudioPlayers[id] else { return nil }
        var duration = player.duration
        if duration.isNaN || duration.isInfinite || duration <= 0.05 {
            duration = lastPlaybackDuration
        }
        let currentTime = player.currentTime
        let progress = duration > 0.05 ? min(1, max(0, currentTime / duration)) : 0
        return MessagePlaybackSnapshot(
            messageId: id,
            progress: progress,
            duration: duration,
            currentTime: currentTime,
            isPlaying: player.isPlaying
        )
    }

    override init() {
        super.init()
        setupAudioSession()
    }

    deinit {
        stopRecording()
        stopRecordedAudio()
        cleanupAudioResources()
    }

    // MARK: - Private Methods
    private func setupAudioSession() {
        recordingSession = AVAudioSession.sharedInstance()
        do {
            try recordingSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try recordingSession?.setActive(true)
            AppLogger.debug("Audio session setup complete - category: playAndRecord, mode: default")
        } catch {
            AppLogger.debug("Failed to setup audio session: \(error)")
        }
    }

    private func configureAudioSessionForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            AppLogger.debug("Failed to configure audio session for playback: \(error)")
        }
    }

    private func cleanupAudioResources() {
        recordingTimer?.invalidate()
        waveformTimer?.invalidate()
        recordedPlaybackTimer?.invalidate()
        playbackTimers.values.forEach { $0.invalidate() }
        playbackTimers.removeAll()
        messageAudioPlayers.removeAll()
        audioPlayer = nil
        audioRecorder = nil
    }

    // MARK: - Recording Methods
    func startRecording() {
        guard !_isRecording else { return }

        do {
            try recordingSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try recordingSession?.setActive(true)
        } catch {
            AppLogger.debug("Failed to restore recording session: \(error)")
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recorded_audio_\(Date().timeIntervalSince1970).m4a")

        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            guard audioRecorder?.record() == true else {
                AppLogger.debug("AVAudioRecorder.record() returned false — check microphone permission or audio session state")
                audioRecorder = nil
                return
            }

            recordedAudioURL = audioFilename
            _isRecording = true
            _recordingDuration = 0
            lastRecordedDuration = 0
            _liveWaveAmplitudes = []

            startRecordingTimer()
            startWaveformTimer()
        } catch {
            AppLogger.debug("Recording failed: \(error)")
        }
    }

    func stopRecording() -> String? {
        if let recorder = audioRecorder {
            if recorder.isRecording {
                // Capture duration while still recording — currentTime is reliable here
                let measured = recorder.currentTime
                lastRecordedDuration = max(measured, Double(_recordingDuration), lastRecordedDuration)
                recorder.stop()
            } else if lastRecordedDuration <= 0 {
                // Already stopped once; don't overwrite a good duration with currentTime == 0
                lastRecordedDuration = max(lastRecordedDuration, Double(_recordingDuration))
            }
            // else: keep lastRecordedDuration from the first stop
        } else if lastRecordedDuration <= 0 {
            lastRecordedDuration = Double(_recordingDuration)
        }

        recordingTimer?.invalidate()
        waveformTimer?.invalidate()
        waveformTimer = nil

        _isRecording = false
        _hasRecordedAudio = recordedAudioURL != nil

        return recordedAudioURL?.path
    }

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?._recordingDuration += 1
        }
    }

    private func startWaveformTimer() {
        waveformTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateWaveform()
        }
        RunLoop.main.add(timer, forMode: .common)
        waveformTimer = timer
    }

    private func updateWaveform() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()
        let peak = recorder.peakPower(forChannel: 0)
        let average = recorder.averagePower(forChannel: 0)
        // DSWaveformImage live formula: 0 = loud, 1 = silence.
        let power = max(peak * 0.55 + average * 0.45, average)
        let sample = CGFloat(max(0, min(1, 1 - pow(10, power / 20))))

        // Example app appends the same sample a few times to speed the scroll.
        _liveWaveAmplitudes.append(contentsOf: [sample, sample, sample])
        // Cap growth; UI trims to visible width.
        if _liveWaveAmplitudes.count > 600 {
            _liveWaveAmplitudes = Array(_liveWaveAmplitudes.suffix(400))
        }
    }

    // MARK: - Recorded Audio Playback
    func playRecordedAudio() {
        guard let url = recordedAudioURL else { return }

        configureAudioSessionForPlayback()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isRecordedPlaying = true
            isRecordedPaused = false
            startRecordedPlaybackTimer()
        } catch {
            AppLogger.debug("Playback failed: \(error)")
        }
    }

    func pauseRecordedAudio() {
        guard let player = audioPlayer, player.isPlaying else { return }
        player.pause()
        recordedPlaybackTimer?.invalidate()
        isRecordedPaused = true
    }

    func resumeRecordedAudio() {
        guard let player = audioPlayer, !player.isPlaying else { return }
        configureAudioSessionForPlayback()
        player.play()
        isRecordedPaused = false
        startRecordedPlaybackTimer()
    }

    func stopRecordedAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        recordedPlaybackTimer?.invalidate()
        recordedPlaybackTimer = nil
        isRecordedPlaying = false
        isRecordedPaused = false
        recordedPlaybackProgress = 0
    }

    private func startRecordedPlaybackTimer() {
        recordedPlaybackTimer?.invalidate()
        recordedPlaybackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let player = self.audioPlayer else { return }
            let duration = player.duration
            guard duration > 0 else { return }
            self.recordedPlaybackProgress = player.currentTime / duration
        }
    }

    func playMessageAudio(messageId: String, audioURL: URL) -> AnyPublisher<Double, Never> {
        if let playingId = currentlyPlayingMessageId, playingId != messageId {
            stopMessageAudio(messageId: playingId)
        }

        let subject = PassthroughSubject<Double, Never>()
        activePlaybackSubject = subject
        currentlyPlayingMessageId = messageId
        lastPlaybackDuration = 0
        lastPlaybackCurrentTime = 0

        configureAudioSessionForPlayback()

        let startPlayer: (AVAudioPlayer) -> Void = { [weak self] player in
            guard let self else { return }
            player.delegate = self
            player.enableRate = true
            player.rate = ChatAudioSpeedManager.shared.currentSpeed.rate
            player.prepareToPlay()
            self.messageAudioPlayers[messageId] = player
            if player.duration > 0.05, !player.duration.isNaN, !player.duration.isInfinite {
                self.lastPlaybackDuration = player.duration
            }
            self.lastPlaybackCurrentTime = 0
            player.play()
            // Publish immediately so the duration label starts even before the first timer tick.
            subject.send(0)
            self.startPlaybackTimer(messageId: messageId, player: player, subject: subject)
        }

        if audioURL.isFileURL {
            do {
                let player = try AVAudioPlayer(contentsOf: audioURL)
                startPlayer(player)
            } catch {
                AppLogger.debug("Failed to play local audio: \(error)")
                subject.send(completion: .finished)
                currentlyPlayingMessageId = nil
                activePlaybackSubject = nil
            }
            return subject.eraseToAnyPublisher()
        }

        // Remote URL: download data asynchronously, then play
        let task = URLSession.shared.dataTask(with: audioURL) { [weak self] data, response, error in
            if let error = error {
                AppLogger.debug("Audio download failed: \(error)")
                DispatchQueue.main.async {
                    subject.send(completion: .finished)
                    self?.currentlyPlayingMessageId = nil
                    self?.activePlaybackSubject = nil
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    subject.send(completion: .finished)
                    self?.currentlyPlayingMessageId = nil
                    self?.activePlaybackSubject = nil
                }
                return
            }
            DispatchQueue.main.async {
                do {
                    let player = try AVAudioPlayer(data: data)
                    startPlayer(player)
                } catch {
                    AppLogger.debug("Failed to create player from downloaded data: \(error)")
                    subject.send(completion: .finished)
                    self?.currentlyPlayingMessageId = nil
                    self?.activePlaybackSubject = nil
                }
            }
        }
        task.resume()

        return subject.eraseToAnyPublisher()
    }

    func pauseMessageAudio(messageId: String) {
        guard let player = messageAudioPlayers[messageId] else { return }
        player.pause()
        playbackTimers[messageId]?.invalidate()
        playbackTimers.removeValue(forKey: messageId)
        AppLogger.debug("Paused audio: \(messageId)")
    }

    func resumeMessageAudio(messageId: String) {
        guard let player = messageAudioPlayers[messageId] else { return }
        guard let subject = activePlaybackSubject else { return }

        player.enableRate = true
        player.rate = ChatAudioSpeedManager.shared.currentSpeed.rate
        player.play()
        startPlaybackTimer(messageId: messageId, player: player, subject: subject)
        AppLogger.debug("Resumed audio: \(messageId)")
    }

    private func startPlaybackTimer(messageId: String, player: AVAudioPlayer, subject: PassthroughSubject<Double, Never>) {
        playbackTimers[messageId]?.invalidate()
        // `.common` so progress keeps ticking during collection-view layout / scrolling.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self, weak player] _ in
            guard let self, let player else { return }
            var duration = player.duration
            if duration.isNaN || duration.isInfinite || duration <= 0.05 {
                duration = self.lastPlaybackDuration
            }
            if duration > 0.05 {
                self.lastPlaybackDuration = duration
            }
            self.lastPlaybackCurrentTime = player.currentTime
            let denom = max(duration, 0.001)
            let progress = min(1, max(0, player.currentTime / denom))
            subject.send(progress)
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimers[messageId] = timer
    }

    func stopMessageAudio(messageId: String) {
        messageAudioPlayers[messageId]?.delegate = nil
        messageAudioPlayers[messageId]?.stop()
        messageAudioPlayers.removeValue(forKey: messageId)
        playbackTimers[messageId]?.invalidate()
        playbackTimers.removeValue(forKey: messageId)

        if currentlyPlayingMessageId == messageId {
            currentlyPlayingMessageId = nil
            lastPlaybackCurrentTime = 0
            activePlaybackSubject?.send(completion: .finished)
            activePlaybackSubject = nil
        }

        AppLogger.debug("Stopped audio: \(messageId)")
    }

    func clearRecording() {
        if let url = recordedAudioURL {
            try? FileManager.default.removeItem(at: url)
            AppLogger.debug("Deleted recording file: \(url.lastPathComponent)")
        }

        audioPlayer?.stop()
        audioPlayer = nil

        recordedAudioURL = nil
        _hasRecordedAudio = false
        _recordingDuration = 0
        _liveWaveAmplitudes = []

        AppLogger.debug("Recording cleared and cleaned up")
    }

    /// Set playback rate on the currently playing message audio
    func setPlaybackRate(_ rate: Float) {
        if let messageId = currentlyPlayingMessageId,
           let player = messageAudioPlayers[messageId] {
            player.rate = rate
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension ChatAudioService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        _isRecording = false
        _hasRecordedAudio = flag && recordedAudioURL != nil
    }
}

// MARK: - AVAudioPlayerDelegate
extension ChatAudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player == audioPlayer {
            audioPlayer = nil
            recordedPlaybackTimer?.invalidate()
            recordedPlaybackTimer = nil
            isRecordedPlaying = false
            isRecordedPaused = false
            recordedPlaybackProgress = 1.0
            return
        }

        guard let messageId = messageAudioPlayers.first(where: { $0.value === player })?.key else { return }
        lastPlaybackCurrentTime = max(player.duration, lastPlaybackDuration)
        activePlaybackSubject?.send(1)
        playbackTimers[messageId]?.invalidate()
        playbackTimers.removeValue(forKey: messageId)
        messageAudioPlayers.removeValue(forKey: messageId)
        if currentlyPlayingMessageId == messageId {
            currentlyPlayingMessageId = nil
            activePlaybackSubject?.send(completion: .finished)
            activePlaybackSubject = nil
        }
    }
}
