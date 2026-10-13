//
//  MomentsTableViewCell.swift
//  FlirttimeNew
//

import UIKit

protocol MomentsTableViewCellDelegate: AnyObject {
    func vibeCellDidTapLike(_ cell: MomentsTableViewCell)
    func vibeCellDidDoubleTapLike(_ cell: MomentsTableViewCell)
    func vibeCellDidTapComment(_ cell: MomentsTableViewCell)
    func vibeCellDidTapGift(_ cell: MomentsTableViewCell)
    func vibeCellDidTapShare(_ cell: MomentsTableViewCell)
    func vibeCellDidTapMore(_ cell: MomentsTableViewCell)
    func vibeCellDidTapProfile(_ cell: MomentsTableViewCell)
    func vibeCellDidToggleCaption(_ cell: MomentsTableViewCell)
}

final class MomentsTableViewCell: UITableViewCell {

    static let identifier = "MomentsTableViewCell"

    private static let avatarSize: CGFloat = 40
    private static let avatarLeading: CGFloat = 8
    private static let contentLeadingGap: CGFloat = 6
    private static let contentTrailing: CGFloat = 16
    private static let mediaHeight: CGFloat = 400

    /// Photo area of a feed row that is `rowWidth` wide. Add Moment crops photos to this shape.
    static func mediaSize(forRowWidth rowWidth: CGFloat) -> CGSize {
        let width = rowWidth - avatarLeading - avatarSize - contentLeadingGap - contentTrailing
        return CGSize(width: max(width, 1), height: mediaHeight)
    }
    /// Longer captions are cut here with a "more" toggle.
    static let captionPreviewLength = 250

    private static let likeIcon = UIImage(named: "whiteHeart")?.withRenderingMode(.alwaysTemplate)
    private static let likedIcon = UIImage(named: "fillHeart")?.withRenderingMode(.alwaysTemplate)
    private static let commentIcon = UIImage(named: "whiteMessage1")?.withRenderingMode(.alwaysTemplate)
    private static let giftIcon = UIImage(named: "vibe_gift_box")?.withRenderingMode(.alwaysTemplate)
    private static let shareIcon = UIImage(named: "whiteShare")?.withRenderingMode(.alwaysTemplate)

    weak var delegate: MomentsTableViewCellDelegate?

    private var media: [MomentsMedia] = []
    private var lastMediaWidth: CGFloat = 0
    private var caption = ""

