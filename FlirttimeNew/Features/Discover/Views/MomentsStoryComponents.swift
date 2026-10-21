//
//  MomentsStoryComponents.swift
//  FlirttimeNew
//
//  Visual building blocks for the Vibe Card, Vibe Details and connection screens.
//

import UIKit

// MARK: - Gradient

final class MomentsGradientView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    init(colors: [UIColor], start: CGPoint = CGPoint(x: 0, y: 0), end: CGPoint = CGPoint(x: 1, y: 1), locations: [NSNumber]? = nil) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = start
        gradient.endPoint = end
        gradient.locations = locations
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setColors(_ colors: [UIColor]) {
        gradient.colors = colors.map(\.cgColor)
    }
}

extension UIView {
    /// Soft blush-to-white wash used behind Discover, Premium and the main tabs.
    func addBlushBackground() {
        let background = MomentsGradientView(colors: [MomentsTheme.blushGradient[0], AppColor.AppWhite],
                                          start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 0.5))
        backgroundColor = AppColor.AppWhite
        insertSubview(background, at: 0)
        background.pinEdges(to: self)
    }

    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
    }
}

// MARK: - Heart burst

enum HeartBurst {
    static let identifier = "heartBurst"

    static func show(in view: UIView, at point: CGPoint, color: UIColor = AppColor.Punch) {
        let heart = UIImageView(image: UIImage(systemName: "heart.fill"))
        heart.accessibilityIdentifier = identifier
        heart.tintColor = color
        heart.frame = CGRect(x: 0, y: 0, width: 96, height: 88)
        heart.center = point
        heart.layer.shadowColor = UIColor.black.cgColor
        heart.layer.shadowOpacity = 0.25
        heart.layer.shadowRadius = 10
        heart.isUserInteractionEnabled = false
        view.addSubview(heart)

        if UIAccessibility.isReduceMotionEnabled {
            heart.alpha = 0.95
            UIView.animate(withDuration: 0.25, delay: 0.25, options: []) { heart.alpha = 0 } completion: { _ in heart.removeFromSuperview() }
            return
        }
        heart.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        heart.alpha = 0
        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8) {
            heart.transform = CGAffineTransform(scaleX: 1.1, y: 1.1).rotated(by: -.pi / 18)
            heart.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.1, options: .curveEaseIn) {
                heart.transform = CGAffineTransform(translationX: 0, y: -50).scaledBy(x: 1.4, y: 1.4)
                heart.alpha = 0
            } completion: { _ in
                heart.removeFromSuperview()
            }
        }
    }
}

// MARK: - Quick Moment status ring (WhatsApp-style)

/// Segmented ring around a tray avatar: one arc per active Quick Moment.
/// Unviewed segments use the brand red; viewed segments use light gray. Gaps appear when count ≥ 2.
final class QuickMomentStatusRingView: UIView {

    var lineWidth: CGFloat = 2.5 {
        didSet { setNeedsLayout() }
    }
    var unreadColor: UIColor = AppColor.Punch {
        didSet { applyColors() }
    }
    /// Light gray for already-seen segments (`isViewed == true`).
    var viewedColor: UIColor = AppColor.SilverChalice {
        didSet { applyColors() }
    }

