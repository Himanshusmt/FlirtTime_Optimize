import UIKit
import AVFoundation
import CoreImage

enum ChatCameraOutput {
    case image(UIImage)
    case video(URL, cropAspect: CGFloat?)
}

final class ChatCameraController: UIViewController {

    var onSend: ((ChatCameraOutput) -> Void)?
    var onCancel: (() -> Void)?
    /// Snapchat-style hold-to-record + slide-up zoom. New Thread sets this.
    var holdToRecordAndZoom = false
    /// Auto-stop recording. `0` means no limit.
    var maxVideoDuration: TimeInterval = 0

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.onevibe.chatCamera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let videoDataQueue = DispatchQueue(label: "com.onevibe.chatCamera.video")
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private var cameraInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var usingFrontCamera = false

    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        return layer
    }()

    private let overlay = CameraOverlayView()

    private var captureMode: CameraOverlayView.CaptureMode = .photo
    private var flashMode: AVCaptureDevice.FlashMode = .auto
    private var isRecording = false
    private var isSessionConfigured = false
    private var hasHandledCapture = false

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var lastAppendedPts: CMTime?
    private var recordingURL: URL?
    private var recordingPreviewAspect: CGFloat = 0
    private var recordingCropRect: CGRect = .zero
    private var recordingScaleX: CGFloat = 0
    private var recordingScaleY: CGFloat = 0
    private var recordingOutputSize: CGSize = .zero
    private var cachedAudioFormatHint: CMFormatDescription?

    private var pendingOutput: ChatCameraOutput?

    private let reviewContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let reviewImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.backgroundColor = .black
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let videoLayer = AVPlayerLayer()
    private var videoPlayer: AVPlayer?
    private var videoView: UIView?
    private var endTimeObserver: NSObjectProtocol?

    private let reviewCloseButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.setImage(UIImage(named: ChatAssets.cameraClose), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let retakeButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(ChatStrings.chat_retake.localizedString(), for: .normal)
        btn.titleLabel?.font = UIFont(name: "Fredoka-SemiBold", size: 17) ?? UIFont.chat(.semibold, size: 17)
        btn.setTitleColor(.white, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let sendButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.setTitle(ChatStrings.chat_useMedia.localizedString(), for: .normal)
        btn.titleLabel?.font = UIFont(name: "Fredoka-SemiBold", size: 16) ?? UIFont.chat(.semibold, size: 16)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = ChatTheme.primary
        btn.layer.cornerRadius = 24
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 28, bottom: 0, right: 28)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let processingOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let processingSpinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .large)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let processingLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.chat(.medium, size: 14)
        l.textColor = .white
        l.text = "Processing…"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(previewLayer)

        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.translatesAutoresizingMaskIntoConstraints = true
        overlay.holdToRecordAndZoom = holdToRecordAndZoom
        overlay.maxRecordDuration = maxVideoDuration
        view.addSubview(overlay)
        wireOverlay()

        setupReviewOverlay()

        sessionQueue.async { [weak self] in
            self?.configureSessionIfPossible()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        if let videoView = videoView {
            videoLayer.frame = videoView.bounds
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isSessionConfigured && !self.session.isRunning {
                self.session.startRunning()
            }
        }
        if let player = videoPlayer {
            player.seek(to: .zero)
            player.play()
        }
        view.enforceRTLIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        videoPlayer?.pause()
        sessionQueue.async { [weak self] in
            self?.applyTorchOnSessionQueue(false)
            self?.session.stopRunning()
        }
    }

    deinit {
        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        videoPlayer?.pause()
        videoPlayer = nil
        if let writer = assetWriter, writer.status == .writing {
            writer.cancelWriting()
        }
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
    }

    private func wireOverlay() {
        overlay.onClose = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) {
                self.onCancel?()
            }
        }
        overlay.onCapturePhoto = { [weak self] in
            self?.capturePhoto()
        }
        overlay.onStartRecording = { [weak self] in
            return self?.startRecording() ?? false
        }
        overlay.onStopRecording = { [weak self] in
            self?.stopRecording()
        }
        overlay.onFlip = { [weak self] in
            self?.flipCamera()
        }
        overlay.onFlashModeChanged = { [weak self] mode in
            switch mode {
            case .auto: self?.flashMode = .auto
            case .on:   self?.flashMode = .on
            case .off:  self?.flashMode = .off
            }
            self?.applyTorchIfNeeded()
        }
        overlay.onCaptureModeChanged = { [weak self] mode in
            self?.setCaptureMode(mode)
        }
        overlay.onRecordingFailed = { [weak self] in
            self?.presentMicPermissionAlert()
        }
        overlay.onZoomFactorChanged = { [weak self] factor in
            self?.setZoomFactor(factor)
        }
    }

    private func configureSessionIfPossible() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            requestCameraPermission()
            return
        }

        session.beginConfiguration()
        session.sessionPreset = holdToRecordAndZoom ? .high : .photo

        addCameraInput()
        guard cameraInput != nil else {
            session.commitConfiguration()
            return
        }
        photoOutput.maxPhotoQualityPrioritization = .balanced
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if holdToRecordAndZoom {
            addVideoDataOutput()
        }

        session.commitConfiguration()
        isSessionConfigured = true
        session.startRunning()
        if holdToRecordAndZoom {
            ensureAudioInput()
        }
        updateFlashAvailability()
        publishZoomLimits()
    }

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                guard granted else {
                    self.dismiss(animated: true) { self.onCancel?() }
                    return
                }
                self.sessionQueue.async {
                    self.configureSessionIfPossible()
                }
            }
        }
    }

    private func addCameraInput() {
        if let existing = cameraInput {
            session.removeInput(existing)
            cameraInput = nil
        }

        let position: AVCaptureDevice.Position = usingFrontCamera ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                cameraInput = input
            }
        } catch {
            AppLogger.debug("[ChatCamera] camera input failed: \(error)")
        }
    }

    private func setCaptureMode(_ mode: CameraOverlayView.CaptureMode) {
        guard mode != captureMode else { return }
        captureMode = mode

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            switch mode {
            case .photo:
                self.session.sessionPreset = .photo
                self.removeVideoDataOutput()
                self.removeAudioDataOutput()
                self.removeAudioInput()
            case .video:
                self.session.sessionPreset = .high
                self.addVideoDataOutput()
            }
            self.session.commitConfiguration()
            if mode == .video {
                self.ensureAudioInput()
            }
        }
    }

    private func addVideoDataOutput() {
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if session.outputs.contains(videoDataOutput) == false, session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
    }

    private func removeVideoDataOutput() {
        if session.outputs.contains(videoDataOutput) {
            session.removeOutput(videoDataOutput)
        }
    }

    private func removeAudioDataOutput() {
        if session.outputs.contains(audioDataOutput) {
            session.removeOutput(audioDataOutput)
        }
    }

    private func ensureAudioInput() {
        guard audioInput == nil else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    guard let self else { return }
                    guard granted else {
                        DispatchQueue.main.async { self.presentMicPermissionAlert() }
                        return
                    }
                    self.sessionQueue.async { self.addAudioInput() }
                }
            } else {
                DispatchQueue.main.async { self.presentMicPermissionAlert() }
            }
            return
        }
        addAudioInput()
    }

    private func addAudioInput() {
        guard audioInput == nil else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
            audioDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
            if session.outputs.contains(audioDataOutput) == false, session.canAddOutput(audioDataOutput) {
                session.addOutput(audioDataOutput)
            }
            session.commitConfiguration()
        } catch {
            AppLogger.debug("[ChatCamera] audio input failed: \(error)")
        }
    }

    private func removeAudioInput() {
        guard let input = audioInput else { return }
        session.removeInput(input)
        if session.outputs.contains(audioDataOutput) {
            session.removeOutput(audioDataOutput)
        }
        audioInput = nil
        cachedAudioFormatHint = nil
    }

    private func flipCamera() {
        guard !isRecording else { return }
        usingFrontCamera.toggle()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyTorchOnSessionQueue(false)
            self.session.beginConfiguration()
            self.addCameraInput()
            self.session.commitConfiguration()
            self.resetZoom()
            self.updateFlashAvailability()
            self.applyTorchIfNeeded()
            self.publishZoomLimits()
        }
    }

    private func updateFlashAvailability() {
        let device = cameraInput?.device
        let available = !usingFrontCamera && (device?.hasFlash == true || device?.hasTorch == true)
        DispatchQueue.main.async { [weak self] in
            self?.overlay.setFlashVisible(available)
        }
    }

    private func applyTorchIfNeeded() {
        let shouldEnable = !usingFrontCamera && flashMode == .on && (isRecording || holdToRecordAndZoom)
        setTorch(shouldEnable)
    }

    private func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            self?.applyTorchOnSessionQueue(on)
        }
    }

    private func applyTorchOnSessionQueue(_ on: Bool) {
        guard let device = cameraInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on, device.isTorchModeSupported(.on) {
                try device.setTorchModeOn(level: 1.0)
            } else if device.isTorchModeSupported(.off) {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            AppLogger.debug("[ChatCamera] torch failed: \(error)")
        }
    }

    private func publishZoomLimits() {
        guard let device = cameraInput?.device else { return }
        let minZ = device.minAvailableVideoZoomFactor
        let maxZ = min(max(device.activeFormat.videoMaxZoomFactor, minZ), 8)
        DispatchQueue.main.async { [weak self] in
            self?.overlay.minZoomFactor = minZ
            self?.overlay.maxZoomFactor = maxZ
        }
    }

    private func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.cameraInput?.device else { return }
            let minZ = device.minAvailableVideoZoomFactor
            let maxZ = min(device.activeFormat.videoMaxZoomFactor, 8)
            let zoom = min(max(factor, minZ), maxZ)
            guard abs(device.videoZoomFactor - zoom) > 0.01 else { return }
            do {
                try device.lockForConfiguration()
                if device.isRampingVideoZoom {
                    device.cancelVideoZoomRamp()
                }
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
            } catch {
                AppLogger.debug("[ChatCamera] zoom failed: \(error)")
            }
        }
    }

    private func resetZoom() {
        sessionQueue.async { [weak self] in
            guard let device = self?.cameraInput?.device else { return }
            let minZ = device.minAvailableVideoZoomFactor
            guard abs(device.videoZoomFactor - minZ) > 0.01 else { return }
            do {
                try device.lockForConfiguration()
                if device.isRampingVideoZoom {
                    device.cancelVideoZoomRamp()
                }
                device.videoZoomFactor = minZ
                device.unlockForConfiguration()
            } catch {
                AppLogger.debug("[ChatCamera] reset zoom failed: \(error)")
            }
        }
    }

    private func capturePhoto() {
        guard !hasHandledCapture else { return }
        guard isSessionConfigured,
              let connection = photoOutput.connection(with: .video),
              connection.isActive, connection.isEnabled else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = self.usingFrontCamera ? .off : self.flashMode
            
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = self.usingFrontCamera
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func startRecording() -> Bool {
        guard !isRecording else { return false }

        var ready = false
        sessionQueue.sync {
            if self.session.outputs.contains(self.videoDataOutput) == false {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                self.addVideoDataOutput()
                self.session.commitConfiguration()
            }
            if let connection = self.videoDataOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = self.usingFrontCamera
                }
            }
            ready = self.session.outputs.contains(self.videoDataOutput)
        }
        guard ready else { return false }

        ensureAudioInput()

        recordingPreviewAspect = view.bounds.width / max(view.bounds.height, 1)
        assetWriter = nil
        videoInput = nil
        audioWriterInput = nil
        pixelAdaptor = nil
        sessionStarted = false
        lastAppendedPts = nil
        recordingURL = nil
        recordingOutputSize = .zero
        recordingCropRect = .zero
        recordingScaleX = 0
        recordingScaleY = 0
        isRecording = true
        applyTorchIfNeeded()
        return true
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if flashMode != .on {
            setTorch(false)
        }
        resetZoom()
        showProcessing(true)
        videoDataQueue.async { [weak self] in
            self?.finalizeRecording()
        }
    }

    private func finalizeRecording() {
        videoInput?.markAsFinished()
        audioWriterInput?.markAsFinished()

        guard let writer = assetWriter else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.showProcessing(false)
            }
            return
        }

        let capturedURL = recordingURL
        writer.finishWriting { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.showProcessing(false)
                if writer.status == .completed, let url = capturedURL {
                    self.enterReview(.video(url, cropAspect: nil))
                } else {
                    if let url = capturedURL { try? FileManager.default.removeItem(at: url) }
                    self.presentRecordingFailedAlert()
                }
            }
        }
    }

    private func presentRecordingFailedAlert() {
        let alert = UIAlertController(
            title: "Recording Failed",
            message: "The video could not be saved. Please try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func handleVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }
        if assetWriter == nil {
            guard setupWriter(using: sampleBuffer) else { return }
        }
        guard let writer = assetWriter, writer.status == .writing else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if sessionStarted == false {
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }

        if let last = lastAppendedPts {
            let delta = CMTimeSubtract(pts, last)
            if CMTimeGetSeconds(delta) < (1.0 / 30.0) { return }
        }

        guard videoInput?.isReadyForMoreMediaData == true else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard recordingOutputSize.width > 0, recordingOutputSize.height > 0 else { return }

        var ci = CIImage(cvPixelBuffer: pixelBuffer)

        if recordingCropRect.width > 0, recordingCropRect.height > 0 {
            ci = ci.cropped(to: recordingCropRect)
        }

        let scaled = ci
            .transformed(by: CGAffineTransform(translationX: -recordingCropRect.origin.x, y: -recordingCropRect.origin.y))
            .transformed(by: CGAffineTransform(scaleX: recordingScaleX, y: recordingScaleY))

        guard let outputBuffer = makeOutputPixelBuffer() else { return }
        ciContext.render(scaled, to: outputBuffer)
        pixelAdaptor?.append(outputBuffer, withPresentationTime: pts)
        lastAppendedPts = pts
    }

    private func handleAudioSample(_ sampleBuffer: CMSampleBuffer) {
        if cachedAudioFormatHint == nil {
            cachedAudioFormatHint = CMSampleBufferGetFormatDescription(sampleBuffer)
        }
        guard isRecording else { return }
        guard let writer = assetWriter, writer.status == .writing, sessionStarted else { return }
        guard let aInput = audioWriterInput, aInput.isReadyForMoreMediaData else { return }
        aInput.append(sampleBuffer)
    }

    private func setupWriter(using sampleBuffer: CMSampleBuffer) -> Bool {
        guard recordingPreviewAspect > 0 else { return false }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }

        let extent = CIImage(cvPixelBuffer: pixelBuffer).extent
        guard extent.width > 0, extent.height > 0 else { return false }

        let extW = extent.width
        let extH = extent.height
        let cropRect: CGRect
        if (extW / extH) > recordingPreviewAspect {
            let cropW = extH * recordingPreviewAspect
            cropRect = CGRect(x: extent.origin.x + (extW - cropW) / 2, y: extent.origin.y, width: cropW, height: extH)
        } else {
            let cropH = extW / recordingPreviewAspect
            cropRect = CGRect(x: extent.origin.x, y: extent.origin.y + (extH - cropH) / 2, width: extW, height: cropH)
        }
        recordingCropRect = cropRect

        let maxDim: CGFloat = 1280
        let baseScale = maxDim / max(cropRect.width, cropRect.height)
        let rawW = (cropRect.width * baseScale).rounded()
        let rawH = (cropRect.height * baseScale).rounded()
        let outW = (rawW / 2).rounded(.up) * 2
        let outH = (rawH / 2).rounded(.up) * 2
        recordingOutputSize = CGSize(width: outW, height: outH)
        recordingScaleX = outW / cropRect.width
        recordingScaleY = outH / cropRect.height

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatCamera_\(UUID().uuidString).mp4")
        recordingURL = url

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outW),
            AVVideoHeightKey: Int(outH),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_500_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outW),
                kCVPixelBufferHeightKey as String: Int(outH)
            ]
        )
        guard writer.canAdd(vInput) else { return false }
        writer.add(vInput)

        if let audioHint = cachedAudioFormatHint {
            var audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVEncoderBitRateKey: 128_000
            ]
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioHint)?.pointee {
                audioSettings[AVSampleRateKey] = asbd.mSampleRate
                audioSettings[AVNumberOfChannelsKey] = Int(asbd.mChannelsPerFrame)
            }
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: audioHint)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) {
                writer.add(aInput)
                audioWriterInput = aInput
            }
        }

        guard writer.startWriting() else {
            AppLogger.debug("[ChatCamera] writer startWriting failed: \(String(describing: writer.error))")
            return false
        }

        assetWriter = writer
        videoInput = vInput
        pixelAdaptor = adaptor
        return true
    }

    private func makeOutputPixelBuffer() -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(recordingOutputSize.width),
            Int(recordingOutputSize.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        return status == kCVReturnSuccess ? pb : nil
    }

    private func presentMicPermissionAlert() {
        let alert = UIAlertController(
            title: "Microphone Needed",
            message: "Allow microphone access in Settings to record video with sound.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel))
        present(alert, animated: true)
    }

    private func setupReviewOverlay() {
        view.addSubview(reviewContainer)
        reviewContainer.addSubview(reviewImageView)

        reviewContainer.addSubview(reviewCloseButton)
        reviewContainer.addSubview(retakeButton)
        reviewContainer.addSubview(sendButton)

        view.addSubview(processingOverlay)
        processingOverlay.addSubview(processingSpinner)
        processingOverlay.addSubview(processingLabel)

        NSLayoutConstraint.activate([
            reviewContainer.topAnchor.constraint(equalTo: view.topAnchor),
            reviewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reviewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            reviewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            reviewImageView.topAnchor.constraint(equalTo: reviewContainer.topAnchor),
            reviewImageView.leadingAnchor.constraint(equalTo: reviewContainer.leadingAnchor),
            reviewImageView.trailingAnchor.constraint(equalTo: reviewContainer.trailingAnchor),
            reviewImageView.bottomAnchor.constraint(equalTo: reviewContainer.bottomAnchor),

            reviewCloseButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            reviewCloseButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            reviewCloseButton.widthAnchor.constraint(equalToConstant: 40),
            reviewCloseButton.heightAnchor.constraint(equalToConstant: 40),

            retakeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            retakeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            retakeButton.heightAnchor.constraint(equalToConstant: 48),

            sendButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            sendButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            sendButton.heightAnchor.constraint(equalToConstant: 48),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

            processingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            processingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            processingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            processingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            processingSpinner.centerXAnchor.constraint(equalTo: processingOverlay.centerXAnchor),
            processingSpinner.centerYAnchor.constraint(equalTo: processingOverlay.centerYAnchor, constant: -10),
            processingLabel.topAnchor.constraint(equalTo: processingSpinner.bottomAnchor, constant: 12),
            processingLabel.centerXAnchor.constraint(equalTo: processingOverlay.centerXAnchor),
        ])

        reviewCloseButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: true) { self.onCancel?() }
        }, for: .touchUpInside)

        retakeButton.addAction(UIAction { [weak self] _ in
            self?.exitReview()
        }, for: .touchUpInside)

        sendButton.addAction(UIAction { [weak self] _ in
            self?.sendCurrent()
        }, for: .touchUpInside)
    }

    private func showProcessing(_ show: Bool) {
        processingOverlay.isHidden = !show
        sendButton.isEnabled = !show
        retakeButton.isEnabled = !show
        reviewCloseButton.isEnabled = !show
        if show { processingSpinner.startAnimating() } else { processingSpinner.stopAnimating() }
    }

    private func setupVideoPlayer(url: URL) {
        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
            endTimeObserver = nil
        }
        videoPlayer?.pause()
        videoPlayer = nil

        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        videoLayer.player = player
        videoLayer.videoGravity = .resizeAspectFill
        videoPlayer = player

        if videoView == nil {
            let v = UIView()
            v.backgroundColor = .black
            v.translatesAutoresizingMaskIntoConstraints = false
            reviewContainer.insertSubview(v, belowSubview: reviewImageView)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: reviewContainer.topAnchor),
                v.leadingAnchor.constraint(equalTo: reviewContainer.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: reviewContainer.trailingAnchor),
                v.bottomAnchor.constraint(equalTo: reviewContainer.bottomAnchor),
            ])
            v.layer.addSublayer(videoLayer)
            videoView = v
        } else {
            videoView?.isHidden = false
        }

        reviewContainer.layoutIfNeeded()
        videoLayer.frame = videoView?.bounds ?? reviewContainer.bounds

        endTimeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self, weak player] _ in
            guard let self, let player, player === self.videoPlayer else { return }
            player.seek(to: .zero)
            player.play()
        }

        player.seek(to: .zero)
        player.play()
    }
}

