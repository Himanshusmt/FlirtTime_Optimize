//
//  VoiceIntroRecorderViewController.swift
//  FlirttimeNew
//
//  Sheet for recording the signed-in user's voice intro: record (up to 30s), listen back,
//  re-record, then save. Used from the Profile tab and Edit Profile.
//

import UIKit
import AVFoundation

// MARK: - Recorder

final class VoiceIntroRecorder: NSObject {

    static let maxDuration: TimeInterval = 30
    static let minDuration: TimeInterval = 3

    enum State: Equatable {
        case idle
        case recording
        case recorded
        case playing
    }

    var onStateChange: ((State) -> Void)?
    /// Called about every 0.05s with the elapsed recording or playback time and, while recording, a 0...1 level.
    var onTick: ((TimeInterval, CGFloat?) -> Void)?

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var recordedDuration: TimeInterval = 0
    private(set) var fileURL: URL?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { granted in DispatchQueue.main.async { completion(granted) } }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: finish)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(finish)
        }
    }

    func startRecording() -> Bool {
        stopPlayback()
        discard()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return false
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_intro_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: Self.maxDuration) else { return false }
        self.recorder = recorder
        recorder.delegate = self
        fileURL = url
        state = .recording
        startTimer()
        return true
    }

    /// Returns `false` (and discards the take) when it was shorter than `minDuration`.
    @discardableResult
    func stopRecording() -> Bool {
        guard let recorder, state == .recording else { return false }
        recordedDuration = min(recorder.currentTime, Self.maxDuration)
        recorder.stop()
        return finishRecording()
    }

    func togglePlayback() {
        if state == .playing {
            stopPlayback()
            return
        }
        guard state == .recorded, let fileURL else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let player = try? AVAudioPlayer(contentsOf: fileURL) else { return }
        player.delegate = self
        player.play()
        self.player = player
        state = .playing
        startTimer()
    }

    func stopPlayback() {
        guard state == .playing else { return }
        player?.stop()
        player = nil
        stopTimer()
        state = .recorded
        onTick?(0, nil)
    }

    /// Stops everything and deletes the temporary file.
    func discard() {
        stopTimer()
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        player?.stop()
        player = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        recordedDuration = 0
        if state != .idle {
            state = .idle
        }
    }


    private func finishRecording() -> Bool {
        stopTimer()
        recorder?.delegate = nil
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard recordedDuration >= Self.minDuration else {
            discard()
            return false
        }
        state = .recorded
        return true
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        switch state {
        case .recording:
            guard let recorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let level = CGFloat(max(0, min(1, (power + 50) / 50)))
            onTick?(recorder.currentTime, level)
        case .playing:
            guard let player else { return }
            onTick?(player.currentTime, nil)
        default:
            break
        }
    }
}

extension VoiceIntroRecorder: AVAudioRecorderDelegate, AVAudioPlayerDelegate {

    /// Fires when `record(forDuration:)` hits the limit.
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard state == .recording, recorder === self.recorder else { return }
        recordedDuration = Self.maxDuration
        _ = finishRecording()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlayback()
    }
}

// MARK: - Sheet

final class VoiceIntroRecorderViewController: UIViewController, UIAdaptivePresentationControllerDelegate {

    /// Called after the recording has been uploaded, just before the sheet dismisses.
    var onSaved: ((UserVoiceIntro) -> Void)?

    private static let prompts = [
        "My perfect Sunday looks like…",
        "The quickest way to win me over is…",
        "A fun fact most people don't know about me…",
        "I'm looking for someone who…",
        "My go-to karaoke song is…",
        "The best trip I've ever taken was…"
    ]

    private let recorder = VoiceIntroRecorder()
    private var promptIndex = Int.random(in: 0..<VoiceIntroRecorderViewController.prompts.count)

