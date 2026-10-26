//
//  MediaViewerController.swift
//  FlirttimeNew
//

import AVKit
import Kingfisher
import Photos
import UIKit

// MARK: - Page

final class MediaViewerPage: UIViewController, UIScrollViewDelegate {

    let item: GalleryMediaItem
    let index: Int
    var onSingleTap: (() -> Void)?

    private let placeholderImage: UIImage?
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var playerController: AVPlayerViewController?

    init(item: GalleryMediaItem, index: Int, placeholder: UIImage? = nil) {
        self.item = item
        self.index = index
        self.placeholderImage = placeholder
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        item.isVideo ? setupVideo() : setupImage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playerController?.player?.pause()
    }

    var displayedImage: UIImage? { imageView.image ?? placeholderImage }

    var isZoomed: Bool { scrollView.zoomScale > 1.01 }

    var mediaURL: URL {
        item.localMediaURL(type: item.isVideo ? .video : .image) ?? item.downloadURL ?? item.url
    }

    private func setupImage() {
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        if let local = item.localMediaURL(type: .image), let image = UIImage(contentsOfFile: local.path) {
            imageView.image = image
        } else if let cached = ImageLoader.shared.cachedImage(for: item.url) {
            imageView.image = cached
        } else {
            let thumbnail = item.thumbnailURL.flatMap { ImageLoader.shared.cachedImage(for: $0) }
                ?? placeholderImage
            imageView.kf.indicatorType = thumbnail == nil ? .activity : .none
            imageView.setChatImage(
                with: item.url,
                placeholderImage: thumbnail ?? UIImage(named: ChatAssets.imagePlaceholder),
                options: [.retryFailed, .highPriority]
            )
        }

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
    }

    private func setupVideo() {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: mediaURL)
        controller.videoGravity = .resizeAspect
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        playerController = controller
    }

    func setPlaybackActive(_ active: Bool) {
        guard let player = playerController?.player else { return }
        active ? player.play() : player.pause()
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
            scrollView.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}

// MARK: - Viewer

final class MediaViewerController: UIViewController {

    private let items: [GalleryMediaItem]
    private let initialIndex: Int
    private var currentIndex: Int
    private weak var sourceView: UIImageView?
    private let sourceCornerRadius: CGFloat
    private let openingPlaceholder: UIImage?
    private let animatesFromSource: Bool
    private let showsPageIndicator: Bool

    /// Live lookup so dismiss can land on the current carousel photo, not only the one that was tapped.
    var sourceViewProvider: ((Int) -> UIImageView?)?

