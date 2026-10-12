//
//  StoryboardDesignableViews.swift
//  FlirttimeNew
//
//  Small views used by OtherUserProfile.storyboard. Corner radius, border and shadow
//  come from the shared `UIView` inspectables in IBInspectable.swift.
//

import UIKit

/// Two-color gradient, top to bottom (or left to right when `isHorizontal`).
class GradientBackgroundView: UIView {
    @IBInspectable var startColor: UIColor = .clear { didSet { updateGradient() } }
    @IBInspectable var endColor: UIColor = .clear { didSet { updateGradient() } }
    @IBInspectable var isHorizontal: Bool = false { didSet { updateGradient() } }

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private func updateGradient() {
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [startColor.cgColor, endColor.cgColor]
        gradient.startPoint = isHorizontal ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 0.5, y: 0)
        gradient.endPoint = isHorizontal ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0.5, y: 1)
    }
}

/// Shrinks slightly while pressed.
class BounceButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            }
        }
    }
}

/// Grows to fit all its rows, so it can sit inside a scroll view's stack.
final class AutoHeightTableView: UITableView {
    override var contentSize: CGSize { didSet { invalidateIntrinsicContentSize() } }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height) }
}

/// Grows to fit all its items, so it can sit inside a scroll view's stack.
final class AutoHeightCollectionView: UICollectionView {
    override var contentSize: CGSize { didSet { invalidateIntrinsicContentSize() } }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height) }
}
