//
//  VibeRangeSlider.swift
//  FlirttimeNew
//
//  Two-thumb integer range slider. Sends `.valueChanged` while dragging.
//

import UIKit

final class VibeRangeSlider: UIControl {

    let range: ClosedRange<Int>
    var minimumGap = 1
    /// Spoken value for each thumb.
    var accessibilityValueText: (Int) -> String = { "\($0)" }

    private(set) var lower: Int
    private(set) var upper: Int

    fileprivate enum Thumb { case lower, upper }

    private let thumbSize: CGFloat = 28
    private let track = UIView()
    private let fill = UIView()
    private let lowerThumb = UIView()
    private let upperThumb = UIView()
    private var activeThumb: Thumb?
    private let haptics = UISelectionFeedbackGenerator()
    private lazy var lowerElement = ThumbElement(slider: self, thumb: .lower)
    private lazy var upperElement = ThumbElement(slider: self, thumb: .upper)

    init(range: ClosedRange<Int>) {
        self.range = range
        lower = range.lowerBound
        upper = range.upperBound
        super.init(frame: .zero)

        track.backgroundColor = AppColor.Punch.withAlphaComponent(0.14)
        track.layer.cornerRadius = 3
        fill.backgroundColor = AppColor.Punch
        fill.layer.cornerRadius = 3
        [track, fill, lowerThumb, upperThumb].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        for thumb in [lowerThumb, upperThumb] {
            thumb.backgroundColor = .white
            thumb.layer.cornerRadius = thumbSize / 2
            thumb.layer.borderWidth = 3
            thumb.layer.borderColor = AppColor.Punch.cgColor
            thumb.layer.shadowColor = AppColor.Punch.cgColor
            thumb.layer.shadowOpacity = 0.3
            thumb.layer.shadowRadius = 6
            thumb.layer.shadowOffset = CGSize(width: 0, height: 3)
        }
        accessibilityElements = [lowerElement, upperElement]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 40) }

    func setValues(lower: Int, upper: Int) {
        self.lower = min(max(lower, range.lowerBound), range.upperBound)
        self.upper = min(max(upper, self.lower), range.upperBound)
        setNeedsLayout()
    }

    // MARK: - Layout

    private var usableWidth: CGFloat { max(1, bounds.width - thumbSize) }

    private func x(for value: Int) -> CGFloat {
        let span = CGFloat(range.upperBound - range.lowerBound)
        return thumbSize / 2 + usableWidth * CGFloat(value - range.lowerBound) / max(1, span)
    }

    private func value(for x: CGFloat) -> Int {
        let fraction = min(max((x - thumbSize / 2) / usableWidth, 0), 1)
        return range.lowerBound + Int((fraction * CGFloat(range.upperBound - range.lowerBound)).rounded())
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let midY = bounds.midY
        track.frame = CGRect(x: thumbSize / 2, y: midY - 3, width: usableWidth, height: 6)
        let lowX = x(for: lower), highX = x(for: upper)
        fill.frame = CGRect(x: lowX, y: midY - 3, width: highX - lowX, height: 6)
        lowerThumb.bounds.size = CGSize(width: thumbSize, height: thumbSize)
        upperThumb.bounds.size = CGSize(width: thumbSize, height: thumbSize)
        lowerThumb.center = CGPoint(x: lowX, y: midY)
        upperThumb.center = CGPoint(x: highX, y: midY)
        lowerElement.accessibilityFrameInContainerSpace = lowerThumb.frame.insetBy(dx: -8, dy: -8)
        upperElement.accessibilityFrameInContainerSpace = upperThumb.frame.insetBy(dx: -8, dy: -8)
    }

    // MARK: - Tracking

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let x = touch.location(in: self).x
        let lowDistance = abs(x - lowerThumb.center.x), highDistance = abs(x - upperThumb.center.x)
        if abs(lowDistance - highDistance) < 1 {
            activeThumb = x > upperThumb.center.x ? .upper : .lower
        } else {
            activeThumb = lowDistance < highDistance ? .lower : .upper
        }
        haptics.prepare()
        setThumb(activeThumb, highlighted: true)
        move(to: x)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        move(to: touch.location(in: self).x)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        setThumb(activeThumb, highlighted: false)
        activeThumb = nil
    }

    override func cancelTracking(with event: UIEvent?) {
        setThumb(activeThumb, highlighted: false)
        activeThumb = nil
    }

    private func move(to x: CGFloat) {
        guard let activeThumb else { return }
        set(activeThumb, to: value(for: x))
    }

    fileprivate func step(_ thumb: Thumb, by delta: Int) {
        set(thumb, to: (thumb == .lower ? lower : upper) + delta)
    }

    private func set(_ thumb: Thumb, to newValue: Int) {
        let old = (lower, upper)
        switch thumb {
        case .lower: lower = min(max(newValue, range.lowerBound), upper - minimumGap)
        case .upper: upper = max(min(newValue, range.upperBound), lower + minimumGap)
        }
        guard old != (lower, upper) else { return }
        haptics.selectionChanged()
        setNeedsLayout()
        layoutIfNeeded()
        sendActions(for: .valueChanged)
    }

    private func setThumb(_ thumb: Thumb?, highlighted: Bool) {
        guard let thumb else { return }
        let view = thumb == .lower ? lowerThumb : upperThumb
        UIView.animate(withDuration: 0.15) {
            view.transform = highlighted ? CGAffineTransform(scaleX: 1.15, y: 1.15) : .identity
        }
    }

    // MARK: - Accessibility

    private final class ThumbElement: UIAccessibilityElement {
        private weak var slider: VibeRangeSlider?
        private let thumb: Thumb

        init(slider: VibeRangeSlider, thumb: Thumb) {
            self.slider = slider
            self.thumb = thumb
            super.init(accessibilityContainer: slider)
            accessibilityTraits = .adjustable
        }

        override var accessibilityLabel: String? {
            get { thumb == .lower ? "Minimum" : "Maximum" }
            set {}
        }

        override var accessibilityValue: String? {
            get {
                guard let slider else { return nil }
                return slider.accessibilityValueText(thumb == .lower ? slider.lower : slider.upper)
            }
            set {}
        }

        override func accessibilityIncrement() { slider?.step(thumb, by: 1) }
        override func accessibilityDecrement() { slider?.step(thumb, by: -1) }
    }
}
