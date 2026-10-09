//
//  VibeCardView.swift
//  FlirttimeNew
//
//  Discover card: photo first, then who they are and what they're into.
//  Shows the profile photo only; tap to open the full profile (with the gallery), double-tap to like.
//  Swipes are handled by the stack.
//

import UIKit

protocol VibeCardViewDelegate: AnyObject {
    func vibeCardDidTapProfile(_ card: VibeCardView)
    func vibeCardDidTapVerification(_ card: VibeCardView)
    func vibeCard(_ card: VibeCardView, didTapInterest interest: VibeInterest)
    func vibeCard(_ card: VibeCardView, didReact reaction: VibeReaction)
}

final class VibeCardView: UIView {

    weak var delegate: VibeCardViewDelegate?
    let profile: VibeProfile

    /// Swipe-equivalent actions supplied by the stack, offered alongside the card's own.
    var stackAccessibilityActions: [UIAccessibilityCustomAction] = [] {
        didSet { updateAccessibility() }
    }

    private let contentView = UIView()
    private let photoView = UIImageView()
    private let detailsStack = UIStackView()

    let overlay = GestureActionOverlay()
    private let glowLayer = CALayer()

    init(profile: VibeProfile) {
        self.profile = profile
        super.init(frame: .zero)
        setUI()
        photoView.loadImage(path: profile.photos.first, placeholder: UIImage(named: "ProfileBlur"))
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI

    private func setUI() {
        layer.shadowColor = UIColor(red: 0.45, green: 0.05, blue: 0.1, alpha: 1).cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 10)

        glowLayer.cornerRadius = 28
        glowLayer.borderWidth = 3
        glowLayer.opacity = 0
        layer.addSublayer(glowLayer)

        contentView.backgroundColor = AppColor.AthensGray
        contentView.layer.cornerRadius = 28
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.maximumContentSizeCategory = .accessibilityMedium
        addSubview(contentView)
        contentView.pinEdges(to: self)

        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.isUserInteractionEnabled = true
        contentView.addSubview(photoView)
        photoView.pinEdges(to: contentView)

        let shade = VibeGradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.2), UIColor.black.withAlphaComponent(0.78)],
                                     start: CGPoint(x: 0.5, y: 0.45), end: CGPoint(x: 0.5, y: 1), locations: [0, 0.35, 1])
        shade.isUserInteractionEnabled = false
        contentView.addSubview(shade)
        shade.pinEdges(to: contentView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handlePhotoTap(_:)))
        singleTap.require(toFail: doubleTap)
        photoView.addGestureRecognizer(doubleTap)
        photoView.addGestureRecognizer(singleTap)

        setTopBadges()
        setDetails()
        contentView.addSubview(overlay)
        overlay.pinEdges(to: contentView)

        isAccessibilityElement = true
    }

    private func setTopBadges() {
        let topShade = VibeGradientView(colors: [UIColor.black.withAlphaComponent(0.35), .clear],
                                        start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
        topShade.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(topShade)

        var badges: [UIView] = []
        if profile.isOnline == true {
            let online = PaddedPillLabel()
            online.setDot(AppColor.OceanGreen)
            online.text = "Online now"
            badges.append(online)
        }
        badges.append(UIView())
        if let score = profile.vibeScore {
            badges.append(VibeScoreBadge(score: score))
        }
        let row = UIStackView(arrangedSubviews: badges)
        row.alignment = .center

        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            topShade.topAnchor.constraint(equalTo: contentView.topAnchor),
            topShade.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topShade.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topShade.heightAnchor.constraint(equalToConstant: 90),

            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14)
        ])
    }

    private func setDetails() {
        let nameLabel = UILabel.vibeLabel(.bold, 30, style: .largeTitle, color: .white)
        nameLabel.text = profile.nameAndAge
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7
        let nameRow = UIStackView(arrangedSubviews: [nameLabel])
        nameRow.spacing = 6
        nameRow.alignment = .center
        if profile.isVerified {
            let verified = UIButton(type: .system)
            verified.setImage(UIImage(systemName: "checkmark.seal.fill",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)), for: .normal)
            verified.tintColor = UIColor(red: 0.36, green: 0.67, blue: 1, alpha: 1)
            verified.accessibilityLabel = "Verified profile"
            verified.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.vibeCardDidTapVerification(self)
            }, for: .touchUpInside)
            verified.setContentHuggingPriority(.required, for: .horizontal)
            nameRow.addArrangedSubview(verified)
        }

        var openConfig = UIButton.Configuration.filled()
        openConfig.cornerStyle = .capsule
        openConfig.baseBackgroundColor = UIColor.white.withAlphaComponent(0.25)
        openConfig.baseForegroundColor = .white
        openConfig.image = UIImage(systemName: "chevron.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        let openButton = UIButton(configuration: openConfig)
        openButton.accessibilityLabel = "View \(profile.displayName)'s profile"
        openButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.vibeCardDidTapProfile(self)
        }, for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [nameRow, UIView(), openButton])
        headerRow.alignment = .center
        headerRow.spacing = 8
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)

        detailsStack.addArrangedSubview(headerRow)
        detailsStack.axis = .vertical
        detailsStack.spacing = 4
        if let line = profile.locationLine {
            let pin = UIImageView(image: UIImage(systemName: "location.fill",
                                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
            pin.tintColor = UIColor.white.withAlphaComponent(0.92)
            pin.setContentHuggingPriority(.required, for: .horizontal)
            let location = UILabel.vibeLabel(.regular, 15, style: .subheadline, color: UIColor.white.withAlphaComponent(0.92))
            location.text = line
            let locationRow = UIStackView(arrangedSubviews: [pin, location])
            locationRow.spacing = 5
            locationRow.alignment = .center
            detailsStack.addArrangedSubview(locationRow)
        }
        var highlights: [UIView] = []
        if let intent = profile.datingIntent {
            let emoji = FilterModel.datingIntents.first { $0.title == intent }?.emoji ?? "💫"
            highlights.append(GlassTagView(text: "\(emoji) \(intent)"))
        }
        if let shared = profile.sharedVibesText {
            highlights.append(GlassTagView(text: "💞 \(shared)", tint: AppColor.Punch.withAlphaComponent(0.85)))
        }
        if !highlights.isEmpty {
            let row = UIStackView(arrangedSubviews: highlights + [UIView()])
            row.spacing = 6
            detailsStack.setCustomSpacing(10, after: detailsStack.arrangedSubviews[detailsStack.arrangedSubviews.count - 1])
            detailsStack.addArrangedSubview(row)
        }
        if !profile.interests.isEmpty {
            let sharedIDs = Set(profile.sharedInterests.map(\.id))
            let ordered = profile.interests.filter { sharedIDs.contains($0.id) } + profile.interests.filter { !sharedIDs.contains($0.id) }
            let chips = VibeChipsView()
            chips.style = .onPhoto
            chips.maxLines = 2
            chips.configure(ordered, highlighted: sharedIDs, maxCount: 6)
            chips.onTap = { [weak self] interest in
                guard let self else { return }
                self.delegate?.vibeCard(self, didTapInterest: interest)
            }
            detailsStack.addArrangedSubview(chips)
            detailsStack.setCustomSpacing(12, after: detailsStack.arrangedSubviews[detailsStack.arrangedSubviews.count - 2])
        }
        detailsStack.isUserInteractionEnabled = true
        detailsStack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(detailsTapped)))
        detailsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailsStack)
        NSLayoutConstraint.activate([
            openButton.widthAnchor.constraint(equalToConstant: 34),
            openButton.heightAnchor.constraint(equalToConstant: 34),
            detailsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            detailsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            detailsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 28).cgPath
        glowLayer.frame = bounds
    }

    // MARK: - Taps

    @objc private func handlePhotoTap(_ tap: UITapGestureRecognizer) {
        delegate?.vibeCardDidTapProfile(self)
    }

    @objc private func handleDoubleTap(_ tap: UITapGestureRecognizer) {
        react(at: tap.location(in: contentView))
    }

    @objc private func detailsTapped() {
        delegate?.vibeCardDidTapProfile(self)
    }

    private func react(at point: CGPoint?) {
        let origin = point ?? CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        HeartBurst.show(in: contentView, at: origin)
        VibeHaptics.threshold()
        delegate?.vibeCard(self, didReact: VibeReaction(target: .photo(0)))
    }

    // MARK: - Drag feedback

    func updateDrag(action: VibeAction?, progress: CGFloat) {
        overlay.update(action: action, progress: progress)
        let glow = action == .superVibe ? Float(max(0, min(progress, 1))) : 0
        glowLayer.borderColor = VibeTheme.gold.cgColor
        glowLayer.shadowColor = VibeTheme.gold.cgColor
        glowLayer.shadowRadius = 18
        glowLayer.shadowOpacity = glow
        glowLayer.shadowOffset = .zero
        glowLayer.opacity = glow
    }

    // MARK: - Accessibility

    private func updateAccessibility() {
        accessibilityLabel = profile.accessibilitySummary + (profile.vibeScore.map { ". \($0)% vibe match" } ?? "")
        var actions = [
            UIAccessibilityCustomAction(name: "View full profile") { [weak self] _ in
                guard let self else { return false }
                self.delegate?.vibeCardDidTapProfile(self)
                return true
            },
            UIAccessibilityCustomAction(name: "Like this photo") { [weak self] _ in
                self?.react(at: nil)
                return true
            }
        ]
        if profile.isVerified {
            actions.append(UIAccessibilityCustomAction(name: "What verification means") { [weak self] _ in
                guard let self else { return false }
                self.delegate?.vibeCardDidTapVerification(self)
                return true
            })
        }
        accessibilityCustomActions = actions + stackAccessibilityActions
    }
}