    private let promptLabel = UILabel.vibeLabel(.bold, 18, style: .headline, color: AppColor.AppBlack, lines: 0)
    private let levels = VoiceLevelsView()
    private let timeLabel = UILabel.vibeLabel(.medium, 15, style: .subheadline, color: AppColor.MineShaft)
    private let hintLabel = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.DoveGray, lines: 0)
    private let mainButton = UIButton(type: .custom)
    private let mainButtonRing = UIView()
    private let redoButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var isSaving = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        presentationController?.delegate = self
        setUI()
        recorder.onStateChange = { [weak self] state in self?.render(state) }
        recorder.onTick = { [weak self] time, level in self?.tick(time: time, level: level) }
        render(.idle)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            recorder.discard()
        }
    }

    // MARK: UI

    private func setUI() {
        let title = UILabel.vibeLabel(.bold, 22, style: .title2, color: AppColor.AppBlack)
        title.text = "Your voice intro"
        title.textAlignment = .center
        title.accessibilityTraits = .header

        let subtitle = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: AppColor.DoveGray, lines: 0)
        subtitle.text = "Say hi in up to \(Int(VoiceIntroRecorder.maxDuration)) seconds. Matches can play it on your profile."
        subtitle.textAlignment = .center

        let promptCaption = UILabel.vibeLabel(.medium, 12, style: .caption1, color: AppColor.Punch)
        promptCaption.text = "NEED AN IDEA?"
        promptLabel.textAlignment = .left
        promptLabel.text = Self.prompts[promptIndex]

        var shuffleConfig = UIButton.Configuration.plain()
        shuffleConfig.image = UIImage(systemName: "shuffle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        shuffleConfig.baseForegroundColor = AppColor.Punch
        let shuffle = UIButton(configuration: shuffleConfig)
        shuffle.accessibilityLabel = "Another prompt"
        shuffle.setContentHuggingPriority(.required, for: .horizontal)
        shuffle.addAction(UIAction { [weak self] _ in self?.nextPrompt() }, for: .touchUpInside)

        let promptTexts = UIStackView(arrangedSubviews: [promptCaption, promptLabel])
        promptTexts.axis = .vertical
        promptTexts.spacing = 4
        let promptRow = UIStackView(arrangedSubviews: [promptTexts, shuffle])
        promptRow.alignment = .center
        promptRow.spacing = 8
        let promptCard = UIView()
        promptCard.backgroundColor = AppColor.Lavenderblush
        promptCard.layer.cornerRadius = 18
        promptCard.layer.cornerCurve = .continuous
        promptCard.addSubview(promptRow)
        promptRow.pinEdges(to: promptCard, insets: UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 8))

        timeLabel.textAlignment = .center
        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        hintLabel.textAlignment = .center

        mainButtonRing.layer.cornerRadius = 46
        mainButtonRing.layer.borderWidth = 4
        mainButtonRing.layer.borderColor = AppColor.Punch.withAlphaComponent(0.25).cgColor
        mainButtonRing.isUserInteractionEnabled = false
        mainButton.backgroundColor = AppColor.Punch
        mainButton.tintColor = .white
        mainButton.layer.cornerRadius = 36
        mainButton.layer.shadowColor = AppColor.Punch.cgColor
        mainButton.layer.shadowOpacity = 0.35
        mainButton.layer.shadowRadius = 10
        mainButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        mainButton.addAction(UIAction { [weak self] _ in self?.mainTapped() }, for: .touchUpInside)
        let mainHolder = UIView()
        [mainButtonRing, mainButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            mainHolder.addSubview($0)
        }

        configureSideButton(redoButton, symbol: "arrow.counterclockwise", title: "Re-record")
        redoButton.addAction(UIAction { [weak self] _ in self?.redo() }, for: .touchUpInside)
        configureSideButton(saveButton, symbol: "checkmark", title: "Save", filled: true)
        saveButton.addAction(UIAction { [weak self] _ in self?.save() }, for: .touchUpInside)

        let controls = UIStackView(arrangedSubviews: [redoButton, mainHolder, saveButton])
        controls.alignment = .center
        controls.distribution = .equalCentering

        var closeConfig = UIButton.Configuration.filled()
        closeConfig.cornerStyle = .capsule
        closeConfig.baseBackgroundColor = AppColor.AthensGray
        closeConfig.baseForegroundColor = AppColor.MineShaft
        closeConfig.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        closeButton.configuration = closeConfig
        closeButton.accessibilityLabel = "Close"
        closeButton.addAction(UIAction { [weak self] _ in self?.closeTapped() }, for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34)
        ])

        let stack = UIStackView(arrangedSubviews: [title, subtitle, promptCard, levels, timeLabel, controls, hintLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(24, after: promptCard)
        stack.setCustomSpacing(10, after: levels)
        stack.setCustomSpacing(18, after: timeLabel)
        stack.setCustomSpacing(14, after: controls)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            levels.heightAnchor.constraint(equalToConstant: 56),

            mainHolder.widthAnchor.constraint(equalToConstant: 92),
            mainHolder.heightAnchor.constraint(equalToConstant: 92),
            mainButtonRing.widthAnchor.constraint(equalToConstant: 92),
            mainButtonRing.heightAnchor.constraint(equalToConstant: 92),
            mainButtonRing.centerXAnchor.constraint(equalTo: mainHolder.centerXAnchor),
            mainButtonRing.centerYAnchor.constraint(equalTo: mainHolder.centerYAnchor),
            mainButton.widthAnchor.constraint(equalToConstant: 72),
            mainButton.heightAnchor.constraint(equalToConstant: 72),
            mainButton.centerXAnchor.constraint(equalTo: mainHolder.centerXAnchor),
            mainButton.centerYAnchor.constraint(equalTo: mainHolder.centerYAnchor),
            redoButton.widthAnchor.constraint(equalToConstant: 84),
            saveButton.widthAnchor.constraint(equalToConstant: 84)
        ])
    }

    private func configureSideButton(_ button: UIButton, symbol: String, title: String, filled: Bool = false) {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = filled ? AppColor.Punch : AppColor.Punch.withAlphaComponent(0.12)
        config.baseForegroundColor = filled ? .white : AppColor.Punch
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        config.imagePlacement = .top
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: MomentsFont.scaled(.medium, 13, style: .footnote)]))
        button.configuration = config
    }

    private func render(_ state: VoiceIntroRecorder.State) {
        let symbol: String
        let label: String
        switch state {
        case .idle:
            symbol = "mic.fill"
            label = "Start recording"
            levels.reset()
            timeLabel.text = "0:00 / \(Self.format(VoiceIntroRecorder.maxDuration))"
            hintLabel.text = "Tap the mic to start. At least \(Int(VoiceIntroRecorder.minDuration)) seconds."
        case .recording:
            symbol = "stop.fill"
            label = "Stop recording"
            hintLabel.text = "Recording… tap to stop."
        case .recorded:
            symbol = "play.fill"
            label = "Play recording"
            levels.setPlaybackProgress(0)
            timeLabel.text = Self.format(recorder.recordedDuration.rounded())
            hintLabel.text = "Listen back, then save or record again."
        case .playing:
            symbol = "pause.fill"
            label = "Pause"
            hintLabel.text = "Playing your voice intro…"
        }
        mainButton.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)), for: .normal)
        mainButton.accessibilityLabel = label
        mainButtonRing.layer.borderColor = (state == .recording ? AppColor.Punch : AppColor.Punch.withAlphaComponent(0.25)).cgColor

        let hasTake = state == .recorded || state == .playing
        UIView.animate(withDuration: 0.2) {
            self.redoButton.alpha = hasTake ? 1 : 0
            self.saveButton.alpha = hasTake ? 1 : 0
        }
        redoButton.isEnabled = hasTake
        saveButton.isEnabled = hasTake
        isModalInPresentation = state != .idle
        UIAccessibility.post(notification: .announcement, argument: hintLabel.text)
    }

    private func tick(time: TimeInterval, level: CGFloat?) {
        if let level {
            levels.append(level)
            timeLabel.text = "\(Self.format(time)) / \(Self.format(VoiceIntroRecorder.maxDuration))"
        } else if recorder.state == .playing, recorder.recordedDuration > 0 {
            levels.setPlaybackProgress(time / recorder.recordedDuration)
            timeLabel.text = "\(Self.format(time)) / \(Self.format(recorder.recordedDuration))"
        }
    }

    // MARK: Actions

    private func mainTapped() {
        switch recorder.state {
        case .idle:
            VoiceIntroPlayer.shared.stop()
            VoiceIntroRecorder.requestPermission { [weak self] granted in
                guard let self else { return }
                guard granted else {
                    self.showMicrophoneAccessAlert()
                    return
                }
                if !self.recorder.startRecording() {
                    self.hintLabel.text = "Couldn't start recording. Please try again."
                }
            }
        case .recording:
            if !recorder.stopRecording() {
                hintLabel.text = "Too short. Record at least \(Int(VoiceIntroRecorder.minDuration)) seconds."
            }
        case .recorded, .playing:
            recorder.togglePlayback()
        }
    }

    private func redo() {
        recorder.discard()
    }

    private func save() {
        guard !isSaving, let url = recorder.fileURL else { return }
        recorder.stopPlayback()
        isSaving = true
        setControlsEnabled(false)
        saveButton.configuration?.showsActivityIndicator = true
        VoiceIntroService.upload(recordingAt: url, duration: recorder.recordedDuration) { [weak self] result in
            guard let self else { return }
            self.isSaving = false
            self.saveButton.configuration?.showsActivityIndicator = false
            switch result {
            case .success(let intro):
                self.recorder.discard()
                self.onSaved?(intro)
                self.dismiss(animated: true)
            case .failure(let error):
                self.setControlsEnabled(true)
                self.hintLabel.text = error.message
            }
        }
    }

    private func setControlsEnabled(_ enabled: Bool) {
        [mainButton, redoButton, saveButton, closeButton].forEach { $0.isEnabled = enabled }
    }

    private var hasUnsavedTake: Bool {
        recorder.state != .idle
    }

    private func closeTapped() {
        guard hasUnsavedTake else {
            dismiss(animated: true)
            return
        }
        confirmDiscard()
    }

    private func confirmDiscard() {
        recorder.stopPlayback()
        if recorder.state == .recording {
            recorder.stopRecording()
        }
        let alert = UIAlertController(title: "Discard recording?", message: "Your new voice intro hasn't been saved.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.recorder.discard()
            self?.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Keep editing", style: .cancel))
        alert.popoverPresentationController?.sourceView = closeButton
        present(alert, animated: true)
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        guard !isSaving else { return }
        confirmDiscard()
    }

    private func nextPrompt() {
        promptIndex = (promptIndex + 1) % Self.prompts.count
        UIView.transition(with: promptLabel, duration: 0.2, options: .transitionCrossDissolve) {
            self.promptLabel.text = Self.prompts[self.promptIndex]
        }
    }

    private func showMicrophoneAccessAlert() {
        let alert = UIAlertController(title: "Microphone Access Required",
                                      message: "Please allow microphone access in Settings to record your voice intro.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    static func format(_ time: TimeInterval) -> String {
        let seconds = Int(time.rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func present(from presenter: UIViewController, onSaved: @escaping (UserVoiceIntro) -> Void) {
        let recorderVC = VoiceIntroRecorderViewController()
        recorderVC.onSaved = onSaved
        recorderVC.modalPresentationStyle = .pageSheet
        if let sheet = recorderVC.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        presenter.present(recorderVC, animated: true)
    }
}

// MARK: - Levels

/// Scrolling level bars while recording; a static waveform with a playback highlight afterwards.
final class VoiceLevelsView: UIView {

    private static let barCount = 36
    private var samples: [CGFloat] = []
    private var bars: [UIView] = []
    private var heights: [NSLayoutConstraint] = []
    private var playbackProgress: Double?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        let stack = UIStackView()
        stack.alignment = .center
        stack.distribution = .equalSpacing
        addSubview(stack)
        stack.pinEdges(to: self)
        for _ in 0..<Self.barCount {
            let bar = UIView()
            bar.layer.cornerRadius = 2
            bar.translatesAutoresizingMaskIntoConstraints = false
            let height = bar.heightAnchor.constraint(equalToConstant: 4)
            NSLayoutConstraint.activate([bar.widthAnchor.constraint(equalToConstant: 4), height])
            stack.addArrangedSubview(bar)
            bars.append(bar)
            heights.append(height)
        }
        reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        samples = []
        playbackProgress = nil
        redraw()
    }

    func append(_ level: CGFloat) {
        samples.append(level)
        playbackProgress = nil
        redraw()
    }

    func setPlaybackProgress(_ progress: Double) {
        playbackProgress = progress
        redraw()
    }

    private func redraw() {
        let visible = visibleSamples()
        let maxHeight = max(bounds.height, 56)
        let lit = playbackProgress.map { Int(($0 * Double(Self.barCount)).rounded(.down)) }
        for (index, bar) in bars.enumerated() {
            let level = visible[index]
            heights[index].constant = max(4, level * maxHeight)
            if let lit {
                bar.backgroundColor = index < lit ? AppColor.Punch : AppColor.Punch.withAlphaComponent(0.3)
            } else {
                bar.backgroundColor = level > 0 ? AppColor.Punch : AppColor.Punch.withAlphaComponent(0.2)
            }
        }
    }

    /// While recording, the newest samples on the right; once finished (playback mode), the whole take squeezed to fit.
    private func visibleSamples() -> [CGFloat] {
        guard !samples.isEmpty else { return Array(repeating: 0, count: Self.barCount) }
        if playbackProgress != nil, samples.count > Self.barCount {
            let chunk = Double(samples.count) / Double(Self.barCount)
            return (0..<Self.barCount).map { index in
                let start = Int(Double(index) * chunk)
                let end = max(start + 1, Int(Double(index + 1) * chunk))
                return samples[start..<min(end, samples.count)].max() ?? 0
            }
        }
        let recent = Array(samples.suffix(Self.barCount))
        return Array(repeating: 0, count: Self.barCount - recent.count) + recent
    }
}
