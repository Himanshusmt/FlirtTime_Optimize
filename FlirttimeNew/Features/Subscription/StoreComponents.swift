//
//  StoreComponents.swift
//  FlirttimeNew
//
//  Pieces shared by the Premium and Coin Shop screens.
//

import UIKit

enum StoreUI {

    static func circleButton(symbol: String, label: String, onDark: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = onDark ? UIColor.white.withAlphaComponent(0.18) : AppColor.AppWhite
        config.baseForegroundColor = onDark ? .white : AppColor.MineShaft
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        let button = UIButton(configuration: config)
        if !onDark {
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.08
            button.layer.shadowRadius = 8
            button.layer.shadowOffset = CGSize(width: 0, height: 3)
        }
        button.accessibilityLabel = label
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        return button
    }

    static func linkButton(_ title: String, color: UIColor = AppColor.DoveGray, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = color
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: VibeFont.scaled(.medium, 13, style: .footnote),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]))
        let button = UIButton(configuration: config)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}

/// Small capsule tag such as "MOST POPULAR" or "+100 coins".
final class StoreBadgeView: UIView {

    private let label = UILabel.vibeLabel(.bold, 11, style: .caption2, color: .white)
    private var gradient: VibeGradientView?

    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }

    init(text: String, colors: [UIColor] = VibeTheme.brandGradient, textColor: UIColor = .white) {
        super.init(frame: .zero)
        if colors.count > 1 {
            let gradient = VibeGradientView(colors: colors, start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))
            addSubview(gradient)
            gradient.pinEdges(to: self)
            self.gradient = gradient
        } else {
            backgroundColor = colors.first
        }
        clipsToBounds = true
        label.text = text
        label.textColor = textColor
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