    private var isCaptionTruncatable: Bool {
        caption.count > MomentsTableViewCell.captionPreviewLength
    }

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = MomentsTableViewCell.avatarSize / 2
        imageView.backgroundColor = AppColor.AthensGray
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.medium, size: 16)
        label.textColor = AppColor.MineShaft
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let verifiedImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "verified"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    /// Location when the author shares one, otherwise the relative time.
    private let metaLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 13)
        label.textColor = AppColor.SilverChalice
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let moreButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "3Dot")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = AppColor.MineShaft
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.accessibilityLabel = "More options"
        return button
    }()

    private let captionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 15)
        label.textColor = AppColor.MineShaft
        label.numberOfLines = 0
        return label
    }()

    private lazy var mediaCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = AppColor.AthensGray
        collectionView.layer.cornerRadius = 12
        collectionView.clipsToBounds = true
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MomentsMediaCollectionViewCell.self, forCellWithReuseIdentifier: MomentsMediaCollectionViewCell.identifier)
        return collectionView
    }()

    private let pageIndicator = MomentsPageIndicator()

    private let imageCounterLabel: MomentsImageCounterLabel = {
        let label = MomentsImageCounterLabel()
        label.font = UIFont.fredoka(.medium, size: 12)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.isUserInteractionEnabled = false
        return label
    }()

    private let likeButton = MomentsActionButton(iconSize: 22)
    private let commentButton = MomentsActionButton(iconSize: 20)
    private let giftButton = MomentsActionButton(iconSize: 22)
    private let shareButton = MomentsActionButton(iconSize: 20)

    /// Actions sit in a column on the photo's right edge; text-only moments show them in a row instead.
    private let overlayActionStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        return stackView
    }()

    private let rowActionStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 20
        return stackView
    }()

    private let rowActionSpacer = UIView()
    private var actionStyle: MomentsActionButton.Style = .overPhoto

    private let separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColor.Iron
        return view
    }()

    private var mediaHeightConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        delegate = nil
        avatarImageView.image = nil
        metaLabel.text = nil
        media = []
        mediaCollectionView.reloadData()
        contentView.subviews
            .filter { $0.accessibilityIdentifier == HeartBurst.identifier }
            .forEach { $0.removeFromSuperview() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = mediaCollectionView.bounds.width
        if width != lastMediaWidth {
            lastMediaWidth = width
            mediaCollectionView.collectionViewLayout.invalidateLayout()
        }
    }

    private func setUI() {
        let nameStack = UIStackView(arrangedSubviews: [nameLabel, verifiedImageView, UIView(), moreButton])
        nameStack.axis = .horizontal
        nameStack.alignment = .center
        nameStack.spacing = 6

        let headerStack = UIStackView(arrangedSubviews: [nameStack, metaLabel])
        headerStack.axis = .vertical
        headerStack.alignment = .fill
        headerStack.spacing = 2

        rowActionStack.addArrangedSubview(rowActionSpacer)

        let contentStack = UIStackView(arrangedSubviews: [headerStack, captionLabel, mediaCollectionView, rowActionStack])
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.setCustomSpacing(4, after: headerStack)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        mediaCollectionView.addGestureRecognizer(doubleTap)

        [avatarImageView, contentStack, separatorView, pageIndicator, imageCounterLabel, overlayActionStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        mediaHeightConstraint = mediaCollectionView.heightAnchor.constraint(equalToConstant: MomentsTableViewCell.mediaHeight)
        let bottom = separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        bottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: MomentsTableViewCell.avatarLeading),
            avatarImageView.widthAnchor.constraint(equalToConstant: MomentsTableViewCell.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: MomentsTableViewCell.avatarSize),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: MomentsTableViewCell.contentLeadingGap),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -MomentsTableViewCell.contentTrailing),

            verifiedImageView.widthAnchor.constraint(equalToConstant: 16),
            verifiedImageView.heightAnchor.constraint(equalToConstant: 16),
            moreButton.widthAnchor.constraint(equalToConstant: 28),
            moreButton.heightAnchor.constraint(equalToConstant: 24),
            mediaHeightConstraint,

            pageIndicator.leadingAnchor.constraint(equalTo: mediaCollectionView.leadingAnchor, constant: 14),
            pageIndicator.bottomAnchor.constraint(equalTo: mediaCollectionView.bottomAnchor, constant: -16),

            imageCounterLabel.topAnchor.constraint(equalTo: mediaCollectionView.topAnchor, constant: 12),
            imageCounterLabel.trailingAnchor.constraint(equalTo: mediaCollectionView.trailingAnchor, constant: -12),
            imageCounterLabel.heightAnchor.constraint(equalToConstant: 24),

            overlayActionStack.trailingAnchor.constraint(equalTo: mediaCollectionView.trailingAnchor, constant: -8),
            overlayActionStack.bottomAnchor.constraint(equalTo: mediaCollectionView.bottomAnchor, constant: -10),

            separatorView.topAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: 10),
            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5),
            bottom
        ])

        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        commentButton.addTarget(self, action: #selector(commentTapped), for: .touchUpInside)
        giftButton.addTarget(self, action: #selector(giftTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)

        [avatarImageView, nameLabel].forEach {
            $0.isUserInteractionEnabled = true
            $0.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profileTapped)))
        }

        captionLabel.isUserInteractionEnabled = true
        captionLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(captionTapped)))
    }

    // MARK: - Configure

    func configure(with vibe: MomentsPost, isCaptionExpanded: Bool = false) {
        nameLabel.text = vibe.author?.displayName
        verifiedImageView.isHidden = !(vibe.author?.verified ?? false)
        let taggedPlace = (vibe.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = taggedPlace.isEmpty ? vibe.author?.location : taggedPlace
        metaLabel.text = Self.metaText(location: location, createdAt: vibe.createdAt)
        metaLabel.isHidden = (metaLabel.text ?? "").isEmpty
        avatarImageView.loadImage(path: vibe.author?.profilePicture, placeholder: UIImage(named: "dummy_Profile"))

        caption = (vibe.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        captionLabel.isHidden = caption.isEmpty
        setCaptionExpanded(isCaptionExpanded)

        media = vibe.media ?? []
        mediaCollectionView.isHidden = media.isEmpty
        mediaHeightConstraint.constant = media.isEmpty ? 0 : MomentsTableViewCell.mediaHeight
        mediaCollectionView.reloadData()
        mediaCollectionView.setContentOffset(.zero, animated: false)
        pageIndicator.numberOfPages = media.count
        pageIndicator.setCurrentPage(0, animated: false)
        pageIndicator.isHidden = media.count < 2
        imageCounterLabel.isHidden = media.count < 2
        updateImageCounter(page: 0)

        placeActions(overPhoto: !media.isEmpty)
        updateCounts(with: vibe)
    }

    private func placeActions(overPhoto: Bool) {
        let style: MomentsActionButton.Style = overPhoto ? .overPhoto : .plain
        let buttons = [likeButton, commentButton, giftButton, shareButton]
        if style != actionStyle || buttons.allSatisfy({ $0.superview == nil }) {
            buttons.forEach { $0.removeFromSuperview() }
            if overPhoto {
                buttons.forEach { overlayActionStack.addArrangedSubview($0) }
            } else {
                buttons.reversed().forEach { rowActionStack.insertArrangedSubview($0, at: 0) }
            }
            actionStyle = style
        }
        overlayActionStack.isHidden = !overPhoto
        rowActionStack.isHidden = overPhoto
    }

    /// Refreshes like / comment / gift / share state without reloading media.
    func updateCounts(with vibe: MomentsPost) {
        let liked = vibe.hasLiked ?? false
        let likes = vibe.likesCount ?? 0
        let comments = vibe.commentsCount ?? 0
        let gifts = vibe.giftCount ?? 0
        let shares = vibe.shareCount ?? 0

        likeButton.configure(icon: liked ? MomentsTableViewCell.likedIcon : MomentsTableViewCell.likeIcon,
                             style: actionStyle, count: likes,
                             iconTint: liked ? AppColor.Punch : nil)
        commentButton.configure(icon: MomentsTableViewCell.commentIcon,
                                style: actionStyle, count: comments)
        giftButton.configure(icon: MomentsTableViewCell.giftIcon,
                             style: actionStyle, count: gifts)
        shareButton.configure(icon: MomentsTableViewCell.shareIcon,
                              style: actionStyle, count: shares)

        likeButton.accessibilityLabel = liked ? "Unlike, \(likes) likes" : "Like, \(likes) likes"
        commentButton.accessibilityLabel = "Comments, \(comments)"
        giftButton.accessibilityLabel = "Gifts, \(gifts)"
        shareButton.accessibilityLabel = "Share, \(shares)"
    }

    /// Shows the first `captionPreviewLength` characters with "… more", or the full caption with "less".
    func setCaptionExpanded(_ expanded: Bool) {
        let bodyFont = UIFont.fredoka(.regular, size: 15)
        guard isCaptionTruncatable else {
            captionLabel.attributedText = nil
            captionLabel.font = bodyFont
            captionLabel.text = caption
            captionLabel.accessibilityHint = nil
            captionLabel.accessibilityTraits = .staticText
            return
        }

        let visibleText: String
        if expanded {
            visibleText = caption + " "
        } else {
            let preview = caption.prefix(MomentsTableViewCell.captionPreviewLength)
            visibleText = String(preview).trimmingCharacters(in: .whitespacesAndNewlines) + "… "
        }
        let text = NSMutableAttributedString(string: visibleText, attributes: [
            .font: bodyFont,
            .foregroundColor: AppColor.MineShaft
        ])
        text.append(NSAttributedString(string: expanded ? "less" : "more", attributes: [
            .font: UIFont.fredoka(.medium, size: 15),
            .foregroundColor: AppColor.Punch
        ]))
        captionLabel.attributedText = text
        captionLabel.accessibilityHint = expanded ? "Double tap to show less" : "Double tap to read the full caption"
        captionLabel.accessibilityTraits = .button
    }

    // MARK: - Actions

    @objc private func captionTapped() {
        guard isCaptionTruncatable else { return }
        delegate?.vibeCellDidToggleCaption(self)
    }

    @objc private func profileTapped() {
        delegate?.vibeCellDidTapProfile(self)
    }

    @objc private func likeTapped() {
        bounce(likeButton)
        delegate?.vibeCellDidTapLike(self)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: contentView)
        guard !isInsideControl(contentView.hitTest(point, with: nil)) else { return }
        HeartBurst.show(in: contentView, at: point)
        MomentsHaptics.threshold()
        delegate?.vibeCellDidDoubleTapLike(self)
    }

    /// Location under the name when the author shares one, otherwise the relative time.
    private static func metaText(location: String?, createdAt: String?) -> String {
        let place = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let time = MomentsDate.timeAgo(from: createdAt)
        if !place.isEmpty, !time.isEmpty { return "\(place) · \(time)" }
        return place.isEmpty ? time : place
    }

    private func isInsideControl(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current, candidate !== contentView {
            if candidate is UIControl { return true }
            current = candidate.superview
        }
        return false
    }

    @objc private func commentTapped() {
        bounce(commentButton)
        delegate?.vibeCellDidTapComment(self)
    }

    @objc private func giftTapped() {
        bounce(giftButton)
        delegate?.vibeCellDidTapGift(self)
    }

    @objc private func shareTapped() {
        bounce(shareButton)
        delegate?.vibeCellDidTapShare(self)
    }

    @objc private func moreTapped() {
        delegate?.vibeCellDidTapMore(self)
    }

    private func bounce(_ view: UIView) {
        UIView.animate(withDuration: 0.1, animations: {
            view.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                view.transform = .identity
            }
        }
    }

}

