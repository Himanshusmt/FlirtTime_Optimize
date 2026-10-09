//
//  VibeConnectionViewController.swift
//  FlirttimeNew
//
//  "Vibe Sent" (no mutual interest yet) and "It's a Vibe" (mutual connection).
//

import UIKit

final class VibeConnectionViewController: UIViewController {

    enum Mode {
        case sent(VibeProfile)
        case matched(VibeProfile)

        var profile: VibeProfile {
            switch self {
            case .sent(let profile), .matched(let profile): return profile
            }
        }

        var isMatch: Bool {
            if case .matched = self { return true }
            return false
        }
    }

    var onStartConversation: ((VibeProfile) -> Void)?

    private let mode: Mode
    private let reaction: VibeReaction?
    private let backgroundView = VibeGradientView(colors: [AppColor.AppWhite, VibeTheme.blushGradient[1]],
                                                  start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
    private let photosView = UIView()
    private let contentStack = UIStackView()
    private var avatars: [UIView] = []
    private let topHeart = UIImageView(image: UIImage(systemName: "heart.fill",
                                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .bold)))

    init(mode: Mode, reaction: VibeReaction? = nil) {
        self.mode = mode
        self.reaction = reaction
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(backgroundView)
        backgroundView.pinEdges(to: view)
        view.maximumContentSizeCategory = .accessibilityMedium

        topHeart.tintColor = AppColor.Punch
        topHeart.contentMode = .center
        topHeart.isAccessibilityElement = false
        buildPhotos()
        contentStack.axis = .vertical
        contentStack.spacing = 12
        content().forEach(contentStack.addArrangedSubview)

        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        let column = UIStackView(arrangedSubviews: [topHeart, photosView, contentStack])
        column.axis = .vertical
        column.spacing = 18
        column.setCustomSpacing(26, after: photosView)
        [scroll, column].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scroll)
        scroll.addSubview(column)

