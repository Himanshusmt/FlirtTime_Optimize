//
//  VibeTableViewCell.swift
//  FlirttimeNew
//

import UIKit

protocol VibeTableViewCellDelegate: AnyObject {
    func vibeCellDidTapLike(_ cell: VibeTableViewCell)
    func vibeCellDidTapComment(_ cell: VibeTableViewCell)
    func vibeCellDidTapGift(_ cell: VibeTableViewCell)
    func vibeCellDidTapMore(_ cell: VibeTableViewCell)
}

final class VibeTableViewCell: UITableViewCell {

    static let identifier = "VibeTableViewCell"

    private static let avatarSize: CGFloat = 40
    private static let mediaHeight: CGFloat = 400

    private static let likeIcon = UIImage(named: "whiteHeart")?.withRenderingMode(.alwaysTemplate)
    private static let likedIcon = UIImage(named: "fillHeart")?.withRenderingMode(.alwaysOriginal)
    private static let commentIcon = UIImage(named: "whiteMessage1")?.withRenderingMode(.alwaysTemplate)
    private static let giftIcon = UIImage(named: "vibe_gift_box")?.withRenderingMode(.alwaysTemplate)

    weak var delegate: VibeTableViewCellDelegate?

    private var media: [VibeMedia] = []
    private var lastMediaWidth: CGFloat = 0

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = VibeTableViewCell.avatarSize / 2
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

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 14)
        label.textColor = AppColor.SilverChalice
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        collectionView.register(VibeMediaCollectionViewCell.self, forCellWithReuseIdentifier: VibeMediaCollectionViewCell.identifier)
        return collectionView
    }()

    private let pageIndicator = VibePageIndicator()

    private let likeButton = VibeActionButton(iconSize: 22)
    private let commentButton = VibeActionButton(iconSize: 20)
    private let giftButton = VibeActionButton(iconSize: 22)

    /// Actions sit in a column on the photo's right edge; text-only vibes show them in a row instead.
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
    private var actionStyle: VibeActionButton.Style = .overPhoto

    private let separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColor.Iron
        return view
    }()

    private var mediaHeightConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        delegate = nil
        avatarImageView.image = nil
        media = []
        mediaCollectionView.reloadData()
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
        let nameStack = UIStackView(arrangedSubviews: [nameLabel, verifiedImageView, timeLabel, UIView(), moreButton])
        nameStack.axis = .horizontal
        nameStack.alignment = .center
        nameStack.spacing = 6

        rowActionStack.addArrangedSubview(rowActionSpacer)

        let contentStack = UIStackView(arrangedSubviews: [nameStack, captionLabel, mediaCollectionView, rowActionStack])
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.setCustomSpacing(4, after: nameStack)

        [avatarImageView, contentStack, separatorView, pageIndicator, overlayActionStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        mediaHeightConstraint = mediaCollectionView.heightAnchor.constraint(equalToConstant: VibeTableViewCell.mediaHeight)
        let bottom = separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        bottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.widthAnchor.constraint(equalToConstant: VibeTableViewCell.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: VibeTableViewCell.avatarSize),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            verifiedImageView.widthAnchor.constraint(equalToConstant: 16),
            verifiedImageView.heightAnchor.constraint(equalToConstant: 16),
            moreButton.widthAnchor.constraint(equalToConstant: 28),
            moreButton.heightAnchor.constraint(equalToConstant: 24),
            mediaHeightConstraint,

            pageIndicator.leadingAnchor.constraint(equalTo: mediaCollectionView.leadingAnchor, constant: 14),
            pageIndicator.bottomAnchor.constraint(equalTo: mediaCollectionView.bottomAnchor, constant: -16),

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
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
    }

    // MARK: - Configure

    func configure(with vibe: Vibe) {
        nameLabel.text = vibe.author?.displayName
        verifiedImageView.isHidden = !(vibe.author?.verified ?? false)
        timeLabel.text = VibeDate.timeAgo(from: vibe.createdAt)
        avatarImageView.loadImage(path: vibe.author?.profilePicture, placeholder: UIImage(named: "dummy_Profile"))

        let caption = (vibe.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        captionLabel.text = caption
        captionLabel.isHidden = caption.isEmpty

        media = vibe.media ?? []
        mediaCollectionView.isHidden = media.isEmpty
        mediaHeightConstraint.constant = media.isEmpty ? 0 : VibeTableViewCell.mediaHeight
        mediaCollectionView.reloadData()
        mediaCollectionView.setContentOffset(.zero, animated: false)
        pageIndicator.numberOfPages = media.count
        pageIndicator.setCurrentPage(0, animated: false)
        pageIndicator.isHidden = media.count < 2

        placeActions(overPhoto: !media.isEmpty)
        updateCounts(with: vibe)
    }

    private func placeActions(overPhoto: Bool) {
        let style: VibeActionButton.Style = overPhoto ? .overPhoto : .plain
        let buttons = [likeButton, commentButton, giftButton]
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

    /// Refreshes like / comment / gift state without reloading media.
    func updateCounts(with vibe: Vibe) {
        let liked = vibe.hasLiked ?? false
        let likes = vibe.likesCount ?? 0
        let comments = vibe.commentsCount ?? 0
        let gifts = vibe.giftCount ?? 0

        likeButton.configure(icon: liked ? VibeTableViewCell.likedIcon : VibeTableViewCell.likeIcon,
                             style: actionStyle, count: likes)
        commentButton.configure(icon: VibeTableViewCell.commentIcon,
                                style: actionStyle, count: comments)
        giftButton.configure(icon: VibeTableViewCell.giftIcon,
                             style: actionStyle, count: gifts)

        likeButton.accessibilityLabel = liked ? "Unlike, \(likes) likes" : "Like, \(likes) likes"
        commentButton.accessibilityLabel = "Comments, \(comments)"
        giftButton.accessibilityLabel = "Gifts, \(gifts)"
    }

    // MARK: - Actions

    @objc private func likeTapped() {
        bounce(likeButton)
        delegate?.vibeCellDidTapLike(self)
    }

    @objc private func commentTapped() {
        bounce(commentButton)
        delegate?.vibeCellDidTapComment(self)
    }

    @objc private func giftTapped() {
        bounce(giftButton)
        delegate?.vibeCellDidTapGift(self)
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
private final class VibeActionButton: UIControl {

    enum Style {
        /// Frosted circle, white icon and count, laid over the vibe photo.
        case overPhoto
        /// Grey circle and dark icon on the white cell, for vibes without a photo.
        case plain
    }

    private static let circleSize: CGFloat = 44

    private let circleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = VibeActionButton.circleSize / 2
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
            circleView.widthAnchor.constraint(equalToConstant: VibeActionButton.circleSize),
            circleView.heightAnchor.constraint(equalToConstant: VibeActionButton.circleSize),

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

    func configure(icon: UIImage?, style: Style, count: Int) {
        iconImageView.image = icon
        countLabel.text = count.vibeCountText

        switch style {
        case .overPhoto:
            blurView.isHidden = false
            circleView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            iconImageView.tintColor = AppColor.AppWhite
            countLabel.textColor = AppColor.AppWhite
            countLabel.font = UIFont.fredoka(.medium, size: 12)
            countLabel.layer.shadowOpacity = 0.6
        case .plain:
            blurView.isHidden = true
            circleView.backgroundColor = AppColor.Iron.withAlphaComponent(0.6)
            iconImageView.tintColor = AppColor.MineShaft
            countLabel.textColor = AppColor.DoveGray
            countLabel.font = UIFont.fredoka(.regular, size: 12)
            countLabel.layer.shadowOpacity = 0
        }
    }
}

// MARK: - Media
extension VibeTableViewCell: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        media.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VibeMediaCollectionViewCell.identifier, for: indexPath) as? VibeMediaCollectionViewCell else {
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
    }
}

/// Bottom-left photo pager: a white pill for the current photo, dots for the rest.
private final class VibePageIndicator: UIView {

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
                self.dotWidthConstraints[index].constant = isActive ? VibePageIndicator.activeWidth : VibePageIndicator.dotSize
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
            dot.layer.cornerRadius = VibePageIndicator.dotSize / 2
            dot.layer.shadowColor = UIColor.black.cgColor
            dot.layer.shadowOpacity = 0.25
            dot.layer.shadowRadius = 2
            dot.layer.shadowOffset = .zero
            return dot
        }
        dotWidthConstraints = dots.map { dot in
            stackView.addArrangedSubview(dot)
            dot.heightAnchor.constraint(equalToConstant: VibePageIndicator.dotSize).isActive = true
            let width = dot.widthAnchor.constraint(equalToConstant: VibePageIndicator.dotSize)
            width.isActive = true
            return width
        }
        currentPage = -1
    }
}
