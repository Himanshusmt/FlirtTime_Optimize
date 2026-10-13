//
//  AddMomentComponents.swift
//  FlirttimeNew
//
//  Views used by `AddMomentViewController` and the location picker: the empty photo
//  placeholder card, capsule chips and the "Where's this moment?" location section.
//

import UIKit

// MARK: - Photo placeholder

/// Dashed "Add photos" card shown in the photo area until the first photo is picked.
/// It does not handle touches; the button it sits in does.
final class AddMomentPhotoPlaceholderView: UIView {

    private let dashLayer = CAShapeLayer()
    private let cardRadius: CGFloat = 20

    init(maxPhotos: Int) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = AppColor.Serenade
        layer.cornerRadius = cardRadius
        layer.cornerCurve = .continuous

        dashLayer.fillColor = UIColor.clear.cgColor
        dashLayer.strokeColor = AppColor.Punch.withAlphaComponent(0.45).cgColor
        dashLayer.lineWidth = 1.5
        dashLayer.lineDashPattern = [7, 5]
        layer.addSublayer(dashLayer)

        let titleLabel = UILabel()
        titleLabel.text = "Add photos"
        titleLabel.font = .fredoka(.medium, size: 20)
        titleLabel.textColor = AppColor.MineShaft
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Share up to \(maxPhotos) photos from your\ncamera or gallery"
        subtitleLabel.font = .fredoka(.regular, size: 14)
        subtitleLabel.textColor = AppColor.DoveGray
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [makeIconBadge(), titleLabel, subtitleLabel, makeSelectPill()])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(18, after: stack.arrangedSubviews[0])
        stack.setCustomSpacing(20, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16)
        ])

        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashLayer.frame = bounds
        dashLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
                                      cornerRadius: cardRadius).cgPath
    }

    func setPressed(_ pressed: Bool) {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.transform = pressed ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            self.alpha = pressed ? 0.85 : 1
        }
    }

    private func makeIconBadge() -> UIView {
        let size: CGFloat = 88
        let circle = UIView()
        circle.backgroundColor = AppColor.AppWhite
        circle.layer.cornerRadius = size / 2
        circle.layer.shadowColor = AppColor.Punch.cgColor
        circle.layer.shadowOpacity = 0.12
        circle.layer.shadowRadius = 12
        circle.layer.shadowOffset = CGSize(width: 0, height: 6)

        let icon = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)))
        icon.tintColor = AppColor.Punch
        icon.contentMode = .scaleAspectFit

        let plus = UIImageView(image: UIImage(systemName: "plus.circle.fill",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)))
        plus.tintColor = AppColor.Punch
        plus.backgroundColor = AppColor.AppWhite
        plus.layer.cornerRadius = 13
        plus.clipsToBounds = true

        [circle, icon, plus].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        circle.addSubview(icon)
        circle.addSubview(plus)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: size),
            circle.heightAnchor.constraint(equalToConstant: size),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            plus.widthAnchor.constraint(equalToConstant: 26),
            plus.heightAnchor.constraint(equalToConstant: 26),
            plus.trailingAnchor.constraint(equalTo: circle.trailingAnchor, constant: -2),
            plus.bottomAnchor.constraint(equalTo: circle.bottomAnchor, constant: -2)
        ])
        return circle
    }

    private func makeSelectPill() -> UIView {
        let pill = UIView()
        pill.backgroundColor = AppColor.Punch
        pill.layer.cornerRadius = 20

        let icon = UIImageView(image: UIImage(systemName: "plus",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
        icon.tintColor = AppColor.AppWhite

        let label = UILabel()
        label.text = "Select photos"
        label.font = .fredoka(.medium, size: 15)
        label.textColor = AppColor.AppWhite

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)
        NSLayoutConstraint.activate([
            pill.heightAnchor.constraint(equalToConstant: 40),
            row.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -20)
        ])
        return pill
    }
}

// MARK: - Chip

