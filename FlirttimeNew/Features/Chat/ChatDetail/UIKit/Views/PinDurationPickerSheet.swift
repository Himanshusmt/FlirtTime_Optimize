import UIKit

/// Bottom sheet to choose how long a newly pinned message lasts (24h / 7d / 30d).
final class PinDurationPickerSheet: UIView {

    enum Duration: String {
        case hours24 = "24h"
        case days7 = "7d"
        case days30 = "30d"

        var title: String {
            switch self {
            case .hours24: return "24 hours"
            case .days7: return "7 days"
            case .days30: return "30 days"
            }
        }
    }

    var onDurationSelected: ((Duration) -> Void)?
    var onDismiss: (() -> Void)?

    private let durations: [Duration] = [.hours24, .days7, .days30]
    private var sheetTopConstraint: NSLayoutConstraint?
    private var panGesture: UIPanGestureRecognizer?
    private var panStartY: CGFloat = 0
    private var isDraggingSheet = false

    private let dimmingView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.alpha = 0
        return v
    }()

    private let containerView: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 24
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.1
        v.layer.shadowRadius = 10
        v.layer.shadowOffset = CGSize(width: 0, height: -5)
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let handleView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.gray.withAlphaComponent(0.4)
        v.layer.cornerRadius = 3
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Choose how long your new pin lasts"
        l.font = UIFont.chat(.semibold, size: 17)
        l.textColor = .label
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var closeButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        b.tintColor = .secondaryLabel
        b.backgroundColor = UIColor.systemGray5
        b.layer.cornerRadius = 15
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return b
    }()

    private let hintContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemGray6
        v.layer.cornerRadius = 14
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.text = "You can unpin at any time."
        l.font = UIFont.chat(.regular, size: 14)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let optionsContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemGray6
        v.layer.cornerRadius = 16
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let optionsStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 0
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addSubview(dimmingView)
        addSubview(containerView)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        sheetTopConstraint = containerView.topAnchor.constraint(equalTo: topAnchor)
        sheetTopConstraint?.isActive = true

        containerView.addSubview(handleView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(closeButton)
        containerView.addSubview(hintContainer)
        hintContainer.addSubview(hintLabel)
        containerView.addSubview(optionsContainer)
        optionsContainer.addSubview(optionsStack)

        NSLayoutConstraint.activate([
            handleView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            handleView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 40),
            handleView.heightAnchor.constraint(equalToConstant: 5),

            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            titleLabel.topAnchor.constraint(equalTo: handleView.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 48),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -48),

            hintContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            hintContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            hintContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            hintLabel.topAnchor.constraint(equalTo: hintContainer.topAnchor, constant: 10),
            hintLabel.bottomAnchor.constraint(equalTo: hintContainer.bottomAnchor, constant: -10),
            hintLabel.leadingAnchor.constraint(equalTo: hintContainer.leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: hintContainer.trailingAnchor, constant: -12),

            optionsContainer.topAnchor.constraint(equalTo: hintContainer.bottomAnchor, constant: 14),
            optionsContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            optionsContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            optionsContainer.bottomAnchor.constraint(
                equalTo: containerView.safeAreaLayoutGuide.bottomAnchor,
                constant: -16
            ),

            optionsStack.topAnchor.constraint(equalTo: optionsContainer.topAnchor),
            optionsStack.leadingAnchor.constraint(equalTo: optionsContainer.leadingAnchor),
            optionsStack.trailingAnchor.constraint(equalTo: optionsContainer.trailingAnchor),
            optionsStack.bottomAnchor.constraint(equalTo: optionsContainer.bottomAnchor),
        ])

        for (index, duration) in durations.enumerated() {
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = UIColor.separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
                optionsStack.addArrangedSubview(divider)
            }
            optionsStack.addArrangedSubview(makeOptionButton(for: duration))
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        dimmingView.addGestureRecognizer(tap)
    }

    private func makeOptionButton(for duration: Duration) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = duration.title
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.chat(.regular, size: 16)
            return outgoing
        }
        let b = UIButton(configuration: config)
        b.contentHorizontalAlignment = .leading
        b.tag = durations.firstIndex(of: duration) ?? 0
        b.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
        return b
    }

    private func restingTopConstant() -> CGFloat {
        // Content-sized sheet; keep a comfortable height for title + options.
        max(bounds.height - 340, bounds.height * 0.55)
    }

    func present(in parent: UIView) {
        parent.addSubview(self)
        frame = parent.bounds

        let screenHeight = parent.bounds.height
        sheetTopConstraint?.constant = screenHeight
        layoutIfNeeded()

        UIView.animate(withDuration: 0.2) {
            self.dimmingView.alpha = 0.4
        }
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            self.sheetTopConstraint?.constant = self.restingTopConstant()
            parent.layoutIfNeeded()
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        containerView.addGestureRecognizer(pan)
        panGesture = pan
    }

    func dismiss(completion: (() -> Void)? = nil) {
        isDraggingSheet = true
        let screenHeight = bounds.height
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: .curveEaseOut,
            animations: {
                self.dimmingView.alpha = 0
                self.sheetTopConstraint?.constant = screenHeight
                self.superview?.layoutIfNeeded()
            }
        ) { _ in
            self.isDraggingSheet = false
            self.removeFromSuperview()
            self.onDismiss?()
            completion?()
        }
    }

    @objc private func closeTapped() {
        dismiss()
    }

    @objc private func optionTapped(_ sender: UIButton) {
        let index = sender.tag
        guard durations.indices.contains(index) else { return }
        let selected = durations[index]
        dismiss { [weak self] in
            self?.onDurationSelected?(selected)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        let resting = restingTopConstant()

        switch gesture.state {
        case .began:
            isDraggingSheet = true
            panStartY = sheetTopConstraint?.constant ?? resting
        case .changed:
            let newTop = max(resting, panStartY + translation.y)
            sheetTopConstraint?.constant = newTop
            let progress = min(1, max(0, (newTop - resting) / (bounds.height - resting)))
            dimmingView.alpha = 0.4 * (1 - progress)
        case .ended, .cancelled:
            isDraggingSheet = false
            let shouldDismiss = (sheetTopConstraint?.constant ?? resting) - resting > 120
                || velocity.y > 900
            if shouldDismiss {
                dismiss()
            } else {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.85,
                    initialSpringVelocity: 0,
                    options: .curveEaseOut
                ) {
                    self.sheetTopConstraint?.constant = resting
                    self.dimmingView.alpha = 0.4
                    self.layoutIfNeeded()
                }
            }
        default:
            break
        }
    }
}
