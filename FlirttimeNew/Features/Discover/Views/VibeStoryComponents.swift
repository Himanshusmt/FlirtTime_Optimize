//
//  VibeStoryComponents.swift
//  FlirttimeNew
//
//  Visual building blocks for the Vibe Card, Vibe Details and connection screens.
//

import UIKit

// MARK: - Gradient

final class VibeGradientView: UIView {

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
}

extension UIView {
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
