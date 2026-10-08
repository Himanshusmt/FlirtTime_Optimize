import UIKit

final class ChatAudioMessageCell: BaseMessageCell {

    static let cellId = "ChatAudioMessageCell"

    // MARK: - Subviews

    private let audioContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 22
        view.backgroundColor = ChatTheme.surface
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let playButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.setImage(UIImage(named: ChatAssets.play)?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.setImage(UIImage(named: ChatAssets.pause)?.withRenderingMode(.alwaysTemplate), for: .selected)
        btn.tintColor = .white
        btn.backgroundColor = ChatTheme.primary
        btn.layer.cornerRadius = 20
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let downloadIndicator: UIActivityIndicatorView = {
        let iv = UIActivityIndicatorView(style: .medium)
        iv.tintColor = ChatTheme.primary
        iv.hidesWhenStopped = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let downloadIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "arrow.down.circle"))
        iv.tintColor = ChatTheme.primary
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let waveformView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(size: 12)
        label.textColor = .black
        label.textAlignment = .trailing
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let speedButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.titleLabel?.font = UIFont.chat(.semibold, size: 11)
        btn.setTitleColor(ChatTheme.primary, for: .normal)
        btn.backgroundColor = ChatTheme.primary.withAlphaComponent(0.12)
        btn.layer.cornerRadius = 11
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private var waveformBars: [UIView] = []
    private var waveformColor: UIColor = ChatTheme.primary
    private var waveformAmplitudes: [CGFloat] = []
    private var waveformStack: UIStackView?
    private var currentWaveSeed: String?
    private var audioHStack: UIStackView?

    // Playback tracking
    private var totalDurationSeconds: Double = 0
    private var lastPlaybackProgress: Double = 0
    private var lastPlaybackCurrentTime: Double = 0
    private var lastKnownPlayerDuration: Double = 0

    // MARK: - Speed — synced globally via ChatAudioSpeedManager