        let centered = column.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor)
        centered.priority = .defaultLow
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            column.bottomAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            column.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 28),
            column.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -28),
            column.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -56),
            scroll.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
            centered,
            photosView.heightAnchor.constraint(equalToConstant: 140)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(notification: .screenChanged, argument: contentStack.arrangedSubviews.first)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        animateIn()
        if mode.isMatch { burstConfetti() }
    }

    // MARK: - Photos

    private func buildPhotos() {
        let size: CGFloat = 128
        let theirs = avatar(path: mode.profile.photos.first, size: size)
        photosView.addSubview(theirs)
        if mode.isMatch {
            let mine = avatar(path: MockDataStore.shared.currentUserResponse()?.data?.userInfo?.avatar, size: size)
            photosView.insertSubview(mine, belowSubview: theirs)
            avatars = [mine, theirs]
            NSLayoutConstraint.activate([
                mine.trailingAnchor.constraint(equalTo: photosView.centerXAnchor, constant: 18),
                mine.centerYAnchor.constraint(equalTo: photosView.centerYAnchor),
                theirs.leadingAnchor.constraint(equalTo: photosView.centerXAnchor, constant: -18),
                theirs.centerYAnchor.constraint(equalTo: photosView.centerYAnchor)
            ])
        } else {
            avatars = [theirs]
            NSLayoutConstraint.activate([
                theirs.centerXAnchor.constraint(equalTo: photosView.centerXAnchor),
                theirs.centerYAnchor.constraint(equalTo: photosView.centerYAnchor)
            ])
        }

        let badge = UIImageView(image: UIImage(systemName: "heart.fill",
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)))
        badge.tintColor = .white
        badge.contentMode = .center
        badge.backgroundColor = AppColor.Punch
        badge.layer.cornerRadius = 20
        badge.layer.borderWidth = 3
        badge.layer.borderColor = UIColor.white.cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        photosView.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 40),
            badge.heightAnchor.constraint(equalToConstant: 40),
            badge.centerXAnchor.constraint(equalTo: photosView.centerXAnchor, constant: mode.isMatch ? 0 : 46),
            badge.bottomAnchor.constraint(equalTo: theirs.bottomAnchor, constant: 4)
        ])
    }

    private func avatar(path: String?, size: CGFloat) -> UIView {
        let image = UIImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = size / 2
        image.layer.borderWidth = 4
        image.layer.borderColor = UIColor.white.cgColor
        image.backgroundColor = AppColor.AthensGray
        image.loadImage(path: path, placeholder: UIImage(named: "ProfileBlur"))
        image.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: size),
            image.heightAnchor.constraint(equalToConstant: size)
        ])
        let shadow = UIView()
        shadow.translatesAutoresizingMaskIntoConstraints = false
        shadow.layer.shadowColor = AppColor.Punch.cgColor
        shadow.layer.shadowOpacity = 0.25
        shadow.layer.shadowRadius = 14
        shadow.layer.shadowOffset = CGSize(width: 0, height: 8)
        shadow.addSubview(image)
        image.pinEdges(to: shadow)
        return shadow
    }

    // MARK: - Content

    private func content() -> [UIView] {
        let profile = mode.profile
        var views: [UIView] = []

        let title = label(mode.isMatch ? "It's a Vibe!" : "Vibe Sent", font: VibeFont.scaled(.bold, 38, style: .largeTitle), color: AppColor.Punch)
        title.accessibilityTraits = .header
        views.append(title)

        let message: String
        if mode.isMatch {
            message = profile.sharedInterests.isEmpty
                ? "You and \(profile.displayName) are into each other."
                : "You and \(profile.displayName) have connected based on shared interests."
        } else {
            message = "If \(profile.displayName) feels it too, you'll connect. We'll let you know."
        }
        views.append(label(message, font: VibeFont.scaled(.regular, 16), color: AppColor.DoveGray))

        if let reaction {
            views.append(centered(reactionPill("💗 You liked \(reaction.subject(for: profile.displayName))")))
        }

        if mode.isMatch, !profile.sharedInterests.isEmpty {
            let chips = VibeChipsView()
            chips.style = .outlined
            chips.isCentered = true
            chips.maxLines = 2
            chips.configure(profile.sharedInterests, highlighted: [], maxCount: 4)
            chips.isUserInteractionEnabled = false
            views.append(chips)
            if let first = profile.sharedInterests.first, let starter = VibeInterestCatalog.conversationStarter(for: first) {
                views.append(starterView(starter))
            }
        }

        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        views.append(spacer)

        if mode.isMatch {
            views.append(button("Start Conversation", filled: true) { [weak self] in
                guard let self else { return }
                self.dismiss(animated: true) { self.onStartConversation?(profile) }
            })
            views.append(button("Keep Exploring", filled: false) { [weak self] in self?.dismiss(animated: true) })
        } else {
            views.append(button("Keep Exploring", filled: true) { [weak self] in self?.dismiss(animated: true) })
        }
        return views
    }

    private func reactionPill(_ text: String) -> UIView {
        let pill = UIView()
        pill.backgroundColor = AppColor.Lavenderblush
        pill.layer.cornerRadius = 15
        let label = UILabel.vibeLabel(.medium, 13, style: .footnote, color: AppColor.Punch)
        label.text = text
        pill.addSubview(label)
        label.pinEdges(to: pill, insets: UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12))
        return pill
    }

    private func centered(_ view: UIView) -> UIView {
        let wrapper = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: wrapper.topAnchor),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            view.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor)
        ])
        return wrapper
    }

    private func starterView(_ starter: String) -> UIView {
        let container = UIView()
        container.backgroundColor = AppColor.AppWhite
        container.layer.cornerRadius = 18
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.06
        container.layer.shadowRadius = 10
        container.layer.shadowOffset = CGSize(width: 0, height: 4)
        let caption = UILabel.vibeLabel(.bold, 11, style: .caption1, color: AppColor.Punch)
        caption.attributedText = NSAttributedString(string: "💬 OPEN WITH", attributes: [.kern: 1.2])
        let text = UILabel.vibeLabel(.medium, 15, color: AppColor.MineShaft, lines: 0)
        text.text = "“\(starter)”"
        let stack = UIStackView(arrangedSubviews: [caption, text])
        stack.axis = .vertical
        stack.spacing = 4
        container.addSubview(stack)
        stack.pinEdges(to: container, insets: UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
        container.isAccessibilityElement = true
        container.accessibilityLabel = "Suggested opener: \(starter)"
        return container
    }

    private func label(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func button(_ title: String, filled: Bool, action: @escaping () -> Void) -> UIButton {
        var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Punch
        config.baseForegroundColor = filled ? .white : AppColor.Punch
        config.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 20, bottom: 15, trailing: 20)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: VibeFont.scaled(filled ? .bold : .medium, 17)]))
        let button = UIButton(configuration: config)
        if filled {
            button.layer.shadowColor = AppColor.Punch.cgColor
            button.layer.shadowOpacity = 0.35
            button.layer.shadowRadius = 12
            button.layer.shadowOffset = CGSize(width: 0, height: 6)
        }
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Animation

    private func animateIn() {
        for (index, avatar) in avatars.enumerated() {
            let fromX: CGFloat = avatars.count == 1 ? 0 : (index == 0 ? -120 : 120)
            avatar.transform = CGAffineTransform(translationX: fromX, y: 0).scaledBy(x: 0.6, y: 0.6)
            avatar.alpha = 0
        }
        topHeart.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        contentStack.alpha = 0
        contentStack.transform = CGAffineTransform(translationX: 0, y: 24)
        UIView.animate(withDuration: 0.6, delay: 0.05, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4) {
            self.avatars.forEach {
                $0.transform = .identity
                $0.alpha = 1
            }
        }
        UIView.animate(withDuration: 0.5, delay: 0.3, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.8) {
            self.topHeart.transform = .identity
        }
        UIView.animate(withDuration: 0.45, delay: 0.25, options: .curveEaseOut) {
            self.contentStack.alpha = 1
            self.contentStack.transform = .identity
        }
    }

    private func burstConfetti() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: view.bounds.width, height: 1)
        let colors: [UIColor] = [AppColor.Punch, VibeTheme.gold, UIColor(red: 1, green: 0.6, blue: 0.7, alpha: 1)]
        let heart = heartImage()
        emitter.emitterCells = colors.flatMap { color -> [CAEmitterCell] in
            let confetti = CAEmitterCell()
            confetti.contents = confettiImage(color: color).cgImage
            confetti.birthRate = 5
            confetti.lifetime = 6
            confetti.velocity = 170
            confetti.velocityRange = 70
            confetti.emissionLongitude = .pi
            confetti.emissionRange = .pi / 5
            confetti.spin = 3
            confetti.spinRange = 4
            confetti.scale = 0.6
            confetti.scaleRange = 0.25
            confetti.yAcceleration = 110
            confetti.alphaSpeed = -0.1

            let heartCell = CAEmitterCell()
            heartCell.contents = heart.cgImage
            heartCell.color = color.cgColor
            heartCell.birthRate = 1.2
            heartCell.lifetime = 6
            heartCell.velocity = 130
            heartCell.velocityRange = 50
            heartCell.emissionLongitude = .pi
            heartCell.emissionRange = .pi / 6
            heartCell.scale = 0.5
            heartCell.scaleRange = 0.2
            heartCell.yAcceleration = 80
            heartCell.alphaSpeed = -0.12
            return [confetti, heartCell]
        }
        view.layer.insertSublayer(emitter, above: backgroundView.layer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { emitter.removeFromSuperlayer() }
    }

    private func heartImage() -> UIImage {
        let symbol = UIImage(systemName: "heart.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))!
        return UIGraphicsImageRenderer(size: symbol.size).image { _ in
            symbol.withTintColor(.white).draw(at: .zero)
        }
    }

    private func confettiImage(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 14)).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 8, height: 14), cornerRadius: 2).fill()
        }
    }
}
