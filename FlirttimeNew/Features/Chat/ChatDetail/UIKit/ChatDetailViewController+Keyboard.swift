import UIKit

final class KeyboardDisplayLinkProxy: NSObject {
    weak var owner: ChatDetailViewController?

    init(owner: ChatDetailViewController) {
        self.owner = owner
    }

    @objc func tick() {
        owner?.syncInputBarToKeyboard()
    }
}

/// Zero-height accessory that rides the keyboard, including interactive pan-dismiss.
final class ChatKeyboardTrackingView: UIView {

    var onPositionChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth]
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onPositionChange?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onPositionChange?()
    }
}

// MARK: - Keyboard Handling

extension ChatDetailViewController {

    /// Home-indicator inset from the window — ignores the floating tab bar, which
    /// otherwise inflates `view.safeAreaInsets.bottom` and leaves a gap under the composer.
    func composerHomeInset() -> CGFloat {
        if let bottom = view.window?.safeAreaInsets.bottom, bottom > 0 {
            return bottom
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let bottom = windowScene.keyWindow?.safeAreaInsets.bottom, bottom > 0 {
                return bottom
            }
        }
        return view.safeAreaInsets.bottom
    }

    /// Bottom constraint is to `view.bottomAnchor`. Offset keeps the bar above the
    /// home indicator at rest, and above the keyboard while it is visible.
    func inputBarBottomConstant(keyboardOverlap: CGFloat = 0) -> CGFloat {
        -max(keyboardOverlap, composerHomeInset())
    }

    func keyboardAnimationDuration(_ notification: Notification) -> TimeInterval {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.15
        return min(max(duration, 0.08), 0.15)
    }

    func isInteractivelyDismissingKeyboard() -> Bool {
        let panState = collectionView.panGestureRecognizer.state
        return collectionView.isDragging
            || collectionView.isDecelerating
            || panState == .began
            || panState == .changed
            || panState == .ended
    }