    /// Parallel to segments, oldest → newest (clockwise from the top). `true` = viewed.
    private var segmentViewed: [Bool] = []
    private var segmentLayers: [CAShapeLayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(segmentViewed: [Bool]) {
        self.segmentViewed = segmentViewed
        rebuildLayersIfNeeded()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePaths()
    }

    private func rebuildLayersIfNeeded() {
        let count = segmentViewed.count
        while segmentLayers.count > count {
            segmentLayers.removeLast().removeFromSuperlayer()
        }
        while segmentLayers.count < count {
            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.lineCap = .butt
            layer.contentsScale = UIScreen.main.scale
            self.layer.addSublayer(layer)
            segmentLayers.append(layer)
        }
        applyColors()
    }

    private func applyColors() {
        for (index, layer) in segmentLayers.enumerated() {
            let viewed = segmentViewed.indices.contains(index) ? segmentViewed[index] : false
            layer.strokeColor = (viewed ? viewedColor : unreadColor).cgColor
            layer.lineWidth = lineWidth
        }
    }

    private func updatePaths() {
        let count = segmentLayers.count
        guard count > 0, bounds.width > 0, bounds.height > 0 else { return }

        let inset = lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let twoPi = 2 * CGFloat.pi
        // WhatsApp-like gaps: none for a single story; otherwise scale down as count grows.
        let gap: CGFloat = {
            guard count > 1 else { return 0 }
            let degrees: CGFloat = count <= 3 ? 14 : max(8, 36 / CGFloat(count))
            return degrees * .pi / 180
        }()
        let sweep = (twoPi - gap * CGFloat(count)) / CGFloat(count)
        var start = -CGFloat.pi / 2 + gap / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in segmentLayers {
            let end = start + max(sweep, 0.01)
            let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            layer.path = path.cgPath
            layer.frame = bounds
            layer.lineWidth = lineWidth
            start = end + gap
        }
        CATransaction.commit()
    }
}

extension QuickMomentTrayItem {
    /// Per-segment viewed flags for `QuickMomentStatusRingView`, oldest → newest.
    /// Own stories stay “unread” (brand color) so the ring reads as active.
    func statusRingSegmentViewed(isMine: Bool) -> [Bool] {
        let count = max(1, max(activeCount, stories.count))
        if isMine {
            return Array(repeating: false, count: count)
        }
        if stories.count >= count {
            return Array(stories.suffix(count).reversed().map(\.hasViewed))
        }
        if !stories.isEmpty {
            // Oldest → newest among known stories, then pad unknown slots from tray unread flag.
            var flags = stories.reversed().map(\.hasViewed)
            let pad = count - flags.count
            flags += Array(repeating: !hasUnread, count: pad)
            return flags
        }
        return Array(repeating: !hasUnread, count: count)
    }
}

// MARK: - Add-new bubble (Profile + Chat list)

/// Same “Add new” control as Profile Quick Moments: faded avatar, Punch plus, vibe caption.
final class QuickMomentAddBubbleView: UIView {

    static let bubbleSize: CGFloat = 70

    private let circle = UIView()
    private let avatar = UIImageView()
    private let plus = UIImageView(
        image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
    )
    private let titleLabel = UILabel.vibeLabel(.medium, 12, style: .caption1, color: AppColor.Punch)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(avatarPath: String?) {
        avatar.loadImage(path: avatarPath, placeholder: UIImage(named: "ProfileBlur"))
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.bubbleSize + 4, height: 96)
    }

    private func setUp() {
        clipsToBounds = false
        isUserInteractionEnabled = false

        let size = Self.bubbleSize
        circle.backgroundColor = AppColor.Lavenderblush
        circle.layer.cornerRadius = size / 2
        circle.layer.borderWidth = 1.5
        circle.layer.borderColor = AppColor.Punch.withAlphaComponent(0.35).cgColor
        circle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circle)

        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = (size - 12) / 2
        avatar.alpha = 0.55
        avatar.image = UIImage(named: "ProfileBlur")
        circle.addSubview(avatar)
        avatar.pinEdges(to: circle, insets: UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6))

        plus.tintColor = .white
        plus.contentMode = .center
        plus.backgroundColor = AppColor.Punch
        plus.layer.cornerRadius = 12
        plus.clipsToBounds = true
        plus.layer.borderWidth = 2
        plus.layer.borderColor = UIColor.white.cgColor
        plus.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(plus)

        titleLabel.text = "Add new"
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: topAnchor),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.widthAnchor.constraint(equalToConstant: size),
            circle.heightAnchor.constraint(equalToConstant: size),
            plus.widthAnchor.constraint(equalToConstant: 24),
            plus.heightAnchor.constraint(equalToConstant: 24),
            plus.trailingAnchor.constraint(equalTo: circle.trailingAnchor, constant: 2),
            plus.bottomAnchor.constraint(equalTo: circle.bottomAnchor, constant: 2),
            titleLabel.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: size + 4)
        ])
    }
}

// MARK: - Voice waveform

final class VoiceWaveformView: UIView {

    private var bars: [UIView] = []
    private let stack = UIStackView()
    var activeColor: UIColor = .white
    var inactiveColor: UIColor = UIColor.white.withAlphaComponent(0.35)

    init(seed: Int, barCount: Int = 28) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        stack.alignment = .center
        stack.distribution = .equalSpacing
        addSubview(stack)
        stack.pinEdges(to: self)
        var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 2654435761))
        for _ in 0..<barCount {
            let bar = UIView()
            bar.layer.cornerRadius = 2
            let fraction = CGFloat.random(in: 0.25...1, using: &generator)
            stack.addArrangedSubview(bar)
            bar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: 4),
                bar.heightAnchor.constraint(equalTo: heightAnchor, multiplier: fraction)
            ])
            bars.append(bar)
        }
        setProgress(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setProgress(_ progress: Double) {
        let lit = Int((progress * Double(bars.count)).rounded(.down))
        for (index, bar) in bars.enumerated() {
            bar.backgroundColor = index < lit ? activeColor : inactiveColor
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