extension ChatCameraController: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            AppLogger.debug("[ChatCamera] photo capture failed: \(String(describing: error))")
            return
        }

        let previewBounds = view.bounds
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let cropped = Self.cropToPreviewAspect(image, previewBounds: previewBounds)
            DispatchQueue.main.async {
                self.enterReview(.image(cropped))
            }
        }
    }

    private func enterReview(_ output: ChatCameraOutput) {
        guard !hasHandledCapture else { return }
        hasHandledCapture = true
        pendingOutput = output

        overlay.isHidden = true
        reviewContainer.isHidden = false

        switch output {
        case .image(let image):
            reviewImageView.image = image
            reviewImageView.isHidden = false
            videoView?.isHidden = true
            videoPlayer?.pause()
        case .video(let url, _):
            reviewImageView.isHidden = true
            setupVideoPlayer(url: url)
        }
    }

    private func exitReview() {
        reviewContainer.isHidden = true
        overlay.isHidden = false
        overlay.resetToIdle()

        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
            endTimeObserver = nil
        }
        videoPlayer?.pause()
        videoPlayer = nil
        videoLayer.player = nil
        reviewImageView.image = nil

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        pendingOutput = nil
        hasHandledCapture = false
    }

    private func sendCurrent() {
        guard let output = pendingOutput else { return }
        pendingOutput = nil

        switch output {
        case .image:
            dismiss(animated: true) { [weak self] in
                self?.onSend?(output)
            }
        case .video(let url, _):
            recordingURL = nil
            dismiss(animated: true) { [weak self] in
                self?.onSend?(.video(url, cropAspect: nil))
            }
        }
    }

    private static func cropToPreviewAspect(_ image: UIImage, previewBounds: CGRect) -> UIImage {
        let previewAspect = previewBounds.width / previewBounds.height
        let imgAspect = image.size.width / image.size.height

        guard imgAspect > previewAspect else { return image }

        let cropWidth = image.size.height * previewAspect
        let xOffset = (image.size.width - cropWidth) / 2.0
        let cropRect = CGRect(x: xOffset, y: 0, width: cropWidth, height: image.size.height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)
        return renderer.image { _ in
            image.draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        }
    }
}

extension ChatCameraController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === videoDataOutput {
            handleVideoSample(sampleBuffer)
        } else if output === audioDataOutput {
            handleAudioSample(sampleBuffer)
        }
    }
}
