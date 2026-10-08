import UIKit

final class ChatTypingIndicator: UIView {

    private let containerView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        v.layer.cornerRadius = 15
        v.layer.cornerCurve = .continuous
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let senderLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.semibold, size: 10)
        lbl.textColor = ChatTheme.primary
        lbl.isHidden = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let dot1 = makeDot()
    private let dot2 = makeDot()
    private let dot3 = makeDot()

    private let bounceHeight: CGFloat = 4

    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0

    // Dynamic constraints
    private var dotTopConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        displayLink?.invalidate()
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview == nil { stopAnimation() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        containerView.layer.cornerRadius = containerView.bounds.height / 2
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        backgroundColor = .clear

        addSubview(containerView)
        containerView.addSubview(senderLabel)
        containerView.addSubview(dot1)
        containerView.addSubview(dot2)
        containerView.addSubview(dot3)

        dotTopConstraint = dot1.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12)
        dotTopConstraint?.isActive = true

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            senderLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 6),
            senderLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            senderLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            dot1.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            dot1.widthAnchor.constraint(equalToConstant: 7),
            dot1.heightAnchor.constraint(equalToConstant: 7),

            dot2.leadingAnchor.constraint(equalTo: dot1.trailingAnchor, constant: 4),
            dot2.centerYAnchor.constraint(equalTo: dot1.centerYAnchor),
            dot2.widthAnchor.constraint(equalToConstant: 7),
            dot2.heightAnchor.constraint(equalToConstant: 7),

            dot3.leadingAnchor.constraint(equalTo: dot2.trailingAnchor, constant: 4),
            dot3.centerYAnchor.constraint(equalTo: dot1.centerYAnchor),
            dot3.widthAnchor.constraint(equalToConstant: 7),
            dot3.heightAnchor.constraint(equalToConstant: 7),

            dot3.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -12),
            dot1.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
        ])
        enforceRTLIfNeeded()
    }

    func show(senderName: String?) {
        senderLabel.isHidden = true
        dotTopConstraint?.isActive = false
        dotTopConstraint = dot1.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12)
        dotTopConstraint?.isActive = true

        guard isHidden else { return }
        alpha = 0
        isHidden = false
        startAnimation()
        UIView.animate(withDuration: 0.25) {
            self.alpha = 1
        }
    }

    func hide() {
        guard !isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }, completion: { _ in
            self.isHidden = true
            self.stopAnimation()
        })
    }

    // MARK: - Animation

    private func startAnimation() {
        guard displayLink == nil else { return }
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        for dot in [dot1, dot2, dot3] {
            dot.transform = .identity
            dot.alpha = 1
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - startTime
        let dots = [dot1, dot2, dot3]

        for (i, dot) in dots.enumerated() {
            let stagger = Double(i) * 0.2
            let phase = elapsed * 2.0 * Double.pi - stagger * 2.0 * Double.pi
            let wave = max(0, sin(phase))

            let scale = CGFloat(0.75 + 0.35 * wave)
            let yOffset = CGFloat(-bounceHeight) * wave

            dot.transform = CGAffineTransform(translationX: 0, y: yOffset)
                .scaledBy(x: scale, y: scale)

            dot.alpha = CGFloat(0.45 + 0.55 * wave)
        }
    }

    private static func makeDot() -> UIView {
        let v = UIView()
        v.backgroundColor = ChatTheme.textSecondary
        v.layer.cornerRadius = 3.5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }
}
