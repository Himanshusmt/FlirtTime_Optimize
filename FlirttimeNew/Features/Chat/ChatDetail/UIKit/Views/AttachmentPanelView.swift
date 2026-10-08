import UIKit

final class AttachmentPanelView: UIView {

    var onPhoto: (() -> Void)?
    var onCamera: (() -> Void)?
    var onLocation: (() -> Void)?
    var onContact: (() -> Void)?

    private let isChannel: Bool
    var panelHeightConstraint: NSLayoutConstraint?
    let expandedHeight: CGFloat = 112

    init(isChannel: Bool) {
        self.isChannel = isChannel
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = .white
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true

        panelHeightConstraint = heightAnchor.constraint(equalToConstant: 0)
        panelHeightConstraint?.isActive = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])

        stack.addArrangedSubview(
            makeOption(iconName: ChatAssets.gallery, title: ChatStrings.chat_photo.localizedString()) { [weak self] in self?.onPhoto?() }
        )
        stack.addArrangedSubview(
            makeOption(iconName: ChatAssets.camera, title: ChatStrings.chat_camera.localizedString()) { [weak self] in self?.onCamera?() }
        )
        stack.addArrangedSubview(
            makeOption(iconName: ChatAssets.location, title: ChatStrings.chat_location.localizedString()) { [weak self] in self?.onLocation?() }
        )
        stack.addArrangedSubview(
            makeOption(iconName: ChatAssets.contact, title: ChatStrings.chat_contact.localizedString()) { [weak self] in self?.onContact?() }
        )
        enforceRTLIfNeeded()
    }

    // MARK: - Animate In

    func animateIn(completion: (() -> Void)? = nil) {
        superview?.layoutIfNeeded()
        panelHeightConstraint?.constant = expandedHeight

        UIView.animate(
            withDuration: 0.6,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.superview?.layoutIfNeeded()
        } completion: { _ in
            completion?()
        }
    }

    // MARK: - Animate Out

    func animateOut(completion: (() -> Void)? = nil) {
        panelHeightConstraint?.constant = 0

        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 1.0,
            initialSpringVelocity: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.superview?.layoutIfNeeded()
        } completion: { _ in
            self.removeFromSuperview()
            completion?()
        }
    }

    // MARK: - Option Builder

    private func makeOption(iconName: String, title: String, action: @escaping () -> Void) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let btn = UIButton(type: .custom)
        let image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        btn.setImage(image, for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = ChatTheme.primary
        btn.layer.cornerRadius = 28
        btn.contentMode = .center
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)

        wrapper.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: wrapper.topAnchor),
            btn.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            btn.widthAnchor.constraint(equalToConstant: 56),
            btn.heightAnchor.constraint(equalToConstant: 56),
        ])

        let label = UILabel()
        label.text = title
        label.font = UIFont.chat(size: 12)
        label.textColor = ChatTheme.textPrimary
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: btn.bottomAnchor, constant: 6),
            label.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

        return wrapper
    }
}