    private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 16])
    private let topBar = UIView()
    private let pageIndicator = MediaViewerPageIndicator()
    private let closeButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var controlsVisible = true

    private var hasPlayedOpenAnimation = false
    private var isAnimatingTransition = false
    private var zoomOverlay: MediaZoomOverlay?

    var onDismiss: (() -> Void)?

    init(
        items: [GalleryMediaItem],
        initialIndex: Int,
        sourceView: UIImageView? = nil,
        sourceCornerRadius: CGFloat? = nil,
        showsPageIndicator: Bool = true
    ) {
        self.items = items
        self.initialIndex = min(max(initialIndex, 0), max(items.count - 1, 0))
        self.currentIndex = self.initialIndex
        self.sourceView = sourceView
        self.sourceCornerRadius = sourceCornerRadius ?? sourceView?.layer.cornerRadius ?? 0
        self.openingPlaceholder = sourceView?.image
        self.animatesFromSource = sourceView != nil
        self.showsPageIndicator = showsPageIndicator
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersStatusBarHidden: Bool { !controlsVisible }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = animatesFromSource ? .clear : .black
        setupPager()
        setupTopBar()
        setupPageIndicator()
        updateHeader()

        if animatesFromSource {
            pageVC.view.alpha = 0
            setControlsAlpha(0)
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasPlayedOpenAnimation, view.bounds.width > 1 {
            hasPlayedOpenAnimation = true
            playOpeningAnimation()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isAnimatingTransition, hasPlayedOpenAnimation {
            currentPage?.setPlaybackActive(true)
        }
    }

    private var currentPage: MediaViewerPage? {
        pageVC.viewControllers?.first as? MediaViewerPage
    }

    private func makePage(at index: Int) -> MediaViewerPage? {
        guard items.indices.contains(index) else { return nil }
        let placeholder = index == initialIndex ? openingPlaceholder : nil
        let page = MediaViewerPage(item: items[index], index: index, placeholder: placeholder)
        page.onSingleTap = { [weak self] in self?.toggleControls() }
        return page
    }

    private func setupPager() {
        pageVC.dataSource = self
        pageVC.delegate = self
        addChild(pageVC)
        pageVC.view.frame = view.bounds
        pageVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pageVC.view)
        pageVC.didMove(toParent: self)
        if let first = makePage(at: currentIndex) {
            pageVC.setViewControllers([first], direction: .forward, animated: false)
        }
    }

    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.addSubview(topBar)

        configure(closeButton, symbol: "xmark", action: #selector(closeTapped))
        configure(shareButton, symbol: "square.and.arrow.up", action: #selector(shareTapped))
        configure(saveButton, symbol: "arrow.down.to.line", action: #selector(saveTapped))

        titleLabel.font = .chatSemiBold(size: 16)
        titleLabel.textColor = .white
        subtitleLabel.font = .chatRegular(size: 12)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.75)

        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 2

        let row = UIStackView(arrangedSubviews: [closeButton, titles, UIView(), shareButton, saveButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(row)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            row.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            row.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            shareButton.widthAnchor.constraint(equalToConstant: 36),
            saveButton.widthAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func setupPageIndicator() {
        pageIndicator.translatesAutoresizingMaskIntoConstraints = false
        pageIndicator.isHidden = !showsPageIndicator || items.count < 2
        view.addSubview(pageIndicator)
        NSLayoutConstraint.activate([
            pageIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageIndicator.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func configure(_ button: UIButton, symbol: String, action: Selector) {
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func updateHeader() {
        guard items.indices.contains(currentIndex) else { return }
        let item = items[currentIndex]
        titleLabel.text = item.senderName
        if let date = item.timestamp {
            subtitleLabel.text = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        } else {
            subtitleLabel.text = items.count > 1 ? "\(currentIndex + 1) / \(items.count)" : nil
        }
        if showsPageIndicator {
            pageIndicator.numberOfPages = items.count
            pageIndicator.setCurrentPage(currentIndex, animated: true)
        }
    }

    private func setControlsAlpha(_ alpha: CGFloat) {
        topBar.alpha = alpha
        pageIndicator.alpha = showsPageIndicator && items.count > 1 ? alpha : 0
    }

    private func toggleControls() {
        guard !isAnimatingTransition else { return }
        controlsVisible.toggle()
        UIView.animate(withDuration: 0.2) {
            self.setControlsAlpha(self.controlsVisible ? 1 : 0)
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }

    // MARK: Actions

    @objc private func closeTapped() {
        dismissViewer()
    }

    private func dismissViewer() {
        guard !isAnimatingTransition else { return }
        currentPage?.setPlaybackActive(false)
        playClosingAnimation()
    }

    @objc private func shareTapped() {
        guard let page = currentPage else { return }
        let activityItems: [Any] = page.item.isVideo ? [page.mediaURL] : [page.displayedImage ?? page.mediaURL]
        let activity = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = shareButton
        present(activity, animated: true)
    }

    @objc private func saveTapped() {
        guard let page = currentPage else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                GlobalToast.shared.show(ChatStrings.chat_accessToPhotosDenied.localizedString())
                return
            }
            if page.item.isVideo {
                self?.saveVideo(from: page.mediaURL)
            } else if let image = page.displayedImage {
                self?.performSave { PHAssetChangeRequest.creationRequestForAsset(from: image) }
            }
        }
    }

    private func saveVideo(from url: URL) {
        if url.isFileURL {
            performSave { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
            return
        }
        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, _ in
            guard let tempURL else {
                GlobalToast.shared.show(ChatStrings.chat_failedToSave.localizedString())
                return
            }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            try? FileManager.default.moveItem(at: tempURL, to: target)
            self?.performSave { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: target) }
        }.resume()
    }

    private func performSave(_ change: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges(change) { success, _ in
            GlobalToast.shared.show(success
                ? ChatStrings.chat_savedToPhotos.localizedString()
                : ChatStrings.chat_failedToSave.localizedString())
        }
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard !isAnimatingTransition else { return }
        switch gesture.state {
        case .began:
            beginInteractiveDismiss()
        case .changed:
            updateInteractiveDismiss(translation: gesture.translation(in: view))
        case .ended, .cancelled:
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view).y
            if gesture.state == .ended, (abs(translation.y) > 120 || abs(velocity) > 900) {
                finishInteractiveDismiss()
            } else {
                cancelInteractiveDismiss()
            }
        default:
            break
        }
    }

    private func finishPresentation() {
        dismiss(animated: false) { [onDismiss] in onDismiss?() }
    }
}

// MARK: - Thread-style zoom

private extension MediaViewerController {

    func playOpeningAnimation() {
        view.layoutIfNeeded()
        guard let sourceFrame = resolvedSourceFrame(),
              let image = transitionImage() else {
            playFallbackOpen()
            return
        }

        isAnimatingTransition = true
        let destFrame = MediaViewerZoomGeometry.aspectFitRect(for: image.size, in: view.bounds)
        let overlay = makeOverlay(image: image, frame: sourceFrame, filled: true, radius: resolvedCornerRadius())
        zoomOverlay = overlay
        hideResolvedSource(true)

        animateDim(to: .black, duration: 0.18)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
            self.setControlsAlpha(self.controlsVisible ? 1 : 0)
        }
        animateZoom(presenting: true, animations: {
            overlay.frame = destFrame
            overlay.layer.cornerRadius = 0
            overlay.layoutImage(filled: false)
        }, completion: { [weak self] in
            guard let self else { return }
            self.pageVC.view.alpha = 1
            self.view.backgroundColor = .black
            overlay.removeFromSuperview()
            self.zoomOverlay = nil
            self.hideResolvedSource(false)
            self.isAnimatingTransition = false
            self.currentPage?.setPlaybackActive(true)
        })
    }

    func playClosingAnimation() {
        view.layoutIfNeeded()
        let image = transitionImage()
        let sourceFrame = resolvedSourceFrame()
        let sourceHidden = resolvedSourceView()

        isAnimatingTransition = true
        setControlsAlpha(0)
        pageVC.view.alpha = 0
        currentPage?.setPlaybackActive(false)

        guard let image, let sourceFrame else {
            playFallbackClose()
            return
        }

        sourceHidden?.alpha = 0
        let startFrame = MediaViewerZoomGeometry.aspectFitRect(for: image.size, in: view.bounds)
        let overlay = makeOverlay(image: image, frame: startFrame, filled: false, radius: 0)
        zoomOverlay = overlay

        animateDim(to: .clear, duration: 0.16)
        animateZoom(presenting: false, animations: {
            overlay.frame = sourceFrame
            overlay.layer.cornerRadius = self.resolvedCornerRadius()
            overlay.layoutImage(filled: true)
        }, completion: { [weak self] in
            sourceHidden?.alpha = 1
            overlay.removeFromSuperview()
            self?.zoomOverlay = nil
            self?.finishPresentation()
        })
    }

    func playFallbackOpen() {
        pageVC.view.alpha = 0
        pageVC.view.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        setControlsAlpha(0)
        isAnimatingTransition = true
        animateDim(to: .black, duration: 0.16)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
            self.pageVC.view.alpha = 1
            self.pageVC.view.transform = .identity
            self.setControlsAlpha(1)
        } completion: { _ in
            self.isAnimatingTransition = false
            self.currentPage?.setPlaybackActive(true)
        }
    }

    func playFallbackClose() {
        isAnimatingTransition = true
        UIView.animate(withDuration: 0.16, animations: {
            self.pageVC.view.alpha = 0
            self.pageVC.view.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            self.setControlsAlpha(0)
            self.view.backgroundColor = .clear
        }, completion: { _ in
            self.finishPresentation()
        })
    }

    func beginInteractiveDismiss() {
        guard zoomOverlay == nil else { return }
        let image = transitionImage()
        let startFrame: CGRect
        if let image {
            startFrame = MediaViewerZoomGeometry.aspectFitRect(for: image.size, in: view.bounds)
        } else {
            startFrame = view.bounds
        }
        currentPage?.setPlaybackActive(false)
        setControlsAlpha(0)
        pageVC.view.alpha = 0
        hideResolvedSource(true)
        let overlay = makeOverlay(image: image, frame: startFrame, filled: false, radius: 0)
        zoomOverlay = overlay
    }

    func updateInteractiveDismiss(translation: CGPoint) {
        guard let overlay = zoomOverlay else { return }
        let progress = min(1, hypot(translation.x, translation.y) / 360)
        let scale = max(0.72, 1 - progress * 0.22)
        overlay.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
            .scaledBy(x: scale, y: scale)
        overlay.layer.cornerRadius = resolvedCornerRadius() * progress
        view.backgroundColor = UIColor.black.withAlphaComponent(max(0.18, 1 - progress))
    }

    func finishInteractiveDismiss() {
        guard let overlay = zoomOverlay else {
            playClosingAnimation()
            return
        }
        isAnimatingTransition = true
        let currentFrame = overlay.superview?.convert(overlay.layer.presentation()?.frame ?? overlay.frame, to: view)
            ?? overlay.frame
        overlay.transform = .identity
        overlay.frame = currentFrame
        overlay.layoutImage(filled: false)

        guard let sourceFrame = resolvedSourceFrame() else {
            animateDim(to: .clear, duration: 0.16)
            UIView.animate(withDuration: 0.16, animations: {
                overlay.alpha = 0
                overlay.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                self.view.backgroundColor = .clear
            }, completion: { _ in
                overlay.removeFromSuperview()
                self.zoomOverlay = nil
                self.hideResolvedSource(false)
                self.finishPresentation()
            })
            return
        }

        hideResolvedSource(true)
        animateDim(to: .clear, duration: 0.16)
        animateZoom(presenting: false, animations: {
            overlay.frame = sourceFrame
            overlay.layer.cornerRadius = self.resolvedCornerRadius()
            overlay.layoutImage(filled: true)
        }, completion: { [weak self] in
            self?.hideResolvedSource(false)
            overlay.removeFromSuperview()
            self?.zoomOverlay = nil
            self?.finishPresentation()
        })
    }

    func cancelInteractiveDismiss() {
        guard let overlay = zoomOverlay else { return }
        isAnimatingTransition = true
        let image = overlay.image
        let dest = image.map { MediaViewerZoomGeometry.aspectFitRect(for: $0.size, in: view.bounds) } ?? view.bounds
        let currentFrame = overlay.superview?.convert(overlay.layer.presentation()?.frame ?? overlay.frame, to: view)
            ?? overlay.frame
        overlay.transform = .identity
        overlay.frame = currentFrame
        overlay.layoutImage(filled: false)

        animateDim(to: .black, duration: 0.16)
        animateZoom(presenting: true, animations: {
            overlay.frame = dest
            overlay.layer.cornerRadius = 0
            overlay.layoutImage(filled: false)
        }, completion: { [weak self] in
            guard let self else { return }
            self.pageVC.view.alpha = 1
            self.setControlsAlpha(self.controlsVisible ? 1 : 0)
            overlay.removeFromSuperview()
            self.zoomOverlay = nil
            self.hideResolvedSource(false)
            self.isAnimatingTransition = false
            self.currentPage?.setPlaybackActive(true)
        })
    }

    func makeOverlay(image: UIImage?, frame: CGRect, filled: Bool, radius: CGFloat) -> MediaZoomOverlay {
        let overlay = MediaZoomOverlay(image: image)
        overlay.frame = frame
        overlay.layer.cornerRadius = radius
        overlay.layoutImage(filled: filled)
        view.insertSubview(overlay, belowSubview: topBar)
        return overlay
    }

    func animateZoom(presenting: Bool, animations: @escaping () -> Void, completion: (() -> Void)?) {
        UIView.animate(
            withDuration: presenting ? 0.20 : 0.18,
            delay: 0,
            options: [.curveEaseOut, .allowAnimatedContent],
            animations: animations,
            completion: { _ in completion?() }
        )
    }

    func animateDim(to color: UIColor, duration: TimeInterval) {
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
            self.view.backgroundColor = color
        }
    }

    func resolvedSourceView() -> UIImageView? {
        if let provided = sourceViewProvider?(currentIndex), provided.window != nil {
            return provided
        }
        if let sourceView, sourceView.window != nil {
            return sourceView
        }
        return nil
    }

    func resolvedSourceFrame() -> CGRect? {
        guard let source = resolvedSourceView() else { return nil }
        let frame = source.convert(source.bounds, to: view)
        guard frame.width > 1, frame.height > 1, !frame.isNull, !frame.isInfinite else { return nil }
        return frame
    }

    func resolvedCornerRadius() -> CGFloat {
        if sourceCornerRadius > 0 { return sourceCornerRadius }
        return resolvedSourceView()?.layer.cornerRadius ?? 0
    }

    func hideResolvedSource(_ hidden: Bool) {
        resolvedSourceView()?.alpha = hidden ? 0 : 1
    }

    func transitionImage() -> UIImage? {
        currentPage?.displayedImage ?? resolvedSourceView()?.image ?? openingPlaceholder
    }
}

// MARK: - UIPageViewController

extension MediaViewerController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? MediaViewerPage else { return nil }
        return makePage(at: page.index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? MediaViewerPage else { return nil }
        return makePage(at: page.index + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let page = currentPage else { return }
        previousViewControllers.compactMap { $0 as? MediaViewerPage }.forEach { $0.setPlaybackActive(false) }
        currentIndex = page.index
        updateHeader()
        page.setPlaybackActive(true)
    }
}

// MARK: - Gestures

extension MediaViewerController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !isAnimatingTransition else { return false }
        if currentPage?.isZoomed == true { return false }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }
}

