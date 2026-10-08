import UIKit

final class CameraOverlayView: UIView {

    enum CaptureMode { case photo, video }
    enum FlashMode { case auto, on, off }

    var onClose: (() -> Void)?
    var onCapturePhoto: (() -> Void)?
    var onStartRecording: (() -> Bool)?
    var onStopRecording: (() -> Void)?
    var onFlip: (() -> Void)?
    var onFlashModeChanged: ((FlashMode) -> Void)?
    var onCaptureModeChanged: ((CaptureMode) -> Void)?
    var onRecordingFailed: (() -> Void)?
    /// 0...1 while holding to record; 0 is 1x, 1 is max zoom (Snapchat slide-up).
    var onZoomChanged: ((CGFloat) -> Void)?
    /// Absolute zoom factor (1...max) from slide or pinch while recording.
    var onZoomFactorChanged: ((CGFloat) -> Void)?

    var minZoomFactor: CGFloat = 1
    var maxZoomFactor: CGFloat = 8

    /// Single Snapchat shutter: tap = photo, hold = video. Hides Photo/Video tabs.
    var holdToRecordAndZoom = false {
        didSet {
            updateCaptureGestures()
            updateHoldHint()
            updateSingleShutterChrome()
        }
    }
    /// Auto-stop and fill the circular progress ring. `0` means no limit / no ring.
    var maxRecordDuration: TimeInterval = 0 {
        didSet { updateHoldHint() }
    }

    private var captureMode: CaptureMode = .photo {
        didSet {
            guard oldValue != captureMode else { return }
            updateModeAppearance()
            onCaptureModeChanged?(captureMode)
        }
    }
    private var flashMode: FlashMode = .auto { didSet { updateFlashIcon() } }