/// "🔥 92% Vibe" on the brand gradient.
private final class VibeScoreBadge: UIView {
    init(score: Int) {
        super.init(frame: .zero)
        let gradient = VibeGradientView(colors: VibeTheme.brandGradient, start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))
        gradient.layer.cornerRadius = 14
        gradient.clipsToBounds = true
        addSubview(gradient)
        gradient.pinEdges(to: self)
        let label = UILabel.vibeLabel(.bold, 13, style: .caption1, color: .white)
        label.text = "🔥 \(score)% Vibe"
        addSubview(label)
        label.pinEdges(to: self, insets: UIEdgeInsets(top: 6, left: 11, bottom: 6, right: 11))
        layer.shadowColor = AppColor.Punch.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Frosted tag under the name: "💍 Long-term".
private final class GlassTagView: UIView {
    init(text: String, tint: UIColor? = nil) {
        super.init(frame: .zero)
        layer.cornerRadius = 13
        layer.cornerCurve = .continuous
        clipsToBounds = true
        if let tint {
            backgroundColor = tint
        } else {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
            blur.isUserInteractionEnabled = false
            addSubview(blur)
            blur.pinEdges(to: self)
            layer.borderWidth = 1
            layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        }
        let label = UILabel.vibeLabel(.medium, 13, style: .footnote, color: .white)
        label.text = text
        addSubview(label)
        label.pinEdges(to: self, insets: UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10))
        setContentHuggingPriority(.required, for: .horizontal)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Small dark glass pill: "Online now", "1/5".
final class PaddedPillLabel: UIView {

    private let label = UILabel.vibeLabel(.medium, 12, style: .caption1, color: .white)
    private let dot = UIView()

    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }

    init(dark: Bool = true) {
        super.init(frame: .zero)
        backgroundColor = dark ? UIColor.black.withAlphaComponent(0.4) : UIColor.white.withAlphaComponent(0.9)
        label.textColor = dark ? .white : AppColor.MineShaft
        layer.cornerRadius = 13
        dot.layer.cornerRadius = 4
        dot.isHidden = true
        let row = UIStackView(arrangedSubviews: [dot, label])
        row.spacing = 6
        row.alignment = .center
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10))
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDot(_ color: UIColor) {
        dot.backgroundColor = color
        dot.isHidden = false
    }
}
