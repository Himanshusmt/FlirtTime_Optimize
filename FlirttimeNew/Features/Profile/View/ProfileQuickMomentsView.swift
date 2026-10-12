//
//  ProfileQuickMomentsView.swift
//  FlirttimeNew
//
//  Story-style row on the Profile tab: an "Add" bubble followed by the user's own Quick Moments.
//

import UIKit

final class ProfileQuickMomentsView: UIView {

    var onAdd: (() -> Void)?
    var onSelect: ((Int) -> Void)?

    static let preferredHeight: CGFloat = 102
    private static let bubbleSize: CGFloat = 70

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)
        scrollView.pinEdges(to: self)

        stack.spacing = 14
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(moments: [VibeMoment], avatarPath: String?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(addItem(avatarPath: avatarPath))
        for (index, moment) in moments.enumerated() {
            stack.addArrangedSubview(momentItem(moment, index: index, total: moments.count))
        }
    }

    // MARK: - Items

    private func addItem(avatarPath: String?) -> UIView {
        let size = Self.bubbleSize
        let circle = UIView()
        circle.backgroundColor = AppColor.Lavenderblush
        circle.layer.cornerRadius = size / 2
        circle.layer.borderWidth = 1.5
        circle.layer.borderColor = AppColor.Punch.withAlphaComponent(0.35).cgColor

        let avatar = UIImageView()
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = (size - 12) / 2
        avatar.alpha = 0.55
        avatar.loadImage(path: avatarPath, placeholder: UIImage(named: "ProfileBlur"))
        circle.addSubview(avatar)
        avatar.pinEdges(to: circle, insets: UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6))

        let plus = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
        plus.tintColor = .white
        plus.contentMode = .center
        plus.backgroundColor = AppColor.Punch
        plus.layer.cornerRadius = 12
        plus.layer.borderWidth = 2
        plus.layer.borderColor = UIColor.white.cgColor
        plus.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(plus)
        NSLayoutConstraint.activate([
            plus.widthAnchor.constraint(equalToConstant: 24),
            plus.heightAnchor.constraint(equalToConstant: 24),
            plus.trailingAnchor.constraint(equalTo: circle.trailingAnchor, constant: 2),
            plus.bottomAnchor.constraint(equalTo: circle.bottomAnchor, constant: 2)
        ])

        let item = makeItem(circle: circle, title: "Add new", titleColor: AppColor.Punch)
        item.accessibilityLabel = "Add a moment"
        item.addAction(UIAction { [weak self] _ in self?.onAdd?() }, for: .touchUpInside)
        return item
    }

    private func momentItem(_ moment: VibeMoment, index: Int, total: Int) -> UIView {
        let size = Self.bubbleSize
        let ring = VibeGradientView(colors: VibeTheme.brandGradient)
        ring.layer.cornerRadius = size / 2
        ring.clipsToBounds = true

        let gap = UIView()
        gap.backgroundColor = AppColor.AppWhite
        gap.layer.cornerRadius = (size - 6) / 2
        gap.clipsToBounds = true
        ring.addSubview(gap)
        gap.pinEdges(to: ring, insets: UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3))

        let content: UIView
        if moment.isText {
            let background = VibeGradientView(colors: VibeTheme.storyBackground(moment.textBackground))
            let text = UILabel.vibeLabel(.bold, 10, style: .caption2, color: .white, lines: 3)
            text.text = moment.caption
            text.textAlignment = .center
            background.addSubview(text)
            text.pinEdges(to: background, insets: UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6))
            content = background
        } else {
            let image = UIImageView()
            image.contentMode = .scaleAspectFill
            image.backgroundColor = AppColor.AthensGray
            image.loadImage(path: moment.imagePath, placeholder: UIImage(named: "ProfileBlur"))
            content = image
        }
        content.clipsToBounds = true
        content.layer.cornerRadius = (size - 12) / 2
        gap.addSubview(content)
        content.pinEdges(to: gap, insets: UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3))

        let bubble = UIView()
        bubble.addSubview(ring)
        ring.pinEdges(to: bubble)
        let activity = (moment.reactionsCount ?? 0) + (moment.repliesCount ?? 0)
        if activity > 0 {
            let badge = UILabel.vibeLabel(.bold, 11, style: .caption2, color: .white)
            badge.text = "\(moment.topReactions.first ?? "💬") \(activity.vibeCountText)"
            badge.textAlignment = .center
            badge.backgroundColor = AppColor.Punch
            badge.layer.cornerRadius = 10
            badge.layer.borderWidth = 2
            badge.layer.borderColor = UIColor.white.cgColor
            badge.clipsToBounds = true
            badge.translatesAutoresizingMaskIntoConstraints = false
            bubble.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.heightAnchor.constraint(equalToConstant: 20),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
                badge.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
                badge.centerYAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -2)
            ])
        }

        let time = moment.postedAt.map { VibeDate.timeAgo(from: VibeDate.string(from: $0)) }
        let item = makeItem(circle: bubble, title: time ?? " ", titleColor: AppColor.DoveGray)
        item.accessibilityLabel = "Your quick moment \(index + 1) of \(total)"
            + (moment.postedAgoText.map { ", \($0)" } ?? "")
            + (moment.caption.map { ". \($0)" } ?? "")
            + (activity > 0 ? ". \(moment.reactionsCount ?? 0) reactions, \(moment.repliesCount ?? 0) replies" : "")
        item.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
        return item
    }

    private func makeItem(circle: UIView, title: String, titleColor: UIColor) -> UIButton {
        let label = UILabel.vibeLabel(.medium, 12, style: .caption1, color: titleColor)
        label.text = title
        label.textAlignment = .center

        let column = UIStackView(arrangedSubviews: [circle, label])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 10
        column.isUserInteractionEnabled = false

        let button = QuickMomentButton(type: .custom)
        button.addSubview(column)
        column.pinEdges(to: button)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: Self.bubbleSize),
            circle.heightAnchor.constraint(equalToConstant: Self.bubbleSize),
            button.widthAnchor.constraint(equalToConstant: Self.bubbleSize + 4)
        ])
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        return button
    }
}

private final class QuickMomentButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }
}
