//
//  VibeCardStackView.swift
//  FlirttimeNew
//
//  Active card plus the preloaded next card, driven by a single pan gesture:
//  horizontal-dominant drags map to Interested / Not My Vibe, vertical-dominant ones to
//  Super Vibe / Nope. Ambiguous diagonals never commit.
//

import UIKit

protocol VibeCardStackViewDelegate: AnyObject {
    func cardStackShouldBeginInteraction(_ stack: VibeCardStackView) -> Bool
    func cardStack(_ stack: VibeCardStackView, didBeginDragging profile: VibeProfile)
    func cardStack(_ stack: VibeCardStackView, didCancelDragging profile: VibeProfile)
    /// The card has started leaving the screen; the next card is already active.
    func cardStack(_ stack: VibeCardStackView, didCommit action: VibeAction, for profile: VibeProfile)
}

final class VibeCardStackView: UIView {

    struct Configuration {
        /// Fraction of the card's width (horizontal) or height (vertical) that commits an action.
        var commitFraction: CGFloat = 0.3
        /// Release speed (pt/s) along the drag direction that counts as intent on its own…
        var commitVelocity: CGFloat = 900
        /// …provided the card has travelled at least this fraction of the threshold.
        var minimumProgressForVelocity: CGFloat = 0.35
        /// One axis must exceed the other by this ratio for the drag to have a direction.
        var dominanceRatio: CGFloat = 1.25
        var minimumDragDistance: CGFloat = 12
    }

    weak var delegate: VibeCardStackViewDelegate?
    weak var cardDelegate: VibeCardViewDelegate?
    var configuration = Configuration()

    /// Provided by the owner so the accessibility actions mirror the gestures.
    var onAccessibilityViewProfile: (() -> Void)?

    private(set) var topCard: VibeCardView?
    private var backCard: VibeCardView?

    private var dragAction: VibeAction?
    private var didCrossThreshold = false
    private var isTransitioning = false

