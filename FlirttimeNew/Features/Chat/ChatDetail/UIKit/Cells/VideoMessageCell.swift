import UIKit
import Kingfisher
import AVFoundation

final class VideoMessageCell: BaseMessageCell {

    static let cellId = "VideoMessageCell"

    private let thumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.layer.cornerRadius = 12
        iv.layer.borderWidth = 1
        iv.layer.borderColor = ChatTheme.primary.withAlphaComponent(0.4).cgColor
        iv.clipsToBounds = true
        // ✅ White background instead of dark
        iv.backgroundColor = ChatTheme.surface
        iv.image = VideoMessageCell.videoPlaceholder
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private static let videoPlaceholder: UIImage = {
        let size = CGSize(width: MessageCellMetrics.imageVideoBubbleWidth, height: MessageCellMetrics.imageVideoContentHeight)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            ChatTheme.surface.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let iconConfig = UIImage.SymbolConfiguration(pointSize: 44, weight: .light)
            if let icon = UIImage(systemName: "video.fill", withConfiguration: iconConfig)?
                .withTintColor(ChatTheme.separator, renderingMode: .alwaysOriginal) {
                let iconOrigin = CGPoint(
                    x: (size.width - icon.size.width) / 2,
                    y: (size.height - icon.size.height) / 2
                )
                icon.draw(at: iconOrigin)
            }
        }
    }()



    private let playButton: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.layer.cornerRadius = 25
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let playIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "play.fill"))
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(.semibold, size: 11)
        label.textColor = .white
        label.textAlignment = .trailing
        label.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Upload indicator
    private let uploadOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let uploadSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        return spinner
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContentArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContentArea()
    }

    private var activeImageGenerator: AVAssetImageGenerator?
    private var mediaWidthConstraint: NSLayoutConstraint?
    private var mediaHeightConstraint: NSLayoutConstraint?
    private var mediaTopConstraint: NSLayoutConstraint?
    private var mediaBottomConstraint: NSLayoutConstraint?
    private var mediaLeadingConstraint: NSLayoutConstraint?
    private var mediaTrailingConstraint: NSLayoutConstraint?

    private func setupContentArea() {
        contentArea.addSubview(thumbnailView)
        thumbnailView.layer.drawsAsynchronously = true
        thumbnailView.isOpaque = true
        thumbnailView.addSubview(playButton)
        playButton.addSubview(playIcon)
        thumbnailView.addSubview(durationLabel)

        mediaWidthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: MessageCellMetrics.imageVideoBubbleWidth)
        mediaHeightConstraint = thumbnailView.heightAnchor.constraint(equalToConstant: MessageCellMetrics.imageVideoContentHeight)
        mediaTopConstraint = thumbnailView.topAnchor.constraint(equalTo: contentArea.topAnchor)
        mediaLeadingConstraint = thumbnailView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor)
        mediaBottomConstraint = thumbnailView.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor)
        mediaTrailingConstraint = thumbnailView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor)
        mediaWidthConstraint?.isActive = true
        mediaHeightConstraint?.isActive = true
        mediaTopConstraint?.isActive = true
        mediaLeadingConstraint?.isActive = true
        mediaBottomConstraint?.isActive = true

        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 50),
            playButton.heightAnchor.constraint(equalToConstant: 50),

            playIcon.centerXAnchor.constraint(equalTo: playButton.centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            playIcon.widthAnchor.constraint(equalToConstant: 20),
            playIcon.heightAnchor.constraint(equalToConstant: 20),

            durationLabel.rightAnchor.constraint(equalTo: thumbnailView.rightAnchor, constant: -8),
            durationLabel.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -8),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleVideoTap))
        thumbnailView.addGestureRecognizer(tap)
        thumbnailView.isUserInteractionEnabled = true

        // Upload overlay on top of thumbnail
        thumbnailView.addSubview(uploadOverlay)
        uploadOverlay.addSubview(uploadSpinner)
        NSLayoutConstraint.activate([
            uploadOverlay.topAnchor.constraint(equalTo: thumbnailView.topAnchor),
            uploadOverlay.leadingAnchor.constraint(equalTo: thumbnailView.leadingAnchor),
            uploadOverlay.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor),
            uploadOverlay.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor),
            uploadSpinner.centerXAnchor.constraint(equalTo: uploadOverlay.centerXAnchor),
            uploadSpinner.centerYAnchor.constraint(equalTo: uploadOverlay.centerYAnchor),
        ])
    }

    private var thumbnailGenerationId = 0
    private var lastConfiguredMediaKey: String?

    override func configureContent(with model: MessageCellModel) {
        let videoItem = model.mediaItems.first
        let cellId = model.stableId
        let messageId = model.message.id

        // Prefer stable message id for local thumb cache (optimistic + after ack)
        let candidateKeys: [String] = [
            messageId,
            cellId,
            videoItem?.id,
            videoItem?.thumbnailURL,
            (videoItem?.url?.starts(with: "file://") == true ? videoItem?.url : nil)
        ].compactMap { key in
            guard let key, !key.isEmpty else { return nil }
            return key
        }
        let thumbKey = candidateKeys.first ?? cellId

        let mediaChanged = lastConfiguredMediaKey != thumbKey
        lastConfiguredMediaKey = thumbKey

        if mediaChanged {
            let keepCurrent = thumbnailView.image != nil && thumbnailView.image != Self.videoPlaceholder

            // 1. In-memory cache — try all candidate keys
            if let cached = candidateKeys.lazy.compactMap({ InMemoryMediaCache.shared.getCachedImage(for: $0) }).first {
                thumbnailView.image = cached
            }
            // 2. Disk thumbnail — try all candidate keys
            else if let diskThumb = candidateKeys.lazy.compactMap({ MediaStorageManager.shared.getVideoThumbnail(messageId: $0) }).first {
                thumbnailView.image = diskThumb
                InMemoryMediaCache.shared.cacheImage(diskThumb, for: thumbKey)
            }
            // 3. Server thumbnail URL → fallback to local generation
            else {
                // Prefer local file, then remote video URL (API often sends thumbnailUrl: null).
                let resolveVideoForThumbnail = { () -> String? in
                    if let videoURL = videoItem?.url, videoURL.hasPrefix("file://") {
                        return videoURL
                    }
                    for key in candidateKeys {
                        if let diskURL = MediaStorageManager.shared.getMediaURL(messageId: key, type: .video) {
                            return diskURL.absoluteString
                        }
                    }
                    if let remote = videoItem?.url,
                       let url = URL(string: remote),
                       let scheme = url.scheme?.lowercased(),
                       scheme == "http" || scheme == "https",
                       !remote.lowercased().contains(".m3u8") {
                        return remote
                    }
                    return nil
                }

                let generateLocal = { [weak self] in
                    guard let self else { return }
                    guard let videoStr = resolveVideoForThumbnail() else {
                        if !keepCurrent { self.thumbnailView.image = Self.videoPlaceholder }
                        return
                    }
                    if !keepCurrent { self.thumbnailView.image = Self.videoPlaceholder }
                    self.thumbnailGenerationId += 1
                    let generationId = self.thumbnailGenerationId
                    let key = thumbKey
                    self.generateThumbnail(from: videoStr, duration: videoItem?.duration ?? 0) { [weak self] image in
                        DispatchQueue.main.async {
                            guard let self, self.cellModel?.stableId == cellId,
                                  self.thumbnailGenerationId == generationId else { return }
                            self.thumbnailView.image = image ?? Self.videoPlaceholder
                            if let image {
                                InMemoryMediaCache.shared.cacheImage(image, for: key)
                                MediaStorageManager.shared.saveVideoThumbnail(image, messageId: key)
                            }
                        }
                    }
                }

                if let thumbURLStr = videoItem?.thumbnailURL ?? model.message.thumbnail {
                    // Local file thumbnails (file://) — load directly
                    if thumbURLStr.hasPrefix("file://"),
                       let localURL = URL(string: thumbURLStr),
                       let image = UIImage(contentsOfFile: localURL.path) {
                        thumbnailView.image = image
                        InMemoryMediaCache.shared.cacheImage(image, for: thumbKey)
                    } else if let url = URL(string: thumbURLStr), !thumbURLStr.hasPrefix("file://") {
                        let cacheKey = thumbURLStr.components(separatedBy: "?").first ?? thumbURLStr
                        let resource = Kingfisher.ImageResource(downloadURL: url, cacheKey: cacheKey)
                        let placeholder = keepCurrent ? thumbnailView.image : Self.videoPlaceholder
                        thumbnailView.kf.setImage(
                            with: resource,
                            placeholder: placeholder,
                            options: [.loadDiskFileSynchronously],
                            completionHandler: { [weak self] result in
                                guard let self else { return }
                                switch result {
                                case .success(let value):
                                    let key = thumbKey
                                    MediaStorageManager.shared.saveVideoThumbnail(value.image, messageId: key)
                                    InMemoryMediaCache.shared.cacheImage(value.image, for: key)
                                case .failure:
                                    generateLocal()
                                }
                            }
                        )
                    } else {
                        generateLocal()
                    }
                } else {
                    generateLocal()
                }
            }
        }

        if let duration = videoItem?.duration, duration > 0 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            durationLabel.text = String(format: "%d:%02d", minutes, seconds)
        } else {
            durationLabel.text = nil
        }

        if model.isUploading {
            uploadOverlay.isHidden = false
            uploadSpinner.startAnimating()
            playButton.isHidden = true
        } else {
            uploadOverlay.isHidden = true
            uploadSpinner.stopAnimating()
            playButton.isHidden = false
        }
    }

    private func generateThumbnail(from urlStr: String, duration: Double, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: urlStr) else {
            completion(nil)
            return
        }
        if urlStr.lowercased().contains(".m3u8") {
            completion(nil)
            return
        }

        activeImageGenerator?.cancelAllCGImageGeneration()

        let maxSide = MessageCellMetrics.imageVideoBubbleWidth * UIScreen.main.scale
        let maxSize = CGSize(width: maxSide, height: maxSide)
        let seekSeconds = min(1, max(0.0, duration > 0 ? duration * 0.1 : 0.1))

        // Remote URLs: generate on a background queue so AVAsset can fetch enough bytes.
        // Local files: same path — keeps one code path for poster frames.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = maxSize
            DispatchQueue.main.async { self?.activeImageGenerator = generator }

            let time = CMTime(seconds: seekSeconds, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                DispatchQueue.main.async { completion(UIImage(cgImage: cgImage)) }
                return
            }
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                DispatchQueue.main.async { completion(UIImage(cgImage: cgImage)) }
                return
            }
            DispatchQueue.main.async { completion(nil) }
        }
    }

    @objc private func handleVideoTap() {
        guard let model = cellModel else { return }
        actionsDelegate?.cellDidTapMedia(self, model: model, mediaIndex: 0)
    }

    override func configure(with model: MessageCellModel, isInSelectionMode: Bool = false) {
        super.configure(with: model, isInSelectionMode: isInSelectionMode)
        applyMediaLayoutForDeletedState(isDeleted: model.isDeletedState)
    }

    private func applyMediaLayoutForDeletedState(isDeleted: Bool) {
        thumbnailView.isHidden = isDeleted
        mediaHeightConstraint?.isActive = !isDeleted
        mediaWidthConstraint?.isActive = !isDeleted
        mediaTopConstraint?.isActive = !isDeleted
        mediaBottomConstraint?.isActive = !isDeleted
        mediaLeadingConstraint?.isActive = !isDeleted
        if isDeleted {
            mediaTrailingConstraint?.isActive = false
            contentView.setNeedsLayout()
        }
    }

    private func restoreMediaLayoutConstraints() {
        thumbnailView.isHidden = false
        mediaHeightConstraint?.isActive = true
        mediaWidthConstraint?.isActive = true
        mediaTopConstraint?.isActive = true
        mediaBottomConstraint?.isActive = true
        mediaLeadingConstraint?.isActive = true
        mediaTrailingConstraint?.isActive = false
    }

