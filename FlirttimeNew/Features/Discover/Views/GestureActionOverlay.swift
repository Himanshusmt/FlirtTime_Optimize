//
//  GestureActionOverlay.swift
//  FlirttimeNew
//
//  Indicator shown only while dragging; it swaps when the drag direction changes.
//

import UIKit

final class GestureActionOverlay: UIView {

    private let tintView = UIView()
    private let pillView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private(set) var action: VibeAction?

    /// Area of the card the pill is positioned in (the photo).
    var anchorRect: CGRect = .zero {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false

        addSubview(tintView)

        pillView.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        pillView.layer.cornerRadius = 14
        pillView.layer.borderWidth = 3
        addSubview(pillView)

        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        titleLabel.font = UIFont.fredoka(.bold, size: 22)
        let row = UIStackView(arrangedSubviews: [iconView, titleLabel])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: pillView.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: pillView.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -14)
        ])
        update(action: nil, progress: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(action: VibeAction?, progress: CGFloat) {
        if action != self.action {
            self.action = action
            if let action {
                iconView.image = UIImage(systemName: action.symbolName)
                iconView.tintColor = action.tintColor
                titleLabel.text = action.overlayTitle
                titleLabel.textColor = action.tintColor
                pillView.layer.borderColor = action.tintColor.cgColor
                tintView.backgroundColor = action.tintColor
            }
            setNeedsLayout()
            layoutIfNeeded()
        }
        let clamped = max(0, min(progress, 1))
        let visible = action == nil ? 0 : clamped
        pillView.alpha = visible
        tintView.alpha = visible * 0.14
        let scale = 0.8 + 0.2 * visible
        pillView.transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
    }

    private var rotation: CGFloat {
        switch action {
        case .interested: return -.pi / 14
        case .notMyVibe: return .pi / 14
        default: return 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tintView.frame = bounds
        let transform = pillView.transform
        pillView.transform = .identity
        let size = pillView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let area = anchorRect == .zero ? bounds : anchorRect
        let inset: CGFloat = 24
        let origin: CGPoint
        switch action {
        case .interested:
            origin = CGPoint(x: area.minX + inset, y: area.minY + inset + 20)
        case .notMyVibe:
            origin = CGPoint(x: area.maxX - inset - size.width, y: area.minY + inset + 20)
        case .superVibe:
            origin = CGPoint(x: area.midX - size.width / 2, y: area.maxY - inset - size.height)
        case .nope, .none:
            origin = CGPoint(x: area.midX - size.width / 2, y: area.minY + inset + 20)
        }
        pillView.frame = CGRect(origin: origin, size: size)
        pillView.transform = transform
    }
}