/// Round icon button with its count underneath, in the style of FlirtTime's moment preview actions.
private final class MomentsActionButton: UIControl {

    enum Style {
        /// Frosted circle, white icon and count, laid over the moment photo.
        case overPhoto
        /// Grey circle and dark icon on the white cell, for moments without a photo.
        case plain
    }

    private static let circleSize: CGFloat = 44

    private let circleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = MomentsActionButton.circleSize / 2
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private let blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        view.isUserInteractionEnabled = false
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 12)
        label.textColor = AppColor.DoveGray
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.layer.shadowOpacity = 0
        return label
    }()

    init(iconSize: CGFloat) {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button

        blurView.translatesAutoresizingMaskIntoConstraints = false
        circleView.addSubview(blurView)
        [circleView, iconImageView, countLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 52),

            blurView.topAnchor.constraint(equalTo: circleView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: circleView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: circleView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: circleView.bottomAnchor),

            circleView.topAnchor.constraint(equalTo: topAnchor),
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.widthAnchor.constraint(equalToConstant: MomentsActionButton.circleSize),
            circleView.heightAnchor.constraint(equalToConstant: MomentsActionButton.circleSize),

            iconImageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),

            countLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 4),
            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            countLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    func configure(icon: UIImage?, style: Style, count: Int, iconTint: UIColor? = nil) {
        iconImageView.image = icon
        countLabel.text = count.vibeCountText

        switch style {
        case .overPhoto:
            blurView.isHidden = false
            blurView.alpha = 0.7
            circleView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            iconImageView.tintColor = AppColor.AppWhite
            countLabel.textColor = AppColor.AppWhite
            countLabel.font = UIFont.fredoka(.medium, size: 12)
            countLabel.layer.shadowOpacity = 0.6
        case .plain:
            blurView.isHidden = true
            circleView.backgroundColor = AppColor.Iron.withAlphaComponent(0.35)
            iconImageView.tintColor = AppColor.MineShaft
            countLabel.textColor = AppColor.DoveGray
            countLabel.font = UIFont.fredoka(.regular, size: 12)
            countLabel.layer.shadowOpacity = 0
        }
        if let iconTint {
            iconImageView.tintColor = iconTint
        }
    }
}