//    override func prepareForReuse() {
//        super.prepareForReuse()
//        thumbnailView.kf.cancelDownloadTask()
//        thumbnailView.image = UIImage(named: ChatAssets.imagePlaceholder)
//        durationLabel.text = nil
//        uploadOverlay.isHidden = true
//        uploadSpinner.stopAnimating()
//        playButton.isHidden = false
//    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        restoreMediaLayoutConstraints()
        thumbnailView.kf.cancelDownloadTask()
        activeImageGenerator?.cancelAllCGImageGeneration()
        activeImageGenerator = nil
        lastConfiguredMediaKey = nil
        // ✅ Light placeholder on reuse
        thumbnailView.image = Self.videoPlaceholder
        thumbnailView.backgroundColor = ChatTheme.surface
        durationLabel.text = nil
        uploadOverlay.isHidden = true
        uploadSpinner.stopAnimating()
        playButton.isHidden = false
    }

    override func configureBubbleAppearance(model: MessageCellModel) {
        bubbleContainer.backgroundColor = .clear
        bubbleContainer.layer.cornerRadius = 0
        bubbleContainer.clipsToBounds = false
        setBubbleContentInsets(top: 0, horizontal: 0, bottom: 0)

        if model.replyPreview != nil {
            wrapInReplyBubble(model: model, innerInsets: 6)
            setBubbleContentInsets(top: 6, horizontal: 0, bottom: 0)
            mediaWidthConstraint?.isActive = false
            mediaTrailingConstraint?.isActive = true
        } else {
            mediaTrailingConstraint?.isActive = false
            mediaWidthConstraint?.isActive = true
            mediaWidthConstraint?.constant = MessageCellMetrics.imageVideoBubbleWidth
        }
    }

    override var mediaImageView: UIImageView? { thumbnailView }
}
