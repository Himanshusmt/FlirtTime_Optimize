import UIKit

final class ChatAudioComposerView: UIView {

    // MARK: - Callbacks

    var onCancelRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onDeleteRecording: (() -> Void)?
    var onSendRecording: (() -> Void)?

    // MARK: - State

    private var isRecording = false
    private var isUploading = false
    private var isPlaying = false

    static let barHeight: CGFloat = 72

    // MARK: - Recording Subviews

    private let recordingCapsule: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 26
        v.clipsToBounds = true
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let gradientLayer: CAGradientLayer = {
        let g = CAGradientLayer()
        g.colors = [
            ChatTheme.primaryLight.cgColor,
            ChatTheme.primary.cgColor
        ]
        g.startPoint = CGPoint(x: 0, y: 0)
        g.endPoint = CGPoint(x: 1, y: 1)
        return g
    }()

    private let cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.close)?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let waveformView: ChatLiveWaveformView = {
        let w = ChatLiveWaveformView()
        w.stripeWidth = 2
        w.stripeSpacing = 2
        w.stripeColor = .white
        w.shouldDrawSilencePadding = true
        w.translatesAutoresizingMaskIntoConstraints = false
        return w
    }()

    /// Tracks how many DS-style samples were already pushed into `waveformView`.
    private var lastPushedWaveSampleCount = 0
    private var wasShowingRecordingWave = false

    private let timerLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        lbl.textColor = .white
        lbl.text = "00:00"
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let stopButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private var stopRing: CAShapeLayer?

    private var stopLTRLeading: NSLayoutConstraint?
    private var stopLTRTrailing: NSLayoutConstraint?
    private var stopRTLLeading: NSLayoutConstraint?
    private var stopRTLTrailing: NSLayoutConstraint?

    // MARK: - Preview Subviews

    private let previewContainer: UIView = {
        let v = UIView()
        v.backgroundColor = ChatTheme.surface
        v.layer.cornerRadius = 26
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let playPauseButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.play)?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.setImage(UIImage(named: ChatAssets.pause)?.withRenderingMode(.alwaysTemplate), for: .selected)
        btn.tintColor = .white
        btn.backgroundColor = ChatTheme.primary
        btn.layer.cornerRadius = 16
        btn.clipsToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let progressWaveform: ProgressWaveformBars = {
        let w = ProgressWaveformBars(barCount: 32, barWidth: 3)
        w.translatesAutoresizingMaskIntoConstraints = false
        return w
    }()

    private let durationLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 13)
        lbl.textColor = ChatTheme.textSecondary
        lbl.text = "00:00"
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let deleteButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.trash)?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.tintColor = ChatTheme.primary
        btn.backgroundColor = ChatTheme.primarySoft
        btn.layer.cornerRadius = 16
        btn.clipsToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let sendRecordButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let sendIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(named: ChatAssets.send)?.withRenderingMode(.alwaysTemplate))
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let sendSpinner: UIActivityIndicatorView = {
        let sp = UIActivityIndicatorView(style: .medium)
        sp.color = .white
        sp.hidesWhenStopped = true
        sp.translatesAutoresizingMaskIntoConstraints = false
        return sp
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        backgroundColor = .white

        let rtl = UIApplication.isRTL()

        setupRecordingUI(rtl: rtl)
        setupPreviewUI()

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        sendRecordButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        enforceRTLIfNeeded()
    }

    private func setupRecordingUI(rtl: Bool) {
        addSubview(recordingCapsule)
        recordingCapsule.layer.insertSublayer(gradientLayer, at: 0)

        recordingCapsule.addSubview(cancelButton)
        recordingCapsule.addSubview(waveformView)
        recordingCapsule.addSubview(timerLabel)

        // Stop button — filled Punch circle with white square
        addSubview(stopButton)
        let size: CGFloat = 52
        let squareSize: CGFloat = 18
        stopButton.backgroundColor = ChatTheme.primary
        stopButton.layer.cornerRadius = size / 2
        stopButton.clipsToBounds = true

        let squareView = UIView()
        squareView.backgroundColor = .white
        squareView.layer.cornerRadius = 3
        squareView.isUserInteractionEnabled = false
        squareView.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addSubview(squareView)

        NSLayoutConstraint.activate([
            squareView.centerXAnchor.constraint(equalTo: stopButton.centerXAnchor),
            squareView.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
            squareView.widthAnchor.constraint(equalToConstant: squareSize),
            squareView.heightAnchor.constraint(equalToConstant: squareSize),
        ])

        NSLayoutConstraint.activate([
            recordingCapsule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            recordingCapsule.centerYAnchor.constraint(equalTo: centerYAnchor),
            recordingCapsule.heightAnchor.constraint(equalToConstant: 52),

            cancelButton.leadingAnchor.constraint(equalTo: recordingCapsule.leadingAnchor, constant: 14),
            cancelButton.centerYAnchor.constraint(equalTo: recordingCapsule.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 24),
            cancelButton.heightAnchor.constraint(equalToConstant: 24),

            waveformView.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 10),
            waveformView.centerYAnchor.constraint(equalTo: recordingCapsule.centerYAnchor),
            waveformView.heightAnchor.constraint(equalToConstant: 36),

            timerLabel.leadingAnchor.constraint(equalTo: waveformView.trailingAnchor, constant: 10),
            timerLabel.centerYAnchor.constraint(equalTo: recordingCapsule.centerYAnchor),
            timerLabel.widthAnchor.constraint(equalToConstant: 46),
            timerLabel.trailingAnchor.constraint(equalTo: recordingCapsule.trailingAnchor, constant: -14),
        ])

        stopLTRLeading = stopButton.leftAnchor.constraint(equalTo: recordingCapsule.rightAnchor, constant: 12)
        stopLTRTrailing = stopButton.rightAnchor.constraint(equalTo: rightAnchor, constant: -12)

        stopRTLLeading = stopButton.leftAnchor.constraint(equalTo: leftAnchor, constant: 12)
        stopRTLTrailing = stopButton.rightAnchor.constraint(equalTo: recordingCapsule.leftAnchor, constant: -12)

        if rtl {
            stopRTLLeading?.isActive = true
            stopRTLTrailing?.isActive = true
        } else {
            stopLTRLeading?.isActive = true
            stopLTRTrailing?.isActive = true
        }

        NSLayoutConstraint.activate([
            stopButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: size),
            stopButton.heightAnchor.constraint(equalToConstant: size),
        ])
    }

    private func setupPreviewUI() {
        addSubview(previewContainer)

        previewContainer.addSubview(playPauseButton)
        previewContainer.addSubview(progressWaveform)
        previewContainer.addSubview(durationLabel)
        previewContainer.addSubview(deleteButton)
        previewContainer.addSubview(sendRecordButton)

        sendRecordButton.addSubview(sendIcon)
        sendRecordButton.addSubview(sendSpinner)
        sendRecordButton.layer.cornerRadius = 18
        sendRecordButton.clipsToBounds = true
        sendRecordButton.backgroundColor = ChatTheme.primary

        NSLayoutConstraint.activate([
            previewContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            previewContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            previewContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            previewContainer.heightAnchor.constraint(equalToConstant: 52),

            playPauseButton.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 8),
            playPauseButton.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 32),
            playPauseButton.heightAnchor.constraint(equalToConstant: 32),

            progressWaveform.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 8),
            progressWaveform.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            progressWaveform.heightAnchor.constraint(equalToConstant: 24),

            durationLabel.leadingAnchor.constraint(equalTo: progressWaveform.trailingAnchor, constant: 8),
            durationLabel.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),

            deleteButton.leadingAnchor.constraint(equalTo: durationLabel.trailingAnchor, constant: 8),
            deleteButton.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 32),
            deleteButton.heightAnchor.constraint(equalToConstant: 32),

            sendRecordButton.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 8),
            sendRecordButton.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -8),
            sendRecordButton.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            sendRecordButton.widthAnchor.constraint(equalToConstant: 36),
            sendRecordButton.heightAnchor.constraint(equalToConstant: 36),

            sendIcon.centerXAnchor.constraint(equalTo: sendRecordButton.centerXAnchor),
            sendIcon.centerYAnchor.constraint(equalTo: sendRecordButton.centerYAnchor),

            sendSpinner.centerXAnchor.constraint(equalTo: sendRecordButton.centerXAnchor),
            sendSpinner.centerYAnchor.constraint(equalTo: sendRecordButton.centerYAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = recordingCapsule.bounds
    }

    // MARK: - Configure

    func setRecording(_ recording: Bool, amplitudes: [CGFloat] = [], duration: Int = 0) {
        isRecording = recording
        if recording {
            isHidden = false
            recordingCapsule.isHidden = false
            stopButton.isHidden = false
            previewContainer.isHidden = true
            timerLabel.text = formatTime(duration)

            if !wasShowingRecordingWave {
                waveformView.reset()
                lastPushedWaveSampleCount = 0
                wasShowingRecordingWave = true
            }

            if amplitudes.count > lastPushedWaveSampleCount {
                let newSamples = amplitudes[lastPushedWaveSampleCount...].map { Float($0) }
                waveformView.add(samples: newSamples)
                lastPushedWaveSampleCount = amplitudes.count
            } else if amplitudes.count < lastPushedWaveSampleCount {
                // Service reset mid-session.
                waveformView.reset()
                lastPushedWaveSampleCount = 0
                if !amplitudes.isEmpty {
                    waveformView.add(samples: amplitudes.map { Float($0) })
                    lastPushedWaveSampleCount = amplitudes.count
                }
            }
        } else {
            wasShowingRecordingWave = false
            lastPushedWaveSampleCount = 0
        }
    }

    func setPreview(seed: String?, progress: Double, duration: String?, isPlaying: Bool, isPaused: Bool, totalDurationSeconds: Int, isUploading: Bool) {
        wasShowingRecordingWave = false
        lastPushedWaveSampleCount = 0
        let finished = progress >= 1.0 && !isPlaying
        self.isPlaying = finished ? false : isPlaying
        self.isUploading = isUploading
        isHidden = false
        recordingCapsule.isHidden = true
        stopButton.isHidden = true
        previewContainer.isHidden = false

        playPauseButton.isSelected = self.isPlaying && !isPaused

        if let seed {
            let amplitudes = generateWaveAmplitudes(from: seed, length: 32)
            let displayProgress = finished ? 0.0 : progress
            progressWaveform.setAmplitudes(amplitudes, progress: Float(displayProgress))
        }

        if self.isPlaying && !isPaused && totalDurationSeconds > 0 {
            let elapsed = Int(Double(totalDurationSeconds) * progress)
            durationLabel.text = formatTime(elapsed)
        } else if finished {
            durationLabel.text = duration ?? "00:00"
        } else {
            durationLabel.text = duration ?? "00:00"
        }

        if isUploading {
            sendIcon.isHidden = true
            sendSpinner.startAnimating()
            sendRecordButton.backgroundColor = .gray
        } else {
            sendIcon.isHidden = false
            sendSpinner.stopAnimating()
            sendRecordButton.backgroundColor = ChatTheme.primary
        }
        deleteButton.isEnabled = !isUploading
        deleteButton.tintColor = isUploading ? .gray : ChatTheme.primary
        sendRecordButton.isEnabled = !isUploading
    }

    func setHidden() {
        isHidden = true
        recordingCapsule.isHidden = true
        stopButton.isHidden = true
        previewContainer.isHidden = true
        wasShowingRecordingWave = false
        lastPushedWaveSampleCount = 0
        waveformView.reset()
    }

    // MARK: - Actions

    @objc private func cancelTapped() { onCancelRecording?() }
    @objc private func stopTapped() { onStopRecording?() }
    @objc private func playPauseTapped() { onTogglePlayback?() }
    @objc private func deleteTapped() { onDeleteRecording?() }
    @objc private func sendTapped() { onSendRecording?() }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Progress Waveform Bars