// MARK: - Media
extension MomentsTableViewCell: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        media.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MomentsMediaCollectionViewCell.identifier, for: indexPath) as? MomentsMediaCollectionViewCell else {
            return UICollectionViewCell()
        }
        cell.configure(path: media[indexPath.item].filePath)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: max(collectionView.bounds.width, 1), height: max(collectionView.bounds.height, 1))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === mediaCollectionView, scrollView.bounds.width > 0 else { return }
        let page = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
        pageIndicator.setCurrentPage(page, animated: true)
        updateImageCounter(page: page)
    }

    private func updateImageCounter(page: Int) {
        guard !media.isEmpty else { return }
        let current = min(max(page, 0), media.count - 1) + 1
        imageCounterLabel.text = "\(current)/\(media.count)"
    }
}

/// Top-right "current/total" pill shown on multi-photo moments.
private final class MomentsImageCounterLabel: UILabel {

    private static let horizontalInset: CGFloat = 10

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: MomentsImageCounterLabel.horizontalInset, dy: 0))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + MomentsImageCounterLabel.horizontalInset * 2, height: size.height)
    }
}

/// Bottom-left photo pager: a white pill for the current photo, dots for the rest.
private final class MomentsPageIndicator: UIView {

    private static let dotSize: CGFloat = 6
    private static let activeWidth: CGFloat = 28

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 5
        return stackView
    }()

    private var dotWidthConstraints: [NSLayoutConstraint] = []
    private var dots: [UIView] = []
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
        isAccessibilityElement = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCurrentPage(_ page: Int, animated: Bool) {
        let page = min(max(page, 0), max(numberOfPages - 1, 0))
        guard page != currentPage else { return }
        currentPage = page
        let update = {
            for (index, dot) in self.dots.enumerated() {
                let isActive = index == page
                self.dotWidthConstraints[index].constant = isActive ? MomentsPageIndicator.activeWidth : MomentsPageIndicator.dotSize
                dot.alpha = isActive ? 1 : 0.55
            }
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: update)
        } else {
            update()
        }
    }

    private func rebuildDots() {
        dots.forEach { $0.removeFromSuperview() }
        dots = (0..<numberOfPages).map { _ in
            let dot = UIView()
            dot.backgroundColor = .white
            dot.layer.cornerRadius = MomentsPageIndicator.dotSize / 2
            dot.layer.shadowColor = UIColor.black.cgColor
            dot.layer.shadowOpacity = 0.25
            dot.layer.shadowRadius = 2
            dot.layer.shadowOffset = .zero
            return dot
        }
        dotWidthConstraints = dots.map { dot in
            stackView.addArrangedSubview(dot)
            dot.heightAnchor.constraint(equalToConstant: MomentsPageIndicator.dotSize).isActive = true
            let width = dot.widthAnchor.constraint(equalToConstant: MomentsPageIndicator.dotSize)
            width.isActive = true
            return width
        }
        currentPage = -1
    }
}
