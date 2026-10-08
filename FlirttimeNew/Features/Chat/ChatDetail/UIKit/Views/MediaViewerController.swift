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

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var playerController: AVPlayerViewController?

    init(item: GalleryMediaItem, index: Int) {
        self.item = item
        self.index = index
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

    var displayedImage: UIImage? { imageView.image }

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
        } else {
            imageView.kf.indicatorType = .activity
            imageView.setChatImage(with: item.url, placeholderImage: UIImage(named: ChatAssets.imagePlaceholder), options: [.retryFailed, .highPriority])
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
    private var currentIndex: Int
    private weak var sourceView: UIImageView?

    private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 16])
    private let topBar = UIView()
    private let closeButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var controlsVisible = true

    var onDismiss: (() -> Void)?

    init(items: [GalleryMediaItem], initialIndex: Int, sourceView: UIImageView? = nil) {
        self.items = items
        self.currentIndex = min(max(initialIndex, 0), max(items.count - 1, 0))
        self.sourceView = sourceView
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersStatusBarHidden: Bool { !controlsVisible }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPager()
        setupTopBar()
        updateHeader()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        currentPage?.setPlaybackActive(true)
    }

    private var currentPage: MediaViewerPage? {
        pageVC.viewControllers?.first as? MediaViewerPage
    }

    private func makePage(at index: Int) -> MediaViewerPage? {
        guard items.indices.contains(index) else { return nil }
        let page = MediaViewerPage(item: items[index], index: index)
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
    }

    private func toggleControls() {
        controlsVisible.toggle()
        UIView.animate(withDuration: 0.2) {
            self.topBar.alpha = self.controlsVisible ? 1 : 0
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }

    // MARK: Actions

    @objc private func closeTapped() {
        dismissViewer()
    }

    private func dismissViewer() {
        currentPage?.setPlaybackActive(false)
        dismiss(animated: true) { [onDismiss] in onDismiss?() }
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
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .changed:
            pageVC.view.transform = CGAffineTransform(translationX: 0, y: translation.y)
            view.backgroundColor = UIColor.black.withAlphaComponent(max(0.3, 1 - abs(translation.y) / 400))
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).y
            if abs(translation.y) > 120 || abs(velocity) > 900 {
                dismissViewer()
            } else {
                UIView.animate(withDuration: 0.25) {
                    self.pageVC.view.transform = .identity
                    self.view.backgroundColor = .black
                }
            }
        default:
            break
        }
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
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }
}