    private static let backScale: CGFloat = 0.94
    private static let backOffset: CGFloat = 26

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        for card in [backCard, topCard].compactMap({ $0 }) {
            let transform = card.transform
            card.transform = .identity
            card.frame = bounds
            card.transform = transform
        }
    }

    // MARK: - Content

    /// Brings the stack in line with the deck. `returningFrom` animates a restored card back in
    /// from the side it left through.
    func sync(current: VibeProfile?, next: VibeProfile?, returningFrom action: VibeAction? = nil) {
        guard let current else {
            [topCard, backCard].forEach { $0?.removeFromSuperview() }
            topCard = nil
            backCard = nil
            return
        }

        if topCard?.profile == current {
            syncBackCard(with: next)
            return
        }

        let card = makeCard(current)
        if let action, topCard != nil, !reduceMotion {
            // The restored profile slides back on top; the old top card returns to the back.
            backCard?.removeFromSuperview()
            backCard = topCard
            topCard = card
            addSubview(card)
            card.transform = offscreenTransform(for: action, from: .identity)
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4) {
                card.transform = .identity
                self.backCard?.transform = self.backTransform
            }
            if backCard?.profile != next {
                syncBackCard(with: next)
            }
        } else {
            topCard?.removeFromSuperview()
            topCard = card
            addSubview(card)
            animateEntrance(card)
            syncBackCard(with: next)
        }
        configureAccessibility()
    }

    private func syncBackCard(with next: VibeProfile?) {
        guard backCard?.profile != next else { return }
        backCard?.removeFromSuperview()
        backCard = nil
        guard let next else { return }
        let card = makeCard(next)
        card.transform = backTransform
        card.alpha = 0
        if let topCard {
            insertSubview(card, belowSubview: topCard)
        } else {
            addSubview(card)
        }
        backCard = card
        UIView.animate(withDuration: 0.2) { card.alpha = 1 }
    }

    private func makeCard(_ profile: VibeProfile) -> VibeCardView {
        let card = VibeCardView(profile: profile)
        card.delegate = cardDelegate
        card.frame = bounds
        card.layoutIfNeeded()
        return card
    }

    private var backTransform: CGAffineTransform {
        CGAffineTransform(translationX: 0, y: VibeCardStackView.backOffset)
            .scaledBy(x: VibeCardStackView.backScale, y: VibeCardStackView.backScale)
    }

    private func animateEntrance(_ card: VibeCardView) {
        card.alpha = 0
        card.transform = reduceMotion ? .identity : CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            card.alpha = 1
            card.transform = .identity
        }
    }

    // MARK: - Programmatic actions (accessible controls, full profile)

    /// Plays the same animation as a completed gesture. Returns `false` if interaction is blocked.
    @discardableResult
    func perform(_ action: VibeAction) -> Bool {
        guard let card = topCard, !isTransitioning,
              delegate?.cardStackShouldBeginInteraction(self) ?? true else { return false }
        isTransitioning = true
        let nudge = direction(for: action)
        UIView.animate(withDuration: reduceMotion ? 0.1 : 0.18, delay: 0, options: .curveEaseOut) {
            card.updateDrag(action: action, progress: 1)
            if !self.reduceMotion {
                card.transform = CGAffineTransform(translationX: nudge.x * 40, y: nudge.y * 40)
                    .rotated(by: self.rotation(forTranslationX: nudge.x * 40))
            }
        } completion: { _ in
            self.commit(action, card: card, velocity: .zero)
        }
        return true
    }

    // MARK: - Gesture

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let card = topCard else { return }
        let translation = pan.translation(in: self)

        switch pan.state {
        case .began:
            dragAction = nil
            didCrossThreshold = false
            VibeHaptics.prepare()
            delegate?.cardStack(self, didBeginDragging: card.profile)

        case .changed:
            // While a diagonal is ambiguous, keep showing the last clear direction.
            if let resolved = resolveDirection(translation) {
                if resolved != dragAction {
                    didCrossThreshold = false
                }
                dragAction = resolved
            } else if hypot(translation.x, translation.y) < configuration.minimumDragDistance {
                dragAction = nil
            }
            let progress = dragAction.map { self.progress(for: $0, translation: translation) } ?? 0
            if progress >= 1 && !didCrossThreshold {
                didCrossThreshold = true
                VibeHaptics.threshold()
            } else if progress < 0.85 {
                didCrossThreshold = false
            }
            card.transform = dragTransform(translation: translation, action: dragAction, progress: progress)
            card.updateDrag(action: dragAction, progress: progress)
            let overall = min(max(abs(translation.x) / bounds.width, abs(translation.y) / bounds.height) / configuration.commitFraction, 1)
            backCard?.transform = interpolatedBackTransform(overall)

        case .ended, .cancelled, .failed:
            let velocity = pan.velocity(in: self)
            if pan.state == .ended, let action = releaseAction(translation: translation, velocity: velocity) {
                commit(action, card: card, velocity: velocity)
            } else {
                cancelDrag(card)
            }

        default:
            break
        }
    }

    private func resolveDirection(_ vector: CGPoint) -> VibeAction? {
        let ax = abs(vector.x)
        let ay = abs(vector.y)
        guard max(ax, ay) >= configuration.minimumDragDistance else { return nil }
        if ax >= ay * configuration.dominanceRatio {
            return vector.x > 0 ? .interested : .notMyVibe
        }
        if ay >= ax * configuration.dominanceRatio {
            return vector.y < 0 ? .superVibe : .nope
        }
        return nil
    }

    private func releaseAction(translation: CGPoint, velocity: CGPoint) -> VibeAction? {
        guard let action = resolveDirection(translation) else { return nil }
        let progress = progress(for: action, translation: translation)
        let unit = direction(for: action)
        let speed = velocity.x * unit.x + velocity.y * unit.y
        // A strong fling back towards the centre cancels even past the threshold.
        if speed < -configuration.commitVelocity { return nil }
        if progress >= 1 { return action }
        if speed >= configuration.commitVelocity && progress >= configuration.minimumProgressForVelocity { return action }
        return nil
    }

    private func progress(for action: VibeAction, translation: CGPoint) -> CGFloat {
        switch action {
        case .interested, .notMyVibe:
            return abs(translation.x) / max(bounds.width * configuration.commitFraction, 1)
        case .superVibe, .nope:
            return abs(translation.y) / max(bounds.height * configuration.commitFraction, 1)
        }
    }

    private func direction(for action: VibeAction) -> CGPoint {
        switch action {
        case .interested: return CGPoint(x: 1, y: 0)
        case .notMyVibe: return CGPoint(x: -1, y: 0)
        case .superVibe: return CGPoint(x: 0, y: -1)
        case .nope: return CGPoint(x: 0, y: 1)
        }
    }

    private func rotation(forTranslationX x: CGFloat) -> CGFloat {
        reduceMotion ? 0 : (x / max(bounds.width, 1)) * 0.22
    }

    private func dragTransform(translation: CGPoint, action: VibeAction?, progress: CGFloat) -> CGAffineTransform {
        var transform = CGAffineTransform(translationX: translation.x, y: translation.y)
            .rotated(by: rotation(forTranslationX: translation.x))
        if action == .superVibe && !reduceMotion {
            let scale = 1 + 0.03 * min(progress, 1)
            transform = transform.scaledBy(x: scale, y: scale)
        }
        return transform
    }

    private func interpolatedBackTransform(_ progress: CGFloat) -> CGAffineTransform {
        let scale = VibeCardStackView.backScale + (1 - VibeCardStackView.backScale) * progress
        return CGAffineTransform(translationX: 0, y: VibeCardStackView.backOffset * (1 - progress))
            .scaledBy(x: scale, y: scale)
    }

    private func offscreenTransform(for action: VibeAction, from transform: CGAffineTransform) -> CGAffineTransform {
        let unit = direction(for: action)
        let distance = max(bounds.width, bounds.height) * 1.5
        let x = transform.tx + unit.x * distance
        let y = transform.ty + unit.y * distance
        return CGAffineTransform(translationX: x, y: y).rotated(by: rotation(forTranslationX: x) * 0.6)
    }

    private func cancelDrag(_ card: VibeCardView) {
        dragAction = nil
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.3,
                       options: [.allowUserInteraction]) {
            card.transform = .identity
            card.updateDrag(action: nil, progress: 0)
            self.backCard?.transform = self.backTransform
        }
        delegate?.cardStack(self, didCancelDragging: card.profile)
    }

    private func commit(_ action: VibeAction, card: VibeCardView, velocity: CGPoint) {
        isTransitioning = true
        dragAction = nil
        card.updateDrag(action: action, progress: 1)
        card.isUserInteractionEnabled = false
        if action == .superVibe {
            VibeHaptics.superVibe()
            if !reduceMotion {
                emitSparkles(from: card.center)
            }
        }

        // Promote the preloaded card immediately so there is never a blank state.
        let promoted = backCard
        backCard = nil
        topCard = promoted
        configureAccessibility()

        let duration: TimeInterval = reduceMotion ? 0.2 : 0.32
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseIn]) {
            if self.reduceMotion {
                card.alpha = 0
            } else {
                card.transform = self.offscreenTransform(for: action, from: card.transform)
            }
        } completion: { _ in
            card.removeFromSuperview()
        }
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            promoted?.transform = .identity
        } completion: { _ in
            self.isTransitioning = false
        }
        if promoted == nil {
            isTransitioning = false
        }
        delegate?.cardStack(self, didCommit: action, for: card.profile)
    }

    // MARK: - Super Vibe particles

    private func emitSparkles(from point: CGPoint) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 80, height: 80)
        let cell = CAEmitterCell()
        cell.contents = UIImage(systemName: "sparkle")?.withTintColor(VibeAction.superVibe.tintColor, renderingMode: .alwaysOriginal).cgImage
        cell.birthRate = 60
        cell.lifetime = 0.9
        cell.velocity = 160
        cell.velocityRange = 60
        cell.emissionRange = .pi * 2
        cell.scale = 0.5
        cell.scaleRange = 0.25
        cell.alphaSpeed = -1.2
        emitter.emitterCells = [cell]
        layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { emitter.removeFromSuperlayer() }
    }

    // MARK: - Accessibility

    private func configureAccessibility() {
        guard let card = topCard else { return }
        var actions = VibeAction.allCases.map { action in
            UIAccessibilityCustomAction(name: action.displayName) { [weak self] _ in
                self?.perform(action) ?? false
            }
        }
        actions.append(UIAccessibilityCustomAction(name: "View full profile") { [weak self] _ in
            self?.onAccessibilityViewProfile?()
            return true
        })
        card.stackAccessibilityActions = actions
        accessibilityElements = [card]
    }
}

extension VibeCardStackView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UIPanGestureRecognizer else { return true }
        return topCard != nil && !isTransitioning && (delegate?.cardStackShouldBeginInteraction(self) ?? true)
    }
}