    private let closeButton: UIButton = {
        let btn = UIButton(type: .custom)
        let img = UIImage(named: ChatAssets.cameraClose)
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let flipButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.setImage(UIImage(systemName: "camera.rotate"), for: .normal)
        btn.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 22, weight: .regular), forImageIn: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let flashButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityLabel = "Flash"
        return btn
    }()

    private let photoSegmentLabel: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(ChatStrings.chat_photo.localizedString().uppercased(), for: .normal)
        btn.titleLabel?.font = UIFont.chat(.heavy, size: 11)
        btn.setTitleColor(ChatTheme.warning, for: .normal)
        btn.titleLabel?.textAlignment = .center
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let videoSegmentLabel: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(ChatStrings.chat_video.localizedString().uppercased(), for: .normal)
        btn.titleLabel?.font = UIFont.chat(.heavy, size: 11)
        btn.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .normal)
        btn.titleLabel?.textAlignment = .center
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let captureButton: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.layer.cornerRadius = 35
        v.layer.borderWidth = 5
        v.layer.borderColor = UIColor.white.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isUserInteractionEnabled = true
        return v
    }()

    private let captureInnerView: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 28
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let recordingIndicator: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        v.layer.cornerRadius = 14
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let recordingDot: UIView = {
        let v = UIView()
        v.backgroundColor = ChatTheme.error
        v.layer.cornerRadius = 5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let recordingLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        l.textColor = .white
        l.text = "0:00"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let holdHintLabel: UILabel = {
        let l = UILabel()
        l.text = ChatStrings.cameraHoldForVideoTapForPhoto.localizedString()
        l.font = UIFont.chat(.semibold, size: 13)
        l.textColor = .white
        l.textAlignment = .center
        l.numberOfLines = 2
        l.layer.shadowColor = UIColor.black.cgColor
        l.layer.shadowOpacity = 0.55
        l.layer.shadowRadius = 2
        l.layer.shadowOffset = CGSize(width: 0, height: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private var captureCenterX: NSLayoutConstraint?
    private var captureCenterY: NSLayoutConstraint?
    private var captureWidth: NSLayoutConstraint?
    private var captureHeight: NSLayoutConstraint?
    private var innerWidth: NSLayoutConstraint?
    private var innerHeight: NSLayoutConstraint?

    private var isRecording = false
    private var isCapturing = false
    private var recordStartTime: Date?
    private var pulseTimer: Timer?
    private var labelTimer: Timer?
    private var maxDurationWorkItem: DispatchWorkItem?
    private var holdBeganPoint: CGPoint = .zero
    private var captureTap: UITapGestureRecognizer?
    private var captureLongPress: UILongPressGestureRecognizer?
    private var pinchZoom: UIPinchGestureRecognizer?
    private var currentZoomFactor: CGFloat = 1
    private var holdStartZoom: CGFloat = 1
    private var pinchStartZoom: CGFloat = 1
    private var isPinching = false

    private let recordProgressTrackLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        layer.lineWidth = 5
        layer.strokeEnd = 1
        layer.isHidden = true
        return layer
    }()

    private let recordProgressLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = ChatTheme.primary.cgColor
        layer.lineWidth = 5
        layer.lineCap = .round
        layer.strokeEnd = 0
        layer.isHidden = true
        return layer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupGestures()
        updateFlashIcon()
        updateModeAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        setupGestures()
        updateFlashIcon()
        updateModeAppearance()
    }

    deinit {
        maxDurationWorkItem?.cancel()
        pulseTimer?.invalidate()
        labelTimer?.invalidate()
    }

    private func setupViews() {
        backgroundColor = .clear

        addSubview(closeButton)
        addSubview(flipButton)
        addSubview(flashButton)
        addSubview(recordingIndicator)
        recordingIndicator.addSubview(recordingDot)
        recordingIndicator.addSubview(recordingLabel)
        addSubview(captureButton)
        captureButton.addSubview(captureInnerView)
        captureButton.layer.addSublayer(recordProgressTrackLayer)
        captureButton.layer.addSublayer(recordProgressLayer)
        addSubview(photoSegmentLabel)
        addSubview(videoSegmentLabel)
        addSubview(holdHintLabel)

        captureCenterX = captureButton.centerXAnchor.constraint(equalTo: centerXAnchor)
        captureCenterY = captureButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -36)
        captureWidth = captureButton.widthAnchor.constraint(equalToConstant: 70)
        captureHeight = captureButton.heightAnchor.constraint(equalToConstant: 70)
        let innerCenterX = captureInnerView.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor)
        let innerCenterY = captureInnerView.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor)
        innerWidth = captureInnerView.widthAnchor.constraint(equalToConstant: 56)
        innerHeight = captureInnerView.heightAnchor.constraint(equalToConstant: 56)

        captureCenterX?.isActive = true
        captureCenterY?.isActive = true
        captureWidth?.isActive = true
        captureHeight?.isActive = true
        innerWidth?.isActive = true
        innerHeight?.isActive = true

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            flipButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            flipButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            flipButton.widthAnchor.constraint(equalToConstant: 44),
            flipButton.heightAnchor.constraint(equalToConstant: 44),

            flashButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            flashButton.trailingAnchor.constraint(equalTo: flipButton.leadingAnchor, constant: -4),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalToConstant: 44),

            recordingIndicator.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            recordingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            recordingIndicator.heightAnchor.constraint(equalToConstant: 28),

            recordingDot.leadingAnchor.constraint(equalTo: recordingIndicator.leadingAnchor, constant: 12),
            recordingDot.centerYAnchor.constraint(equalTo: recordingIndicator.centerYAnchor),
            recordingDot.widthAnchor.constraint(equalToConstant: 10),
            recordingDot.heightAnchor.constraint(equalToConstant: 10),

            recordingLabel.leadingAnchor.constraint(equalTo: recordingDot.trailingAnchor, constant: 8),
            recordingLabel.trailingAnchor.constraint(equalTo: recordingIndicator.trailingAnchor, constant: -12),
            recordingLabel.centerYAnchor.constraint(equalTo: recordingIndicator.centerYAnchor),

            innerCenterX,
            innerCenterY,

            videoSegmentLabel.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 60),
            videoSegmentLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),
            videoSegmentLabel.widthAnchor.constraint(equalToConstant: 64),
            videoSegmentLabel.heightAnchor.constraint(equalToConstant: 32),

            photoSegmentLabel.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -60),
            photoSegmentLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),
            photoSegmentLabel.widthAnchor.constraint(equalToConstant: 64),
            photoSegmentLabel.heightAnchor.constraint(equalToConstant: 32),

            holdHintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            holdHintLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -16),
        ])

        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        flipButton.addAction(UIAction { [weak self] _ in self?.handleFlip() }, for: .touchUpInside)
        flashButton.addAction(UIAction { [weak self] _ in self?.handleFlashToggle() }, for: .touchUpInside)
        photoSegmentLabel.addAction(UIAction { [weak self] _ in self?.handleSelectPhoto() }, for: .touchUpInside)
        videoSegmentLabel.addAction(UIAction { [weak self] _ in self?.handleSelectVideo() }, for: .touchUpInside)
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCaptureTap))
        tap.delaysTouchesBegan = false
        captureButton.addGestureRecognizer(tap)
        captureTap = tap

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleCaptureLongPress(_:)))
        longPress.minimumPressDuration = 0.15
        longPress.allowableMovement = 10_000
        longPress.isEnabled = false
        longPress.delegate = self
        captureButton.addGestureRecognizer(longPress)
        captureLongPress = longPress
        tap.require(toFail: longPress)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchZoom(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        pinchZoom = pinch

        updateCaptureGestures()
    }

    private func updateCaptureGestures() {
        if holdToRecordAndZoom {
            captureLongPress?.isEnabled = true
            captureTap?.isEnabled = !isRecording
        } else {
            captureLongPress?.isEnabled = false
            captureTap?.isEnabled = true
        }
    }

    private func updateHoldHint() {
        guard holdToRecordAndZoom else {
            holdHintLabel.isHidden = true
            return
        }
        var text = ChatStrings.cameraHoldForVideoTapForPhoto.localizedString()
        if maxRecordDuration > 0 {
            text += " · \(Int(maxRecordDuration.rounded()))s"
        }
        holdHintLabel.text = text
        holdHintLabel.isHidden = isRecording
    }

    private func updateSingleShutterChrome() {
        let hideModes = holdToRecordAndZoom || isRecording
        photoSegmentLabel.isHidden = hideModes
        videoSegmentLabel.isHidden = hideModes
        captureCenterY?.constant = holdToRecordAndZoom ? -20 : -36
    }

    @objc private func handleCaptureTap() {
        if holdToRecordAndZoom {
            capturePhoto()
            return
        }
        switch captureMode {
        case .photo:
            capturePhoto()
        case .video:
            if isRecording { stopRecording() } else { startRecording() }
        }
    }

    private func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        animatePressIn()
        onCapturePhoto?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.animatePressOut()
            self?.isCapturing = false
        }
    }

    @objc private func handleSelectPhoto() {
        guard captureMode != .photo, !isRecording else { return }
        captureMode = .photo
    }

    @objc private func handleSelectVideo() {
        guard captureMode != .video, !isRecording else { return }
        captureMode = .video
    }

    @objc private func handleCaptureLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            holdBeganPoint = gesture.location(in: self)
            holdStartZoom = currentZoomFactor
            startRecording()
        case .changed:
            guard isRecording, !isPinching else { return }
            applyHoldSlideZoom(at: gesture.location(in: self))
        case .ended, .cancelled, .failed:
            isPinching = false
            resetZoomTracking()
            stopRecording()
        default:
            break
        }
    }

    @objc private func handlePinchZoom(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            isPinching = true
            pinchStartZoom = currentZoomFactor
        case .changed:
            let next = pinchStartZoom * gesture.scale
            publishZoom(next)
        case .ended, .cancelled, .failed:
            isPinching = false
            if !isRecording {
                resetZoomTracking()
            }
        default:
            break
        }
    }

    private func applyHoldSlideZoom(at point: CGPoint) {
        let travel = max(bounds.height * 0.28, 140)
        let deltaY = holdBeganPoint.y - point.y
        let next: CGFloat
        if deltaY >= 0 {
            let progress = min(deltaY / travel, 1)
            next = holdStartZoom + (maxZoomFactor - holdStartZoom) * progress
        } else {
            let progress = min(-deltaY / travel, 1)
            next = holdStartZoom + (minZoomFactor - holdStartZoom) * progress
        }
        publishZoom(next)
    }

    private func publishZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, minZoomFactor), maxZoomFactor)
        guard abs(clamped - currentZoomFactor) > 0.005 else { return }
        currentZoomFactor = clamped
        let span = max(maxZoomFactor - minZoomFactor, 0.001)
        onZoomChanged?((clamped - minZoomFactor) / span)
        onZoomFactorChanged?(clamped)
    }

    private func resetZoomTracking() {
        currentZoomFactor = minZoomFactor
        holdStartZoom = minZoomFactor
        pinchStartZoom = minZoomFactor
        onZoomChanged?(0)
        onZoomFactorChanged?(minZoomFactor)
    }

    private func handleFlip() {
        guard !isRecording else { return }
        onFlip?()
    }

    private func handleFlashToggle() {
        switch flashMode {
        case .auto: flashMode = .on
        case .on:   flashMode = .off
        case .off:  flashMode = .auto
        }
        onFlashModeChanged?(flashMode)
    }

    func setFlashVisible(_ visible: Bool) {
        flashButton.isHidden = !visible
    }

    private func updateFlashIcon() {
        let iconName: String
        switch flashMode {
        case .auto:
            iconName = "bolt.badge.automatic"
            flashButton.tintColor = .white
        case .on:
            iconName = "bolt.fill"
            flashButton.tintColor = ChatTheme.primary
        case .off:
            iconName = "bolt.slash.fill"
            flashButton.tintColor = .white
        }
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        flashButton.setImage(UIImage(systemName: iconName, withConfiguration: cfg), for: .normal)
    }

    private func updateModeAppearance() {
        let isPhoto = captureMode == .photo
        photoSegmentLabel.setTitleColor(isPhoto ? ChatTheme.warning : UIColor.white.withAlphaComponent(0.5), for: .normal)
        videoSegmentLabel.setTitleColor(isPhoto ? UIColor.white.withAlphaComponent(0.5) : ChatTheme.warning, for: .normal)

        UIView.animate(withDuration: 0.15) {
            self.photoSegmentLabel.transform = isPhoto ? CGAffineTransform(scaleX: 1.1, y: 1.1) : .identity
            self.videoSegmentLabel.transform = isPhoto ? .identity : CGAffineTransform(scaleX: 1.1, y: 1.1)
        }

        if !isRecording {
            let usePhotoShutter = isPhoto || holdToRecordAndZoom
            if usePhotoShutter {
                captureButton.layer.borderColor = UIColor.white.cgColor
                captureInnerView.backgroundColor = .white
            } else {
                captureButton.layer.borderColor = ChatTheme.error.cgColor
                captureInnerView.backgroundColor = ChatTheme.error
            }
        }
        updateCaptureGestures()
    }

    private func startRecording() {
        guard !isRecording else { return }
        let started = onStartRecording?() ?? false
        guard started else {
            onRecordingFailed?()
            return
        }
        isRecording = true
        recordStartTime = Date()
        recordingIndicator.isHidden = false
        startRecordingDotBlink()
        updateSingleShutterChrome()
        holdHintLabel.isHidden = true
        if holdToRecordAndZoom {
            applyHoldRecordingMetrics()
            layoutIfNeeded()
            startRecordProgressRing()
        } else {
            animateToRecordingState()
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.animateRecordingPulse()
            }
        }
        labelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateRecordingLabel()
        }
        updateRecordingLabel()
        scheduleMaxDurationStop()
        updateCaptureGestures()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        maxDurationWorkItem?.cancel()
        maxDurationWorkItem = nil
        pulseTimer?.invalidate()
        labelTimer?.invalidate()
        pulseTimer = nil
        labelTimer = nil
        recordStartTime = nil
        recordingIndicator.isHidden = true
        stopRecordingDotBlink()
        updateSingleShutterChrome()
        updateHoldHint()
        recordingLabel.text = "0:00"
        captureButton.transform = .identity
        hideRecordProgressRing()
        animateToIdleState()
        updateCaptureGestures()
        onStopRecording?()
    }

    private func scheduleMaxDurationStop() {
        maxDurationWorkItem?.cancel()
        guard maxRecordDuration > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.resetZoomTracking()
            self?.stopRecording()
        }
        maxDurationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maxRecordDuration, execute: work)
    }

    private func startRecordProgressRing() {
        guard maxRecordDuration > 0 else { return }
        updateRecordProgressPath()
        captureButton.layer.borderWidth = 0
        recordProgressTrackLayer.isHidden = false
        recordProgressLayer.isHidden = false
        recordProgressLayer.removeAllAnimations()
        recordProgressLayer.strokeEnd = 0

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = maxRecordDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        recordProgressLayer.add(animation, forKey: "recordProgress")
    }

    private func hideRecordProgressRing() {
        recordProgressLayer.removeAllAnimations()
        recordProgressLayer.strokeEnd = 0
        recordProgressTrackLayer.isHidden = true
        recordProgressLayer.isHidden = true
        captureButton.layer.borderWidth = 5
    }

    private func updateRecordProgressPath() {
        let bounds = captureButton.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let lineWidth: CGFloat = 5
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(min(bounds.width, bounds.height) / 2 - lineWidth / 2, 1)
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        recordProgressTrackLayer.path = path.cgPath
        recordProgressLayer.path = path.cgPath
        recordProgressTrackLayer.frame = bounds
        recordProgressLayer.frame = bounds
    }

    func resetToIdle() {
        if isRecording {
            maxDurationWorkItem?.cancel()
            maxDurationWorkItem = nil
            pulseTimer?.invalidate()
            labelTimer?.invalidate()
            pulseTimer = nil
            labelTimer = nil
            recordStartTime = nil
            isRecording = false
            recordingIndicator.isHidden = true
            stopRecordingDotBlink()
            updateSingleShutterChrome()
            updateHoldHint()
            recordingLabel.text = "0:00"
            captureButton.transform = .identity
            hideRecordProgressRing()
            animateToIdleState()
        }
        isCapturing = false
        resetZoomTracking()
    }

    private func startRecordingDotBlink() {
        recordingDot.layer.removeAnimation(forKey: "recordingDotBlink")
        recordingDot.alpha = 1
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0.15
        blink.duration = 0.45
        blink.autoreverses = true
        blink.repeatCount = .infinity
        blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        recordingDot.layer.add(blink, forKey: "recordingDotBlink")
    }

    private func stopRecordingDotBlink() {
        recordingDot.layer.removeAnimation(forKey: "recordingDotBlink")
        recordingDot.alpha = 1
    }

    private func updateRecordingLabel() {
        guard let start = recordStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let m = elapsed / 60
        let s = elapsed % 60
        recordingLabel.text = String(format: "%d:%02d", m, s)
    }

    private func animatePressIn() {
        UIView.animate(withDuration: 0.1) {
            self.captureButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    private func animatePressOut() {
        UIView.animate(withDuration: 0.15, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            self.captureButton.transform = .identity
        }
    }

    private func applyHoldRecordingMetrics() {
        captureWidth?.constant = 84
        captureHeight?.constant = 84
        captureButton.layer.cornerRadius = 42
        captureButton.layer.borderWidth = maxRecordDuration > 0 ? 0 : 5
        innerWidth?.constant = 28
        innerHeight?.constant = 28
        captureInnerView.layer.cornerRadius = 14
        captureInnerView.backgroundColor = ChatTheme.error
    }

    private func animateToRecordingState() {
        captureWidth?.constant = 50
        captureHeight?.constant = 50
        captureButton.layer.cornerRadius = 25
        captureButton.layer.borderWidth = 4
        innerWidth?.constant = 20
        innerHeight?.constant = 20
        captureInnerView.layer.cornerRadius = 4
        captureInnerView.backgroundColor = ChatTheme.error
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4) {
            self.layoutIfNeeded()
        }
    }

    private func animateToIdleState() {
        captureWidth?.constant = 70
        captureHeight?.constant = 70
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 5
        innerWidth?.constant = 56
        innerHeight?.constant = 56
        captureInnerView.layer.cornerRadius = 28
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4) {
            self.layoutIfNeeded()
        }
        updateModeAppearance()
    }

    private var pulseToggle = false
    private func animateRecordingPulse() {
        pulseToggle.toggle()
        let scale: CGFloat = pulseToggle ? 1.15 : 1.0
        UIView.animate(withDuration: 0.5, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.captureButton.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isRecording, maxRecordDuration > 0 {
            updateRecordProgressPath()
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        enforceRTLIfNeeded()
    }
}

extension CameraOverlayView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === pinchZoom, touch.view is UIControl {
            return false
        }
        return true
    }
}