private final class ProgressWaveformBars: UIView {

    private let barCount: Int
    private let barWidth: CGFloat
    private var bars: [(track: UIView, fill: UIView)] = []
    private var progress: Float = 0

    init(barCount: Int, barWidth: CGFloat) {
        self.barCount = barCount
        self.barWidth = barWidth
        super.init(frame: .zero)
        for _ in 0..<barCount {
            let track = UIView()
            track.backgroundColor = ChatTheme.primary.withAlphaComponent(0.25)
            track.layer.cornerRadius = barWidth / 2
            track.translatesAutoresizingMaskIntoConstraints = false

            let fill = UIView()
            fill.backgroundColor = ChatTheme.primary
            fill.layer.cornerRadius = barWidth / 2
            fill.translatesAutoresizingMaskIntoConstraints = false

            addSubview(track)
            track.addSubview(fill)
            bars.append((track, fill))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let spacing: CGFloat = 3
        let totalWidth = CGFloat(barCount) * (barWidth + spacing) - spacing
        var x: CGFloat = (bounds.width - totalWidth) / 2
        for (i, bar) in bars.enumerated() {
            let h = bars.count > 1 ? (bounds.height * 0.3 + CGFloat(i % 5) * bounds.height * 0.14) : bounds.height * 0.5
            bar.track.frame = CGRect(x: x, y: (bounds.height - h) / 2, width: barWidth, height: h)
            x += barWidth + spacing
        }
        applyProgress()
    }

    func setAmplitudes(_ amplitudes: [CGFloat], progress: Float) {
        self.progress = progress
        let spacing: CGFloat = 3
        let totalWidth = CGFloat(barCount) * (barWidth + spacing) - spacing
        var x: CGFloat = (bounds.width - totalWidth) / 2
        for (i, bar) in bars.enumerated() {
            let amp = i < amplitudes.count ? amplitudes[i] : 0.15
            let h = max(4, amp * bounds.height)
            bar.track.frame = CGRect(x: x, y: (bounds.height - h) / 2, width: barWidth, height: h)
            x += barWidth + spacing
        }
        applyProgress()
    }

    private func applyProgress() {
        for (i, bar) in bars.enumerated() {
            let barProgress = Float(i) / Float(max(1, barCount - 1))
            let isActive = barProgress <= progress
            UIView.animate(withDuration: 0.08) {
                bar.fill.frame = bar.track.bounds
                bar.fill.alpha = isActive ? 1.0 : 0.0
                bar.track.backgroundColor = isActive
                    ? ChatTheme.primary.withAlphaComponent(0.5)
                    : ChatTheme.primary.withAlphaComponent(0.25)
            }
        }
    }
}