    enum Speed: String, CaseIterable {
        case x1 = "1x", x1_5 = "1.5x", x2 = "2x"
        var rate: Float {
            switch self {
            case .x1: return 1.0
            case .x1_5: return 1.5
            case .x2: return 2.0
            }
        }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContentArea()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSpeedNotification(_:)), name: .audioSpeedDidChange, object: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContentArea()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSpeedNotification(_:)), name: .audioSpeedDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .audioSpeedDidChange, object: nil)
    }

    // MARK: - Setup

    private func setupContentArea() {
        contentArea.addSubview(audioContainer)

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.spacing = 8
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false
        audioHStack = hStack

        hStack.addArrangedSubview(playButton)
        hStack.addArrangedSubview(downloadIndicator)
        hStack.addArrangedSubview(downloadIcon)
        hStack.addArrangedSubview(waveformView)
        hStack.addArrangedSubview(durationLabel)
        hStack.addArrangedSubview(speedButton)

        audioContainer.addSubview(hStack)

        NSLayoutConstraint.activate([
            audioContainer.topAnchor.constraint(equalTo: contentArea.topAnchor),
            audioContainer.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            audioContainer.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            audioContainer.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),

            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: 40),

            downloadIndicator.widthAnchor.constraint(equalToConstant: 36),
            downloadIndicator.heightAnchor.constraint(equalToConstant: 36),

            downloadIcon.widthAnchor.constraint(equalToConstant: 36),
            downloadIcon.heightAnchor.constraint(equalToConstant: 36),

            waveformView.heightAnchor.constraint(equalToConstant: 32),

            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            speedButton.widthAnchor.constraint(equalToConstant: 36),
            speedButton.heightAnchor.constraint(equalToConstant: 22),

            hStack.topAnchor.constraint(equalTo: audioContainer.topAnchor, constant: 8),
            hStack.leftAnchor.constraint(equalTo: audioContainer.leftAnchor, constant: 8),
            hStack.rightAnchor.constraint(equalTo: audioContainer.rightAnchor, constant: -8),
            hStack.bottomAnchor.constraint(equalTo: audioContainer.bottomAnchor, constant: -8),
        ])

        playButton.addTarget(self, action: #selector(handlePlayTap), for: .touchUpInside)
        speedButton.addTarget(self, action: #selector(handleSpeedTap), for: .touchUpInside)

        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        speedButton.setTitle(ChatAudioSpeedManager.shared.currentSpeed.rawValue, for: .normal)
    }

    // MARK: - Waveform

    private func setupWaveform(seed: String) {
        if seed == currentWaveSeed { return }
        currentWaveSeed = seed

        waveformStack?.removeFromSuperview()
        waveformBars.removeAll()

        waveformAmplitudes = generateWaveAmplitudesFrom(seed: seed, length: 24)

        let barWidth: CGFloat = 3
        let spacing: CGFloat = 2

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.spacing = spacing
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false
        waveformView.addSubview(hStack)
        waveformStack = hStack

        NSLayoutConstraint.activate([
            hStack.centerXAnchor.constraint(equalTo: waveformView.centerXAnchor),
            hStack.centerYAnchor.constraint(equalTo: waveformView.centerYAnchor),
        ])

        for amp in waveformAmplitudes {
            let bar = UIView()
            bar.layer.cornerRadius = barWidth / 2
            let height = max(2, amp * 32)
            bar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: barWidth),
                bar.heightAnchor.constraint(equalToConstant: height),
            ])
            hStack.addArrangedSubview(bar)
            waveformBars.append(bar)
        }
    }

    private func generateWaveAmplitudesFrom(seed: String, length: Int) -> [CGFloat] {
        var value: UInt64 = 1469598103934665603
        for byte in seed.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
        var rng = value
        var result: [CGFloat] = []
        result.reserveCapacity(length)
        for _ in 0..<length {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            let normalized = CGFloat((rng % 100) + 10) / 110.0
            result.append(normalized)
        }
        return result
    }

    /// Update waveform highlighting to show playback progress
    func updatePlaybackProgress(_ progress: Double, currentTime: Double = 0, duration: Double = 0) {
        if duration > 0.05 {
            totalDurationSeconds = max(totalDurationSeconds, duration)
            lastKnownPlayerDuration = max(lastKnownPlayerDuration, duration)
        }
        lastPlaybackProgress = progress
        lastPlaybackCurrentTime = currentTime

        let foregroundColor = waveformColor
        let baselineColor = foregroundColor.withAlphaComponent(0.4)

        let highlightedBars = Int(Double(waveformBars.count) * max(0, min(1, progress)))
        for (index, bar) in waveformBars.enumerated() {
            bar.backgroundColor = index < highlightedBars ? foregroundColor : baselineColor
        }

        guard totalDurationSeconds > 0.05 else { return }

        let elapsed: Double
        if currentTime > 0 {
            elapsed = min(currentTime, totalDurationSeconds)
        } else if progress > 0 {
            elapsed = progress * totalDurationSeconds
        } else {
            durationLabel.text = formatTime(totalDurationSeconds)
            return
        }
        let remaining = max(0, totalDurationSeconds - elapsed)
        durationLabel.text = formatTime(remaining)
    }

    /// Reset duration label to total time (called when playback stops or cell is first configured)
    func resetDurationLabel() {
        if totalDurationSeconds > 0 {
            durationLabel.text = formatTime(totalDurationSeconds)
        }
    }

    /// Update play/pause button state
    func updatePlayingState(_ isPlaying: Bool, isPaused: Bool = false) {
        playButton.isSelected = isPlaying
        if !isPlaying && !isPaused {
            resetDurationLabel()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Configure

    override func configureContent(with model: MessageCellModel) {
        let durationText = getAudioDuration(from: model.message)
        durationLabel.text = durationText.isEmpty ? "0:00" : durationText

        // Parse total duration for playback countdown
        totalDurationSeconds = parseDurationSeconds(from: model.message)

        let audioItem = model.mediaItems.first
        let seed = model.message.metadata?["waveSeed"]?.value as? String
            ?? audioItem?.url
            ?? model.stableId
        setupWaveform(seed: seed)

        let messageId = model.stableId

        let isDownloaded = localAudioFileURL(for: model.message) != nil
            || MediaStorageManager.shared.isAlreadyDownloaded(messageId: messageId)
            || MediaStorageManager.shared.mediaExists(messageId: messageId, type: .audio)

        if isDownloaded {
            downloadIndicator.stopAnimating()
            downloadIcon.isHidden = true
            playButton.isHidden = false
        } else {
            downloadIndicator.stopAnimating()
            downloadIcon.isHidden = false
            playButton.isHidden = true
            autoDownloadAudio(model: model)
        }

        speedButton.setTitle(ChatAudioSpeedManager.shared.currentSpeed.rawValue, for: .normal)

        // Reconfigure (status ticks, etc.) must not reset an in-progress countdown.
        if playButton.isSelected {
            updatePlaybackProgress(
                lastPlaybackProgress,
                currentTime: lastPlaybackCurrentTime,
                duration: max(totalDurationSeconds, lastKnownPlayerDuration)
            )
        } else {
            lastPlaybackProgress = 0
            lastPlaybackCurrentTime = 0
            lastKnownPlayerDuration = 0
            updatePlaybackProgress(0)
            resetDurationLabel()
        }
    }

    private func parseDurationSeconds(from message: ConversationMessage) -> Double {
        audioDurationSeconds(from: message) ?? 0
    }

    private func autoDownloadAudio(model: MessageCellModel) {
        let messageId = model.stableId
        guard !messageId.isEmpty else { return }

        if MediaStorageManager.shared.isDownloading[messageId] == true {
            downloadIndicator.startAnimating()
            downloadIcon.isHidden = true
            playButton.isHidden = true
        }

        let audioURL: URL?
        if let local = localAudioFileURL(for: model.message) {
            audioURL = local
        } else if let resolved = model.message.resolvedMediaURL, !resolved.isFileURL {
            audioURL = resolved
        } else if let urlString = model.mediaItems.first?.url, urlString.lowercased().hasPrefix("http") {
            audioURL = URL(string: urlString)
        } else if let content = model.message.content, content.lowercased().hasPrefix("http") {
            audioURL = URL(string: content)
        } else {
            audioURL = nil
        }

        guard let audioURL else {
            if !model.isIncoming {
                downloadIcon.isHidden = true
                playButton.isHidden = false
            }
            return
        }

        if audioURL.isFileURL {
            downloadIcon.isHidden = true
            playButton.isHidden = false
            return
        }

        MediaStorageManager.shared.downloadMedia(
            from: audioURL.absoluteString,
            messageId: messageId,
            type: .audio
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.cellModel?.stableId == messageId else { return }
                switch result {
                case .success:
                    self.downloadIndicator.stopAnimating()
                    self.downloadIcon.isHidden = true
                    self.playButton.isHidden = false
                case .failure:
                    self.downloadIndicator.stopAnimating()
                    self.downloadIcon.isHidden = false
                    self.playButton.isHidden = true
                }
            }
        }
    }

    @objc private func handlePlayTap() {
        guard let model = cellModel else { return }
        actionsDelegate?.cellDidTapMedia(self, model: model, mediaIndex: 0)
    }

    @objc private func handleSpeedTap() {
        ChatAudioSpeedManager.shared.cycleSpeed()
        let speed = ChatAudioSpeedManager.shared.currentSpeed
        speedButton.setTitle(speed.rawValue, for: .normal)
        actionsDelegate?.cellDidChangeAudioSpeed(self, speed: speed.rate)
        NotificationCenter.default.post(name: .audioSpeedDidChange, object: nil, userInfo: ["speed": speed.rawValue])
    }

    @objc private func handleSpeedNotification(_ notification: Notification) {
        guard let rawValue = notification.userInfo?["speed"] as? String else { return }
        speedButton.setTitle(rawValue, for: .normal)
    }

    override func configureBubbleAppearance(model: MessageCellModel) {
        // Reset to default (no-reply) state first
        audioContainer.layer.cornerRadius = 16
        bubbleContainer.clipsToBounds = false
        setBubbleContentInsets(top: 0, horizontal: 0, bottom: 0)
        // Wide enough for play(50) + gaps + waveform + duration(36) + speed(36) + padding(16)
        overrideBubbleWidth(min(UIScreen.main.bounds.width * 0.75, UIScreen.main.bounds.width * 0.72 + 20))
        bubbleContainer.backgroundColor = .clear
        bubbleContainer.layer.cornerRadius = 0

        let accent: UIColor
        if model.isIncoming {
            audioContainer.backgroundColor = ChatTheme.surface
            accent = ChatTheme.primary
            playButton.backgroundColor = ChatTheme.primary
            playButton.tintColor = .white
            durationLabel.textColor = ChatTheme.textSecondary
        } else {
            audioContainer.backgroundColor = ChatTheme.outgoingBubble
            accent = ChatTheme.outgoingText
            playButton.backgroundColor = .white
            playButton.tintColor = ChatTheme.primary
            durationLabel.textColor = ChatTheme.outgoingText
        }
        audioContainer.layer.cornerRadius = 22

        waveformColor = accent
        downloadIndicator.color = accent
        downloadIcon.tintColor = accent
        speedButton.setTitleColor(accent, for: .normal)
        speedButton.backgroundColor = accent.withAlphaComponent(0.15)
        updatePlaybackProgress(lastPlaybackProgress, currentTime: lastPlaybackCurrentTime)

        // When a reply is present: outer bubble wraps reply preview + audio player
        if model.replyPreview != nil {
            wrapInReplyBubble(model: model, innerInsets: 6)
            audioContainer.layer.cornerRadius = 10
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        playButton.isSelected = false
        playButton.isHidden = false
        downloadIndicator.stopAnimating()
        downloadIcon.isHidden = true
        durationLabel.text = nil
        currentWaveSeed = nil
        waveformStack?.removeFromSuperview()
        waveformStack = nil
        waveformBars.removeAll()
        waveformAmplitudes.removeAll()
        totalDurationSeconds = 0
        lastPlaybackProgress = 0
        lastPlaybackCurrentTime = 0
        lastKnownPlayerDuration = 0
    }
}

// MARK: - Global Audio Speed Manager

final class ChatAudioSpeedManager {
    static let shared = ChatAudioSpeedManager()

    private let speeds: [ChatAudioMessageCell.Speed] = ChatAudioMessageCell.Speed.allCases
    private(set) var currentIndex = 0

    var currentSpeed: ChatAudioMessageCell.Speed {
        speeds[currentIndex]
    }

    func cycleSpeed() {
        currentIndex = (currentIndex + 1) % speeds.count
    }
}

extension Notification.Name {
    static let audioSpeedDidChange = Notification.Name("audioSpeedDidChange")
}