// MARK: - Zoom helpers

private enum MediaViewerZoomGeometry {
    static func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 1, imageSize.height > 1, bounds.width > 1, bounds.height > 1 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func aspectFillRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 1, imageSize.height > 1, bounds.width > 1, bounds.height > 1 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// Snapshot that morphs from the feed's aspect-fill crop to the viewer's aspect-fit frame.
private final class MediaZoomOverlay: UIView {
    private let imageView = UIImageView()

    var image: UIImage? { imageView.image }

    init(image: UIImage?) {
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.masksToBounds = true
        layer.cornerCurve = .continuous
        imageView.image = image
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func layoutImage(filled: Bool) {
        let imageSize = imageView.image?.size ?? bounds.size
        if filled {
            imageView.frame = MediaViewerZoomGeometry.aspectFillRect(for: imageSize, in: bounds)
        } else {
            imageView.frame = bounds
        }
    }
}

/// Bottom pager: the current photo's dot is slightly larger than the rest.
private final class MediaViewerPageIndicator: UIView {

    private static let dotSize: CGFloat = 6
    private static let activeSize: CGFloat = 8.5
    private static let spacing: CGFloat = 6

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = MediaViewerPageIndicator.spacing
        return stackView
    }()

    private var dots: [UIView] = []
    private var sizeConstraints: [(width: NSLayoutConstraint, height: NSLayoutConstraint)] = []
    private var currentPage = -1

