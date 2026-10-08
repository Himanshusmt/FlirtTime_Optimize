//
//  OutlinedTextField.swift
//  FlirttimeNew
//
//  Lightweight stand-in for MaterialComponents' MDCOutlinedTextField
//  (MaterialComponents has no Swift Package Manager distribution).
//

import UIKit

enum OutlinedTextFieldState {
    case normal
    case editing
    case disabled
}

class OutlinedTextField: UITextField {

    let label = UILabel()

    @objc var placeholderColor: UIColor?

    var containerRadius: CGFloat = 4 {
        didSet { setNeedsLayout() }
    }

    var leadingView: UIView? {
        get { leftView }
        set { leftView = newValue; setNeedsLayout() }
    }

    var trailingView: UIView? {
        get { rightView }
        set { rightView = newValue; setNeedsLayout() }
    }

    var leadingViewMode: UITextField.ViewMode {
        get { leftViewMode }
        set { leftViewMode = newValue }
    }

    var trailingViewMode: UITextField.ViewMode {
        get { rightViewMode }
        set { rightViewMode = newValue }
    }

    private let outlineLayer = CAShapeLayer()
    private let horizontalPadding: CGFloat = 16
    private let accessorySpacing: CGFloat = 8
    private let floatingScale: CGFloat = 0.75

    private var normalLabelColors: [OutlinedTextFieldState: UIColor] = [:]
    private var floatingLabelColors: [OutlinedTextFieldState: UIColor] = [:]
    private var outlineColors: [OutlinedTextFieldState: UIColor] = [:]
    private var textColors: [OutlinedTextFieldState: UIColor] = [:]

    private var currentState: OutlinedTextFieldState {
        if !isEnabled { return .disabled }
        return isEditing ? .editing : .normal
    }

    private var shouldFloatLabel: Bool {
        return isEditing || !(text ?? "").isEmpty
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        borderStyle = .none
        clipsToBounds = false
        outlineLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(outlineLayer)

        label.font = font
        label.textColor = AppColor.Bombay
        label.isUserInteractionEnabled = false
        addSubview(label)

        addTarget(self, action: #selector(refreshAppearance), for: [.editingDidBegin, .editingDidEnd, .editingChanged])
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        if label.text == nil || label.text?.isEmpty == true {
            label.text = placeholder
        }
        placeholder = nil
        label.font = font
    }

    override var text: String? {
        didSet { refreshAppearance() }
    }

    override var font: UIFont? {
        didSet { label.font = font }
    }

    // MARK: - MDC-compatible color API

    func setNormalLabelColor(_ color: UIColor, for state: OutlinedTextFieldState) {
        normalLabelColors[state] = color
        refreshAppearance()
    }

    func setFloatingLabelColor(_ color: UIColor, for state: OutlinedTextFieldState) {
        floatingLabelColors[state] = color
        refreshAppearance()
    }

    func setOutlineColor(_ color: UIColor, for state: OutlinedTextFieldState) {
        outlineColors[state] = color
        refreshAppearance()
    }

    func setTextColor(_ color: UIColor, for state: OutlinedTextFieldState) {
        textColors[state] = color
        refreshAppearance()
    }

    // MARK: - Layout

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: textInsets)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: textInsets)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: textInsets)
    }

    override func leftViewRect(forBounds bounds: CGRect) -> CGRect {
        let size = leftView?.bounds.size ?? .zero
        return CGRect(x: horizontalPadding, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func rightViewRect(forBounds bounds: CGRect) -> CGRect {
        let size = rightView?.bounds.size ?? .zero
        return CGRect(x: bounds.width - horizontalPadding / 2 - size.width, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    private var textInsets: UIEdgeInsets {
        let rightInset = rightView == nil ? horizontalPadding : horizontalPadding / 2 + (rightView?.bounds.width ?? 0) + accessorySpacing
        let leftInset = leftView == nil ? horizontalPadding : horizontalPadding + (leftView?.bounds.width ?? 0) + accessorySpacing
        return UIEdgeInsets(top: 0, left: leftInset, bottom: 0, right: rightInset)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLabel()
        drawOutline()
    }

    private func layoutLabel() {
        label.transform = .identity
        label.sizeToFit()
        let labelSize = label.bounds.size
        if shouldFloatLabel {
            label.transform = CGAffineTransform(scaleX: floatingScale, y: floatingScale)
            let scaledWidth = labelSize.width * floatingScale
            label.center = CGPoint(x: horizontalPadding + scaledWidth / 2, y: 0)
        } else {
            label.center = CGPoint(x: textInsets.left + labelSize.width / 2, y: bounds.midY)
        }
    }

    private func drawOutline() {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: containerRadius)
        outlineLayer.path = path.cgPath
        outlineLayer.frame = bounds

        if shouldFloatLabel, !(label.text ?? "").isEmpty {
            let gapStart = horizontalPadding - 4
            let gapWidth = label.frame.width + 8
            let mask = CAShapeLayer()
            let maskPath = UIBezierPath(rect: bounds.insetBy(dx: -2, dy: -2))
            maskPath.append(UIBezierPath(rect: CGRect(x: gapStart, y: -2, width: gapWidth, height: 4)).reversing())
            mask.path = maskPath.cgPath
            outlineLayer.mask = mask
        } else {
            outlineLayer.mask = nil
        }
    }

    @objc private func refreshAppearance() {
        let state = currentState
        let outline = outlineColors[state] ?? outlineColors[.normal] ?? AppColor.Iron
        outlineLayer.strokeColor = outline.cgColor
        outlineLayer.lineWidth = state == .editing ? 2 : 1

        if let color = textColors[state] ?? textColors[.normal] {
            textColor = color
        }

        let labelColors = shouldFloatLabel ? floatingLabelColors : normalLabelColors
        label.textColor = labelColors[state] ?? labelColors[.normal] ?? AppColor.Bombay

        UIView.animate(withDuration: 0.15) {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }
}