/// Capsule chip used for places and date-spot categories.
final class MomentChip: UIControl {

    enum Style {
        /// White with a light border, for recent places and categories.
        case outline
        /// Peach with red text, for the "Add location" call to action.
        case soft
        /// Red gradient with white text, for the selected place or category.
        case filled
    }

    var style: Style {
        didSet { applyStyle() }
    }

    /// Shows a trailing ✕ that calls this instead of the chip's own action.
    var onClear: (() -> Void)? {
        didSet {
            clearButton.isHidden = onClear == nil
            trailingConstraint?.constant = onClear == nil ? -14 : -8
        }
    }

    private let gradientLayer = CAGradientLayer()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let contentStack = UIStackView()
    private var trailingConstraint: NSLayoutConstraint?
    private let height: CGFloat

    init(title: String, symbol: String? = nil, style: Style, height: CGFloat = 40) {
        self.style = style
        self.height = height
        super.init(frame: .zero)
        setUp()
        update(title: title, symbol: symbol)
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, symbol: String?) {
        titleLabel.text = title
        iconView.image = symbol.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        }
        iconView.isHidden = iconView.image == nil
        accessibilityLabel = title
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
    }

    private func setUp() {
        isAccessibilityElement = true
        accessibilityTraits = .button

        gradientLayer.colors = [AppColor.Punch.cgColor, AppColor.Carnation.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradientLayer, at: 0)

        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.font = .fredoka(.medium, size: 14)
        titleLabel.lineBreakMode = .byTruncatingTail

        clearButton.setImage(UIImage(systemName: "xmark",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)), for: .normal)
        clearButton.layer.cornerRadius = 11
        clearButton.isHidden = true
        clearButton.accessibilityLabel = "Remove"
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 6
        [iconView, titleLabel, clearButton].forEach(contentStack.addArrangedSubview)
        contentStack.setCustomSpacing(10, after: titleLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        let trailing = contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        trailingConstraint = trailing
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing,
            clearButton.widthAnchor.constraint(equalToConstant: 22),
            clearButton.heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        ])
    }

    /// The chip handles its own touches; only the ✕ (with some slop) is hit-tested separately.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, self.point(inside: point, with: event) else { return nil }
        if !clearButton.isHidden,
           clearButton.bounds.insetBy(dx: -10, dy: -10).contains(convert(point, to: clearButton)) {
            return clearButton
        }
        return self
    }

    private func applyStyle() {
        gradientLayer.isHidden = style != .filled
        layer.borderWidth = style == .filled ? 0 : 1
        layer.shadowOpacity = 0
        switch style {
        case .outline:
            backgroundColor = AppColor.AppWhite
            layer.borderColor = AppColor.Iron.cgColor
            titleLabel.textColor = AppColor.MineShaft
            iconView.tintColor = AppColor.DoveGray
        case .soft:
            backgroundColor = AppColor.Serenade
            layer.borderColor = AppColor.Punch.withAlphaComponent(0.25).cgColor
            titleLabel.textColor = AppColor.Punch
            iconView.tintColor = AppColor.Punch
        case .filled:
            backgroundColor = .clear
            titleLabel.textColor = AppColor.AppWhite
            iconView.tintColor = AppColor.AppWhite
            layer.shadowColor = AppColor.Punch.cgColor
            layer.shadowOpacity = 0.25
            layer.shadowRadius = 8
            layer.shadowOffset = CGSize(width: 0, height: 4)
        }
        clearButton.tintColor = style == .filled ? AppColor.AppWhite : AppColor.DoveGray
        clearButton.backgroundColor = style == .filled ? UIColor.white.withAlphaComponent(0.25) : AppColor.WildSand
        accessibilityTraits = style == .filled ? [.button, .selected] : .button
    }

    @objc private func clearTapped() {
        onClear?()
    }
}

// MARK: - Location section

/// Location chips on Add Moment: an "Add location" chip, or the tagged place once one is picked.
final class AddMomentLocationSection: UIView {

