//
//  ProfileQuickMomentsView.swift
//  FlirttimeNew
//
//  Story-style row on the Profile tab: an "Add" bubble followed by the user's own Quick Moments.
//  On another user's profile, bubbles use a WhatsApp-style status ring (red = unseen, gray = viewed).
//

import UIKit

final class ProfileQuickMomentsView: UIView {

    var onAdd: (() -> Void)?
    var onSelect: ((Int) -> Void)?
    /// Off when showing someone else's Quick Moments.
    @IBInspectable var showsAddButton: Bool = true

    static let preferredHeight: CGFloat = 102
    private static let bubbleSize: CGFloat = 70

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    /// When true, rings reflect the visitor's viewed / unseen state.
    private var showsViewedStatus = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
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

    /// - Parameter showsViewedStatus: Use WhatsApp-style red/gray rings for a visitor on someone else's profile.
    func configure(moments: [MomentsStory], avatarPath: String?, showsViewedStatus: Bool = false) {
        self.showsViewedStatus = showsViewedStatus
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if showsAddButton {
            stack.addArrangedSubview(addItem(avatarPath: avatarPath))
        } else if showsViewedStatus, !moments.isEmpty {
            // Leading avatar with the full multi-segment ring (same language as the Discover tray).
            stack.addArrangedSubview(statusAvatarItem(moments: moments, avatarPath: avatarPath))
        }
        for (index, moment) in moments.enumerated() {
            stack.addArrangedSubview(momentItem(moment, index: index, total: moments.count))
        }
    }

    // MARK: - Items

    private func addItem(avatarPath: String?) -> UIView {
        let bubble = QuickMomentAddBubbleView()
        bubble.configure(avatarPath: avatarPath)

        let item = QuickMomentButton(type: .custom)
        item.addSubview(bubble)
        bubble.pinEdges(to: item)
        item.accessibilityLabel = "Add a moment"
        item.accessibilityTraits = .button
        item.isAccessibilityElement = true
        item.addAction(UIAction { [weak self] _ in self?.onAdd?() }, for: .touchUpInside)
        return item
    }

    /// User avatar with one ring segment per Quick Moment (oldest → newest).
    private func statusAvatarItem(moments: [MomentsStory], avatarPath: String?) -> UIView {
        let size = Self.bubbleSize
        let bubble = UIView()

        let ring = QuickMomentStatusRingView()
        ring.lineWidth = 3
        // Moments are newest-first in the row; the ring draws oldest → newest like WhatsApp.
        ring.configure(segmentViewed: moments.reversed().map(\.hasViewed))
        ring.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(ring)

        let avatar = UIImageView()
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = (size - 12) / 2
        avatar.backgroundColor = AppColor.AthensGray
        avatar.loadImage(path: avatarPath, placeholder: UIImage(named: "ProfileBlur"))
        avatar.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(avatar)

        NSLayoutConstraint.activate([
            ring.topAnchor.constraint(equalTo: bubble.topAnchor),
            ring.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            ring.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            avatar.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            avatar.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: size - 12),
            avatar.heightAnchor.constraint(equalToConstant: size - 12)
        ])

        let unread = moments.filter { !$0.hasViewed }.count
        let item = makeItem(circle: bubble, title: unread > 0 ? "New" : "Viewed", titleColor: unread > 0 ? AppColor.Punch : AppColor.DoveGray)
        item.accessibilityLabel = unread > 0
            ? "Quick moments, \(unread) unseen of \(moments.count)"
            : "Quick moments, all \(moments.count) viewed"
        // Oldest unseen in newest-first order (viewer remaps to oldest-first playback).
        let startIndex = moments.lastIndex(where: { !$0.hasViewed }) ?? max(moments.count - 1, 0)
        item.addAction(UIAction { [weak self] _ in self?.onSelect?(startIndex) }, for: .touchUpInside)
        return item
    }

    private func momentItem(_ moment: MomentsStory, index: Int, total: Int) -> UIView {
        let size = Self.bubbleSize
        let bubble = UIView()

        let content: UIView
        if moment.isText {
            let background = MomentsGradientView(colors: MomentsTheme.storyBackground(moment.textBackground))
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
        content.layer.cornerRadius = (size - 14) / 2
        content.translatesAutoresizingMaskIntoConstraints = false

        if showsViewedStatus {
            // Per-moment ring: red if this visitor hasn't seen it, light gray if they have.
            let ring = QuickMomentStatusRingView()
            ring.lineWidth = 3
            ring.configure(segmentViewed: [moment.hasViewed])
            ring.translatesAutoresizingMaskIntoConstraints = false
            bubble.addSubview(ring)
            bubble.addSubview(content)
            NSLayoutConstraint.activate([
                ring.topAnchor.constraint(equalTo: bubble.topAnchor),
                ring.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
                ring.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
                ring.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
                content.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
                content.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
                content.widthAnchor.constraint(equalToConstant: size - 14),
                content.heightAnchor.constraint(equalToConstant: size - 14)
            ])
        } else {
            let ring = MomentsGradientView(colors: MomentsTheme.brandGradient)
            ring.layer.cornerRadius = size / 2
            ring.clipsToBounds = true
            bubble.addSubview(ring)
            ring.pinEdges(to: bubble)

            let gap = UIView()
            gap.backgroundColor = AppColor.AppWhite
            gap.layer.cornerRadius = (size - 6) / 2
            gap.clipsToBounds = true
            ring.addSubview(gap)
            gap.pinEdges(to: ring, insets: UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3))

            content.layer.cornerRadius = (size - 12) / 2
            gap.addSubview(content)
            content.pinEdges(to: gap, insets: UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3))
        }

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

        let time = moment.postedAt.map { MomentsDate.timeAgo(from: MomentsDate.string(from: $0)) }
        let titleColor = showsViewedStatus && !moment.hasViewed ? AppColor.Punch : AppColor.DoveGray
        let item = makeItem(circle: bubble, title: time ?? " ", titleColor: titleColor)
        var label = (showsAddButton ? "Your quick moment" : "Quick moment") + " \(index + 1) of \(total)"
        if showsViewedStatus {
            label += moment.hasViewed ? ", viewed" : ", new"
        }
        label += (moment.postedAgoText.map { ", \($0)" } ?? "")
        label += (moment.caption.map { ". \($0)" } ?? "")
        if activity > 0 {
            label += ". \(moment.reactionsCount ?? 0) reactions, \(moment.repliesCount ?? 0) replies"
        }
        item.accessibilityLabel = label
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
