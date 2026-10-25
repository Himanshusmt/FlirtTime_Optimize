//
//  GestureActionOverlay.swift
//  FlirttimeNew
//
//  Old Flirttime swipe stamps shown only while dragging.
//  Like / Nope sit at the top corners; Super Like sits at the top centre.
//

import UIKit

final class GestureActionOverlay: UIView {

    private static let likeSize = CGSize(width: 140, height: 154)
    private static let nopeSize = CGSize(width: 140, height: 149)
    private static let superLikeSize = CGSize(width: 160, height: 129)

    private let tintView = UIView()
    private let stickerView = UIImageView()
    private(set) var action: MomentsAction?

    /// Area of the card the sticker is positioned in (the photo).
    var anchorRect: CGRect = .zero {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false

        addSubview(tintView)

        stickerView.contentMode = .scaleAspectFit
        stickerView.clipsToBounds = false
        stickerView.layer.shadowColor = UIColor.black.cgColor
        stickerView.layer.shadowOpacity = 0.28
        stickerView.layer.shadowRadius = 8
        stickerView.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(stickerView)

        update(action: nil, progress: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(action: MomentsAction?, progress: CGFloat) {
        if action != self.action {
            self.action = action
            stickerView.image = action.flatMap { UIImage(named: $0.stickerImageName) }?
                .withRenderingMode(.alwaysOriginal)
            tintView.backgroundColor = action?.tintColor
            setNeedsLayout()
            layoutIfNeeded()
        }
        let clamped = max(0, min(progress, 1))
        let visible = action == nil ? 0 : clamped
        stickerView.alpha = visible
        tintView.alpha = visible * 0.14
        let scale = 0.55 + 0.45 * visible
        stickerView.transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
    }

    private var rotation: CGFloat {
        switch action {
        case .interested: return .pi / 10
        case .notMyVibe: return -.pi / 10
        case .superVibe: return -.pi / 20
        case .nope: return .pi / 20
        case .none: return 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tintView.frame = bounds

        let transform = stickerView.transform
        stickerView.transform = .identity

        let size: CGSize
        switch action {
        case .superVibe: size = Self.superLikeSize
        case .notMyVibe, .nope: size = Self.nopeSize
        case .interested, .none: size = Self.likeSize
        }
        stickerView.bounds = CGRect(origin: .zero, size: size)

        let area = anchorRect == .zero ? bounds : anchorRect
        let inset: CGFloat = 20
        let top = area.minY + 80 + size.height / 2
        switch action {
        case .interested:
            stickerView.center = CGPoint(x: area.minX + inset + size.width / 2, y: top)
        case .notMyVibe:
            stickerView.center = CGPoint(x: area.maxX - inset - size.width / 2, y: top)
        case .superVibe, .nope, .none:
            stickerView.center = CGPoint(x: area.midX, y: top)
        }
        stickerView.transform = transform
    }
}

private extension MomentsAction {
    /// Asset names from the original Flirttime card overlay.
    var stickerImageName: String {
        switch self {
        case .superVibe: return "super_like"
        case .interested: return "swipeLikeImage1"
        case .notMyVibe, .nope: return "swipeNope"
        }
    }
}
