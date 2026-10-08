import UIKit
import Kingfisher

final class ImageMessageCell: BaseMessageCell {

    static let cellId = "ImageMessageCell"

    private static let mediaPlaceholder: UIImage = {
        let size = CGSize(width: MessageCellMetrics.imageVideoBubbleWidth, height: MessageCellMetrics.imageVideoContentHeight)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Light grey background
            UIColor(white: 0.94, alpha: 1.0).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // Centered photo icon
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .light)
            let icon = UIImage(systemName: "photo", withConfiguration: iconConfig)
            let iconSize = icon?.size ?? CGSize(width: 32, height: 32)
            let iconOrigin = CGPoint(
                x: (size.width - iconSize.width) / 2,
                y: (size.height - iconSize.height) / 2
            )
            UIColor(white: 0.78, alpha: 1.0).setFill()
            icon?.draw(at: iconOrigin)
        }
    }()

    private class GridContainer: UIView {
        var layoutCallback: ((CGSize) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            layoutCallback?(bounds.size)
        }
    }

    private let imageGridContainer: GridContainer = {
        let view = GridContainer()
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = ChatTheme.primary.withAlphaComponent(0.4).cgColor
        view.backgroundColor = UIColor.systemGray6
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var imageSlots: [UIImageView] = []
    private var playOverlays: [UIImageView] = []
    private let moreOverlayLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.chat(.bold, size: 24)
        l.textColor = .white
        l.textAlignment = .center
        l.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        l.isHidden = true
        l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return l
    }()

    private var gridItemCount = 0
    private var hasMoreOverlay = false
    private var lastConfiguredMediaKey: String?
    private var videoThumbGenerationIds = [0, 0, 0, 0]

    // Upload indicator
    private let uploadOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
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

    private static let playIcon: UIImage? = {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        return UIImage(systemName: "play.circle.fill", withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContentArea()
        setupImageSlots()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContentArea()
        setupImageSlots()
    }

    private var mediaWidthConstraint: NSLayoutConstraint?
    private var mediaHeightConstraint: NSLayoutConstraint?
    private var mediaTopConstraint: NSLayoutConstraint?
    private var mediaBottomConstraint: NSLayoutConstraint?
    private var mediaLeadingConstraint: NSLayoutConstraint?
    private var mediaTrailingConstraint: NSLayoutConstraint?

    private func setupContentArea() {
        contentArea.addSubview(imageGridContainer)
        imageGridContainer.layoutCallback = { [weak self] size in
            guard let self, size.width > 0, self.gridItemCount > 0 else { return }
            self.layoutGrid(width: size.width, height: size.height)
        }
        
        mediaWidthConstraint = imageGridContainer.widthAnchor.constraint(equalToConstant: MessageCellMetrics.imageVideoBubbleWidth)
        mediaHeightConstraint = imageGridContainer.heightAnchor.constraint(equalToConstant: MessageCellMetrics.imageVideoContentHeight)
        mediaTopConstraint = imageGridContainer.topAnchor.constraint(equalTo: contentArea.topAnchor)
        mediaLeadingConstraint = imageGridContainer.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor)
        mediaBottomConstraint = imageGridContainer.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor)
        mediaTrailingConstraint = imageGridContainer.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor)
        mediaWidthConstraint?.isActive = true
        mediaHeightConstraint?.isActive = true
        mediaTopConstraint?.isActive = true
        mediaLeadingConstraint?.isActive = true
        mediaBottomConstraint?.isActive = true
    }

    private func setupImageSlots() {
        for i in 0..<4 {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.layer.cornerRadius = 12
            iv.clipsToBounds = true
            iv.backgroundColor = UIColor(white: 0.95, alpha: 1)
            iv.isUserInteractionEnabled = true
            iv.tag = i
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleMediaTap(_:)))
            iv.addGestureRecognizer(tap)
            imageGridContainer.addSubview(iv)
            imageSlots.append(iv)

            let play = UIImageView(image: Self.playIcon)
            play.contentMode = .center
            play.isHidden = true
            play.isUserInteractionEnabled = false
            play.translatesAutoresizingMaskIntoConstraints = false
            iv.addSubview(play)
            NSLayoutConstraint.activate([
                play.centerXAnchor.constraint(equalTo: iv.centerXAnchor),
                play.centerYAnchor.constraint(equalTo: iv.centerYAnchor),
                play.widthAnchor.constraint(equalToConstant: 36),
                play.heightAnchor.constraint(equalToConstant: 36),
            ])
            playOverlays.append(play)
        }
        // More-overlay lives inside the 4th slot
        imageSlots[3].addSubview(moreOverlayLabel)

        // Upload overlay on top of everything (added last for correct z-order)
        imageGridContainer.addSubview(uploadOverlay)
        uploadOverlay.addSubview(uploadSpinner)
        NSLayoutConstraint.activate([
            uploadOverlay.topAnchor.constraint(equalTo: imageGridContainer.topAnchor),
            uploadOverlay.leadingAnchor.constraint(equalTo: imageGridContainer.leadingAnchor),
            uploadOverlay.trailingAnchor.constraint(equalTo: imageGridContainer.trailingAnchor),
            uploadOverlay.bottomAnchor.constraint(equalTo: imageGridContainer.bottomAnchor),
            uploadSpinner.centerXAnchor.constraint(equalTo: uploadOverlay.centerXAnchor),
            uploadSpinner.centerYAnchor.constraint(equalTo: uploadOverlay.centerYAnchor),
        ])
    }

    override func configureContent(with model: MessageCellModel) {
        // Show all album items (images + videos) — WhatsApp-style grid
        let items = model.mediaItems.filter { $0.isImage || $0.isVideo }
        let count = min(items.count, 4)

        let mediaKey = items.enumerated().map { (i, item) -> String in
            if !item.id.isEmpty { return item.id }
            if let url = item.url, !url.isEmpty { return url }
            return "\(model.message.id)_\(i)"
        }.joined(separator: "|")

        if model.isUploading {
            uploadOverlay.isHidden = false
            uploadSpinner.startAnimating()
        } else {
            uploadOverlay.isHidden = true
            uploadSpinner.stopAnimating()
        }

        guard lastConfiguredMediaKey != mediaKey else { return }
        lastConfiguredMediaKey = mediaKey

        gridItemCount = count
        hasMoreOverlay = items.count > 4

        imageSlots.forEach { $0.isHidden = true; $0.kf.cancelDownloadTask(); $0.image = nil }
        playOverlays.forEach { $0.isHidden = true }
        moreOverlayLabel.isHidden = true

        let messageId = model.message.id

        for i in 0..<videoThumbGenerationIds.count { videoThumbGenerationIds[i] += 1 }

        for i in 0..<count {
            let slot = imageSlots[i]
            slot.isHidden = false
            let item = items[i]
            playOverlays[i].isHidden = !item.isVideo

            let itemKey: String
            if !item.id.isEmpty {
                itemKey = item.id
            } else if let urlStr = item.url, !urlStr.isEmpty {
                itemKey = urlStr
            } else {
                itemKey = messageId + "_\(i)"
            }

            let localKeys = [itemKey, "\(messageId)_\(i)", messageId].filter { !$0.isEmpty }

            // 1. In-memory cache
            if let cached = localKeys.lazy.compactMap({ InMemoryMediaCache.shared.getCachedImage(for: $0) }).first {
                slot.image = cached
                continue
            }

            // 2a. Disk thumbnail (album videos are stored as messageId_index after ack)
            if item.isVideo {
                if let diskThumb = localKeys.lazy.compactMap({ MediaStorageManager.shared.getVideoThumbnail(messageId: $0) }).first {
                    slot.image = diskThumb
                    InMemoryMediaCache.shared.cacheImage(diskThumb, for: itemKey)
                    continue
                }
            } else if let diskThumb = localKeys.lazy.compactMap({ MediaStorageManager.shared.getImageThumbnail(messageId: $0) }).first {
                slot.image = diskThumb
                InMemoryMediaCache.shared.cacheImage(diskThumb, for: itemKey)
                continue
            }

            // 2b. Local disk full image
            if item.isImage {
                var found = false
                for key in localKeys {
                    if let localURL = MediaStorageManager.shared.getMediaURL(messageId: key, type: .image),
                       let image = UIImage(contentsOfFile: localURL.path) {
                        slot.image = image
                        InMemoryMediaCache.shared.cacheImage(image, for: itemKey)
                        found = true
                        break
                    }
                }
                if found { continue }
            }

            // Local file:// url on the item itself
            if let urlStr = item.url, urlStr.hasPrefix("file://"),
               let fileURL = URL(string: urlStr) {
                if item.isImage, let image = UIImage(contentsOfFile: fileURL.path) {
                    slot.image = image
                    InMemoryMediaCache.shared.cacheImage(image, for: itemKey)
                    continue
                }
                if item.isVideo {
                    if let thumbStr = item.thumbnailURL, thumbStr.hasPrefix("file://"),
                       let thumbURL = URL(string: thumbStr),
                       let image = UIImage(contentsOfFile: thumbURL.path) {
                        slot.image = image
                        InMemoryMediaCache.shared.cacheImage(image, for: itemKey)
                        continue
                    }
                }
            }

            // 3. Remote thumbnail URL, then generate from the video file (same as single-video cell).
            let saveDiskThumb = itemKey
            if let thumbStr = item.thumbnailURL, let thumbURL = URL(string: thumbStr), !thumbStr.hasPrefix("file://") {
                let cacheKey = thumbStr.components(separatedBy: "?").first ?? thumbStr
                let resource = Kingfisher.ImageResource(downloadURL: thumbURL, cacheKey: cacheKey)
                slot.kf.setImage(
                    with: resource,
                    placeholder: Self.mediaPlaceholder,
                    options: [.loadDiskFileSynchronously]
                ) { [weak self] result in
                    switch result {
                    case .success(let value):
                        InMemoryMediaCache.shared.cacheImage(value.image, for: itemKey)
                        if item.isVideo {
                            MediaStorageManager.shared.saveVideoThumbnail(value.image, messageId: saveDiskThumb)
                        } else {
                            MediaStorageManager.shared.saveImageThumbnail(value.image, messageId: saveDiskThumb)
                        }
                    case .failure:
                        if item.isVideo {
                            self?.startVideoThumbnailGeneration(
                                item: item, itemKey: itemKey, messageId: messageId, index: i, slot: slot
                            )
                        }
                    }
                }
            } else if item.isImage, let urlStr = item.url, let url = URL(string: urlStr), !urlStr.hasPrefix("file://") {
                let cacheKey = urlStr.components(separatedBy: "?").first ?? urlStr
                let resource = Kingfisher.ImageResource(downloadURL: url, cacheKey: cacheKey)
                slot.kf.setImage(
                    with: resource,
                    placeholder: Self.mediaPlaceholder,
                    options: [.loadDiskFileSynchronously]
                ) { result in
                    if case .success(let value) = result {
                        InMemoryMediaCache.shared.cacheImage(value.image, for: itemKey)
                        MediaStorageManager.shared.saveImageThumbnail(value.image, messageId: saveDiskThumb)
                    }
                }
            } else if item.isVideo {
                slot.image = Self.mediaPlaceholder
                startVideoThumbnailGeneration(
                    item: item, itemKey: itemKey, messageId: messageId, index: i, slot: slot
                )
            } else {
                slot.image = Self.mediaPlaceholder
            }
        }

        if hasMoreOverlay {
            moreOverlayLabel.text = "+\(items.count - 4)"
        }

        setNeedsLayout()
    }

    /// Generate a poster frame from the local or remote video — albums previously skipped this
    /// and only showed a placeholder when `thumbnail` was null (single-video cells already do this).
    private func startVideoThumbnailGeneration(
        item: MediaItemModel,
        itemKey: String,
        messageId: String,
        index: Int,
        slot: UIImageView
    ) {
        guard let videoURL = resolveAlbumVideoURL(item: item, itemKey: itemKey, messageId: messageId, index: index) else {
            return
        }
        videoThumbGenerationIds[index] += 1
        let generationId = videoThumbGenerationIds[index]
        let mediaKey = lastConfiguredMediaKey
        let duration = item.duration ?? 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = MediaStorageManager.generateVideoThumbnailImage(from: videoURL, duration: duration)
            DispatchQueue.main.async {
                guard let self,
                      self.lastConfiguredMediaKey == mediaKey,
                      index < self.videoThumbGenerationIds.count,
                      self.videoThumbGenerationIds[index] == generationId,
                      let image else { return }
                slot.image = image
                InMemoryMediaCache.shared.cacheImage(image, for: itemKey)
                MediaStorageManager.shared.saveVideoThumbnail(image, messageId: itemKey)
                if !messageId.isEmpty {
                    MediaStorageManager.shared.saveVideoThumbnail(image, messageId: "\(messageId)_\(index)")
                }
            }
        }
    }

    private func resolveAlbumVideoURL(
        item: MediaItemModel,
        itemKey: String,
        messageId: String,
        index: Int
    ) -> URL? {
        if let urlStr = item.url, urlStr.hasPrefix("file://"), let url = URL(string: urlStr) {
            return url
        }
        let keys = [itemKey, "\(messageId)_\(index)", messageId].filter { !$0.isEmpty }
        for key in keys {
            if let diskURL = MediaStorageManager.shared.getMediaURL(messageId: key, type: .video) {
                return diskURL
            }
        }
        if let remote = item.url,
           let url = URL(string: remote),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           !remote.lowercased().contains(".m3u8") {
            return url
        }
        return nil
    }

    private func layoutGrid(width gridWidth: CGFloat, height gridHeight: CGFloat) {
        let gridSpacing: CGFloat = 2
        let count = gridItemCount

        switch count {
        case 1:
            imageSlots[0].frame = CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight)

        case 2:
            let hw = (gridWidth - gridSpacing) / 2
            for i in 0..<2 {
                imageSlots[i].frame = CGRect(x: CGFloat(i) * (hw + gridSpacing), y: 0, width: hw, height: gridHeight)
            }

        case 3:
            let hw = (gridWidth - gridSpacing) / 2
            let hh = (gridHeight - gridSpacing) / 2
            imageSlots[0].frame = CGRect(x: 0, y: 0, width: gridWidth, height: hh)
            for i in 1..<3 {
                imageSlots[i].frame = CGRect(x: CGFloat(i - 1) * (hw + gridSpacing), y: hh + gridSpacing, width: hw, height: hh)
            }

        default: // 4+
            let hw = (gridWidth - gridSpacing) / 2
            let hh = (gridHeight - gridSpacing) / 2
            for i in 0..<4 {
                let col = CGFloat(i % 2)
                let row = CGFloat(i / 2)
                imageSlots[i].frame = CGRect(x: col * (hw + gridSpacing), y: row * (hh + gridSpacing), width: hw, height: hh)
            }
            if hasMoreOverlay {
                moreOverlayLabel.frame = imageSlots[3].bounds
                moreOverlayLabel.isHidden = false
            }
        }
    }

    @objc private func handleMediaTap(_ gesture: UITapGestureRecognizer) {
        guard let model = cellModel, let view = gesture.view else { return }
        actionsDelegate?.cellDidTapMedia(self, model: model, mediaIndex: view.tag)
    }

    override func configure(with model: MessageCellModel, isInSelectionMode: Bool = false) {
        super.configure(with: model, isInSelectionMode: isInSelectionMode)
        applyMediaLayoutForDeletedState(isDeleted: model.isDeletedState)
    }

    private func applyMediaLayoutForDeletedState(isDeleted: Bool) {
        imageGridContainer.isHidden = isDeleted
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
        imageGridContainer.isHidden = false
        mediaHeightConstraint?.isActive = true
        mediaWidthConstraint?.isActive = true
        mediaTopConstraint?.isActive = true
        mediaBottomConstraint?.isActive = true
        mediaLeadingConstraint?.isActive = true
        mediaTrailingConstraint?.isActive = false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        restoreMediaLayoutConstraints()
        imageSlots.forEach { iv in
            iv.kf.cancelDownloadTask()
            iv.image = nil
            iv.isHidden = true
        }
        playOverlays.forEach { $0.isHidden = true }
        moreOverlayLabel.isHidden = true
        uploadOverlay.isHidden = true
        uploadSpinner.stopAnimating()
        gridItemCount = 0
        hasMoreOverlay = false
        lastConfiguredMediaKey = nil
        for i in 0..<videoThumbGenerationIds.count { videoThumbGenerationIds[i] += 1 }
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

    override var mediaImageView: UIImageView? {
        imageSlots.first(where: { !$0.isHidden })
    }
}