    func keyboardOverlap(from notification: Notification) -> CGFloat {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return 0
        }
        let frameInView = view.convert(frameValue.cgRectValue, from: view.window)
        return max(0, view.bounds.height - frameInView.origin.y)
    }

    func pinInputBar(keyboardOverlap: CGFloat) {
        keyboardHeight = max(0, keyboardOverlap - composerHomeInset())
        inputContainerBottom?.constant = inputBarBottomConstant(keyboardOverlap: keyboardOverlap)
    }

    func startKeyboardTracking() {
        guard keyboardTrackingDisplayLink == nil else { return }
        let proxy = KeyboardDisplayLinkProxy(owner: self)
        let link = CADisplayLink(target: proxy, selector: #selector(KeyboardDisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        keyboardTrackingProxy = proxy
        keyboardTrackingDisplayLink = link
    }

    func stopKeyboardTracking() {
        keyboardTrackingDisplayLink?.invalidate()
        keyboardTrackingDisplayLink = nil
        keyboardTrackingProxy = nil
    }

    /// Follows the live keyboard frame. Clamped so the composer never slides off-screen.
    func syncInputBarToKeyboard() {
        guard !isApplyingKeyboardTracking else { return }
        guard keyboardTrackingView.window != nil else { return }

        let rectInView = keyboardTrackingView.convert(keyboardTrackingView.bounds, to: view)
        guard rectInView.minY.isFinite, rectInView.minY > 1 else { return }

        let keyboardTop = rectInView.minY
        let overlap: CGFloat
        if keyboardTop >= view.bounds.height - 0.5 {
            overlap = 0
        } else {
            overlap = max(0, view.bounds.height - keyboardTop)
        }

        let constant = inputBarBottomConstant(keyboardOverlap: overlap)
        guard abs((inputContainerBottom?.constant ?? 0) - constant) > 0.5 else { return }

        isApplyingKeyboardTracking = true
        keyboardHeight = max(0, overlap - composerHomeInset())
        inputContainerBottom?.constant = constant
        view.layoutIfNeeded()
        isApplyingKeyboardTracking = false
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        guard presentedViewController == nil else { return }

        guard let animation = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }

        let overlap = keyboardOverlap(from: notification)
        let duration = keyboardAnimationDuration(notification)

        let panel = attachmentPanel
        if panel != nil {
            attachmentPanel = nil
            inputBar.resetAttachmentButton()
            inputBar.showingAttachmentSheet = false
        }

        let currentInputHeight = inputContainer.frame.height
        let panelHeight = panel?.frame.height ?? 0

        startKeyboardTracking()
        let trackingLive = keyboardTrackingView.window != nil
        if !trackingLive {
            pinInputBar(keyboardOverlap: overlap)
        }

        updateContentInsets(
            animated: true,
            duration: duration,
            animationCurve: animation,
            overrideInputHeight: currentInputHeight - panelHeight,
            coAnimatedHideView: panel,
            bottomConstraintConstant: trackingLive ? nil : inputBarBottomConstant(keyboardOverlap: overlap)
        )
    }

    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard presentedViewController == nil else { return }
        startKeyboardTracking()
        syncInputBarToKeyboard()
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        let duration = keyboardAnimationDuration(notification)
        let animation = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt)
            ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)

        let rest = inputBarBottomConstant()

        // Always pin the input bar back to the bottom when the keyboard dismisses —
        // including when a call UI / sheet is presented. Skipping that left the bar
        // stuck at the old keyboard height after the call ended.
        if pendingAttachmentFromKeyboard, presentedViewController == nil {
            keyboardHeight = 0
            pendingAttachmentFromKeyboard = false
            presentAttachmentPanelCoordinated(duration: duration, animationCurve: animation)
            return
        }
        pendingAttachmentFromKeyboard = false

        if isInteractivelyDismissingKeyboard() {
            startKeyboardTracking()
            return
        }

        keyboardHeight = 0
        updateContentInsets(
            animated: true,
            duration: duration,
            animationCurve: animation,
            bottomConstraintConstant: rest
        )
    }

    @objc func keyboardDidHide(_ notification: Notification) {
        stopKeyboardTracking()

        guard !inputBar.textView.isFirstResponder else { return }
        if pendingAttachmentFromKeyboard { return }

        keyboardHeight = 0
        updateContentInsets(
            animated: false,
            bottomConstraintConstant: inputBarBottomConstant()
        )
    }

    /// Dismiss keyboard and reset input-bar offset (call interruption / background).
    func dismissKeyboardForInterruption() {
        inputBar.resignFirstResponderInput()
        resetKeyboardLayoutIfNeeded(animated: false)
    }

    /// If the keyboard is gone but the input bar is still lifted, snap it back down.
    func resetKeyboardLayoutIfNeeded(animated: Bool = true) {
        guard !inputBar.textView.isFirstResponder else { return }
        let rest = inputBarBottomConstant()
        let lifted = keyboardHeight != 0
            || abs((inputContainerBottom?.constant ?? rest) - rest) > 0.5
        guard lifted else { return }

        stopKeyboardTracking()
        keyboardHeight = 0
        updateContentInsets(
            animated: animated,
            duration: animated ? 0.12 : 0,
            bottomConstraintConstant: rest
        )
    }

    func updateContentInsets(
        animated: Bool = false,
        duration: TimeInterval = 0.25,
        animationCurve: UInt = UInt(UIView.AnimationCurve.easeInOut.rawValue),
        springWithDamping: CGFloat? = nil,
        initialVelocity: CGFloat = 0,
        onlyIfNearBottom: Bool = false,
        skipThreshold: CGFloat = 0,
        overrideInputHeight: CGFloat? = nil,
        coAnimatedHideView: UIView? = nil,
        bottomConstraintConstant: CGFloat? = nil
    ) {
        view.layoutIfNeeded()

        let oldInset = collectionView.contentInset

        let distFromBottom: CGFloat
        if collectionView.contentSize.height > 0 && collectionView.bounds.height > 0 {
            distFromBottom = max(0,
                collectionView.contentSize.height
                - collectionView.contentOffset.y
                - collectionView.bounds.height
                + collectionView.contentInset.bottom
            )
        } else {
            distFromBottom = 0
        }

        let navBarBottom = navBar?.frame.maxY ?? view.safeAreaInsets.top
        let rejoinHeight: CGFloat = groupCallRejoinBanner.isHidden ? 0 : groupCallRejoinBanner.frame.height
        let pinnedHeight: CGFloat = pinnedBanner.isHidden ? 0 : pinnedBanner.frame.height
        let topInset = navBarBottom + rejoinHeight + pinnedHeight

        let typingHeight: CGFloat = isTypingActive ? (typingIndicator.frame.height + 4) : 0
        let blockHeight: CGFloat = viewModel.shouldShowBlockView && !blockOverlay.isHidden ? blockOverlay.frame.height : 0
        let effectiveInputHeight: CGFloat
        if blockHeight > 0 {
            effectiveInputHeight = 0
        } else if let override = overrideInputHeight {
            effectiveInputHeight = override
        } else {
            effectiveInputHeight = inputContainer.frame.height
        }
        let bottomInset = composerHomeInset()
            + effectiveInputHeight
            + keyboardHeight
            + blockHeight
            + 8
            + typingHeight


        let effectiveTopInset = topInset

        let newInset = UIEdgeInsets(top: effectiveTopInset, left: 0, bottom: bottomInset, right: 0)
        let insetDelta = newInset.bottom - oldInset.bottom

        let nearBottom = checkIfNearBottom()
        let shouldAdjustOffset = abs(insetDelta) > skipThreshold

        if let constant = bottomConstraintConstant {
            inputContainerBottom?.constant = constant
        }

        let apply = {
            self.collectionView.contentInset = newInset
            self.collectionView.scrollIndicatorInsets = newInset
            if shouldAdjustOffset {
                if self.contentFitsOnScreen() {
                    self.collectionView.contentOffset.y = -effectiveTopInset
                } else if nearBottom || !onlyIfNearBottom {
                    // Near bottom: maintain distance from bottom so newest content stays visible
                    let targetOffset = self.collectionView.contentSize.height
                        - distFromBottom
                        - self.collectionView.bounds.height
                        + newInset.bottom
                    self.collectionView.contentOffset.y = max(-effectiveTopInset, targetOffset)
                } else {
                    // Scrolled up: compensate inset delta so visible content doesn't shift
                    self.collectionView.contentOffset.y -= insetDelta
                }
            }
        }

        let useAnimation = animated && !isInInitialScrollSettlingWindow()
        guard useAnimation else {
            apply()
            coAnimatedHideView?.isHidden = true
            view.layoutIfNeeded()
            return
        }

        let curveOptions = UIView.AnimationOptions(rawValue: animationCurve << 16)
            .union([.beginFromCurrentState, .allowUserInteraction])

        if let damping = springWithDamping {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: damping,
                initialSpringVelocity: initialVelocity,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                coAnimatedHideView?.isHidden = true
                apply()
                self.view.layoutIfNeeded()
            } completion: { _ in
                coAnimatedHideView?.removeFromSuperview()
            }
        } else {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: curveOptions
            ) {
                coAnimatedHideView?.isHidden = true
                apply()
                self.view.layoutIfNeeded()
            } completion: { _ in
                coAnimatedHideView?.removeFromSuperview()
            }
        }
    }
}