    var numberOfPages = 0 {
        didSet {
            guard numberOfPages != oldValue else { return }
            rebuildDots()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .updatesFrequently
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setCurrentPage(_ page: Int, animated: Bool) {
        let page = min(max(page, 0), max(numberOfPages - 1, 0))
        guard page != currentPage else { return }
        currentPage = page
        accessibilityValue = "\(page + 1) of \(numberOfPages)"
        let update = {
            for (index, dot) in self.dots.enumerated() {
                let isActive = index == page
                let size = isActive ? MediaViewerPageIndicator.activeSize : MediaViewerPageIndicator.dotSize
                self.sizeConstraints[index].width.constant = size
                self.sizeConstraints[index].height.constant = size
                dot.layer.cornerRadius = size / 2
                dot.alpha = isActive ? 1 : 0.45
            }
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.18, animations: update)
        } else {
            update()
        }
    }

    private func rebuildDots() {
        dots.forEach { $0.removeFromSuperview() }
        dots = (0..<numberOfPages).map { _ in
            let dot = UIView()
            dot.backgroundColor = .white
            dot.layer.cornerRadius = MediaViewerPageIndicator.dotSize / 2
            return dot
        }
        sizeConstraints = dots.map { dot in
            stackView.addArrangedSubview(dot)
            let height = dot.heightAnchor.constraint(equalToConstant: MediaViewerPageIndicator.dotSize)
            let width = dot.widthAnchor.constraint(equalToConstant: MediaViewerPageIndicator.dotSize)
            height.isActive = true
            width.isActive = true
            return (width, height)
        }
        currentPage = -1
    }
}