    var onAddTapped: (() -> Void)?
    var onClear: (() -> Void)?

    private let scrollView = UIScrollView()
    private let chipStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(selected place: MomentPlace?) {
        chipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if let place {
            let selectedChip = MomentChip(title: place.displayText, symbol: "mappin.circle.fill", style: .filled)
            selectedChip.accessibilityLabel = "Location, \(place.displayText)"
            selectedChip.accessibilityHint = "Double tap to change the location"
            selectedChip.onClear = { [weak self] in self?.onClear?() }
            selectedChip.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
            chipStack.addArrangedSubview(selectedChip)

            let changeChip = MomentChip(title: "Change", symbol: "arrow.triangle.2.circlepath", style: .outline)
            changeChip.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
            chipStack.addArrangedSubview(changeChip)
        } else {
            let addChip = MomentChip(title: "Add location", symbol: "mappin.and.ellipse", style: .soft)
            addChip.accessibilityHint = "Double tap to pick a place"
            addChip.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
            chipStack.addArrangedSubview(addChip)
        }
        scrollView.setContentOffset(.zero, animated: false)
    }

    private func setUp() {
        backgroundColor = AppColor.AppWhite

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = false
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        chipStack.axis = .horizontal
        chipStack.spacing = 8
        chipStack.alignment = .center

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(chipStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 48),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            chipStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            chipStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            chipStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            chipStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            chipStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    @objc private func addTapped() {
        onAddTapped?()
    }
}

// MARK: - Photos bar

/// Row under the selected photos: "3 of 5 photos" with progress dots, and an "Add more" chip.
final class AddMomentPhotosBar: UIView {

    var onAddMore: (() -> Void)?

    private let countLabel = UILabel()
    private let dotsStack = UIStackView()
    private let addMoreChip = MomentChip(title: "Add more", symbol: "plus", style: .soft, height: 36)
    private let fullChip = MomentChip(title: "All set", symbol: "checkmark", style: .outline, height: 36)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(count: Int, max: Int) {
        countLabel.text = "\(count) of \(max) photos"
        if dotsStack.arrangedSubviews.count != max {
            dotsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for _ in 0..<max {
                let dot = UIView()
                dot.layer.cornerRadius = 2
                dot.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    dot.widthAnchor.constraint(equalToConstant: 14),
                    dot.heightAnchor.constraint(equalToConstant: 4)
                ])
                dotsStack.addArrangedSubview(dot)
            }
        }
        for (index, dot) in dotsStack.arrangedSubviews.enumerated() {
            dot.backgroundColor = index < count ? AppColor.Punch : AppColor.Iron
        }
        let isFull = count >= max
        addMoreChip.isHidden = isFull
        fullChip.isHidden = !isFull
        accessibilityLabel = countLabel.text
    }

    private func setUp() {
        backgroundColor = AppColor.AppWhite

        countLabel.font = .fredoka(.medium, size: 14)
        countLabel.textColor = AppColor.MineShaft
        dotsStack.axis = .horizontal
        dotsStack.spacing = 4

        let info = UIStackView(arrangedSubviews: [countLabel, dotsStack])
        info.axis = .vertical
        info.alignment = .leading
        info.spacing = 6

        addMoreChip.accessibilityHint = "Double tap to add more photos"
        addMoreChip.addTarget(self, action: #selector(addMoreTapped), for: .touchUpInside)
        fullChip.isUserInteractionEnabled = false
        fullChip.accessibilityLabel = "Photo limit reached"

        [info, addMoreChip, fullChip].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            info.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            info.centerYAnchor.constraint(equalTo: centerYAnchor),
            addMoreChip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            addMoreChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            addMoreChip.leadingAnchor.constraint(greaterThanOrEqualTo: info.trailingAnchor, constant: 12),
            fullChip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            fullChip.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func addMoreTapped() {
        onAddMore?()
    }
}
