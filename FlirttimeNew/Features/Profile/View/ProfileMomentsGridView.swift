//
//  ProfileMomentsGridView.swift
//  FlirttimeNew
//
//  "My Moments" on the Profile tab: FlirtTime's two-column grid of the user's vibes, each
//  showing its first photo. Shows an empty state and an upload strip while a vibe posts.
//

import UIKit

final class ProfileMomentsGridView: UIView {

    /// Height / width of a card, as in FlirtTime's moment grid.
    private static let cardAspect: CGFloat = 1.3048
    private static let spacing: CGFloat = 12

    var onSelect: ((Vibe) -> Void)?
    var onAdd: (() -> Void)?

    private let stack = UIStackView()
    private let uploadStrip = UIView()
    private let uploadProgress = UIProgressView(progressViewStyle: .default)
    private let uploadLabel = UILabel.vibeLabel(.medium, 13, style: .footnote, color: AppColor.MineShaft)
    private let grid = UIStackView()
    private lazy var emptyView = makeEmptyView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical
        stack.spacing = Self.spacing
        addSubview(stack)
        stack.pinEdges(to: self)

        grid.axis = .vertical
        grid.spacing = Self.spacing
        stack.addArrangedSubview(makeUploadStrip())
        stack.addArrangedSubview(grid)
        stack.addArrangedSubview(emptyView)
        uploadStrip.isHidden = true
        emptyView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(vibes: [Vibe]) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        emptyView.isHidden = !vibes.isEmpty
        grid.isHidden = vibes.isEmpty

        for start in stride(from: 0, to: vibes.count, by: 2) {
            let row = UIStackView()
            row.spacing = Self.spacing
            row.distribution = .fillEqually
            row.alignment = .top
            for index in start..<min(start + 2, vibes.count) {
                row.addArrangedSubview(makeCard(for: vibes[index], index: index, total: vibes.count))
            }
            if row.arrangedSubviews.count == 1 {
                row.addArrangedSubview(UIView())
            }
            grid.addArrangedSubview(row)
        }
    }

    /// `nil` hides the upload strip.
    func setUploadProgress(_ progress: Float?) {
        guard let progress else {
            uploadStrip.isHidden = true
            return
        }
        uploadStrip.isHidden = false
        uploadProgress.setProgress(progress, animated: false)
        uploadLabel.text = "Posting your moment… \(Int(progress * 100))%"
    }

    // MARK: - Cards

    private func makeCard(for vibe: Vibe, index: Int, total: Int) -> UIView {
        let card = MomentCardButton()
        card.backgroundColor = AppColor.AthensGray
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.heightAnchor.constraint(equalTo: card.widthAnchor, multiplier: Self.cardAspect).isActive = true

        let photos = (vibe.media ?? []).compactMap(\.filePath).filter { !$0.isEmpty }
        let text = vibe.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let caption = UILabel.vibeLabel(.medium, 13, style: .footnote, color: .white, lines: 2)

        if photos.isEmpty {
            let background = VibeGradientView(colors: VibeTheme.brandGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
            background.isUserInteractionEnabled = false
            card.addSubview(background)
            background.pinEdges(to: card)

            let quote = UILabel.vibeLabel(.bold, 17, style: .headline, color: .white, lines: 0)
            quote.text = text
            quote.textAlignment = .center
            quote.adjustsFontSizeToFitWidth = true
            quote.minimumScaleFactor = 0.6
            quote.isUserInteractionEnabled = false
            card.addSubview(quote)
            quote.pinEdges(to: card, insets: UIEdgeInsets(top: 16, left: 14, bottom: 40, right: 14))
            caption.isHidden = true
        } else {
            let image = UIImageView()
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.isUserInteractionEnabled = false
            image.loadImage(path: photos.first, placeholder: UIImage(named: "failed-image-placeholder"))
            card.addSubview(image)
            image.pinEdges(to: card)

            let shade = VibeGradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.65)],
                                         start: CGPoint(x: 0.5, y: 0.45), end: CGPoint(x: 0.5, y: 1))
            shade.isUserInteractionEnabled = false
            card.addSubview(shade)
            shade.pinEdges(to: card)

            caption.text = text
            caption.isHidden = text.isEmpty
        }

        let stats = UILabel.vibeLabel(.medium, 12, style: .caption1, color: UIColor.white.withAlphaComponent(0.9))
        stats.text = "♥ \((vibe.likesCount ?? 0).vibeCountText)   💬 \((vibe.commentsCount ?? 0).vibeCountText)"

        let info = UIStackView(arrangedSubviews: [caption, stats])
        info.axis = .vertical
        info.spacing = 4
        info.isUserInteractionEnabled = false
        info.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(info)
        NSLayoutConstraint.activate([
            info.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            info.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            info.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])

        if photos.count > 1 {
            let multi = UIImageView(image: UIImage(systemName: "square.on.square.fill",
                                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
            multi.tintColor = .white
            multi.layer.shadowColor = UIColor.black.cgColor
            multi.layer.shadowOpacity = 0.4
            multi.layer.shadowRadius = 3
            multi.layer.shadowOffset = .zero
            multi.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(multi)
            NSLayoutConstraint.activate([
                multi.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
                multi.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10)
            ])
        }

        card.isAccessibilityElement = true
        card.accessibilityTraits = .button
        card.accessibilityLabel = "Your moment \(index + 1) of \(total)"
            + (photos.count > 1 ? ", \(photos.count) photos" : "")
            + (text.isEmpty ? "" : ". \(text)")
            + ". \(vibe.likesCount ?? 0) likes, \(vibe.commentsCount ?? 0) comments"
        card.addAction(UIAction { [weak self] _ in self?.onSelect?(vibe) }, for: .touchUpInside)
        return card
    }

    // MARK: - Upload strip / empty state

    private func makeUploadStrip() -> UIView {
        uploadStrip.backgroundColor = AppColor.Lavenderblush
        uploadStrip.layer.cornerRadius = 14
        uploadProgress.progressTintColor = AppColor.Punch
        uploadProgress.trackTintColor = AppColor.Punch.withAlphaComponent(0.15)
        let column = UIStackView(arrangedSubviews: [uploadLabel, uploadProgress])
        column.axis = .vertical
        column.spacing = 8
        uploadStrip.addSubview(column)
        column.pinEdges(to: uploadStrip, insets: UIEdgeInsets(top: 12, left: 14, bottom: 14, right: 14))
        return uploadStrip
    }

    private func makeEmptyView() -> UIView {
        let box = UIView()
        box.backgroundColor = AppColor.Lavenderblush
        box.layer.cornerRadius = 20
        box.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)))
        icon.tintColor = AppColor.Punch
        icon.contentMode = .center

        let title = UILabel.vibeLabel(.bold, 17, style: .headline, color: AppColor.AppBlack)
        title.text = "No Moments yet!"
        title.textAlignment = .center

        let subtitle = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: AppColor.DoveGray, lines: 0)
        subtitle.text = "Share photos from your day so your matches get to know you."
        subtitle.textAlignment = .center

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Punch
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        config.attributedTitle = AttributedString("Add Moment", attributes: AttributeContainer([.font: VibeFont.scaled(.medium, 15)]))
        let add = UIButton(configuration: config)
        add.addAction(UIAction { [weak self] _ in self?.onAdd?() }, for: .touchUpInside)

        let column = UIStackView(arrangedSubviews: [icon, title, subtitle, add])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 6
        column.setCustomSpacing(16, after: subtitle)
        box.addSubview(column)
        column.pinEdges(to: box, insets: UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20))
        return box
    }
}

private final class MomentCardButton: UIControl {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }
}
