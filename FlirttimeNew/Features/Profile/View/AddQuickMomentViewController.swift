//
//  AddQuickMomentViewController.swift
//  FlirttimeNew
//
//  Composer for a Quick Moment: a line of text on a colour background, or a photo with a caption.
//

import UIKit
import PhotosUI

final class AddQuickMomentViewController: UIViewController {

    /// Text (or caption), background index for text moments, and the photo if one was picked.
    var onShare: ((String?, Int?, UIImage?) -> Void)?

    private var backgroundIndex = 0
    private var photo: UIImage?

    private let canvas = UIView()
    private let textBackground = VibeGradientView(colors: VibeTheme.storyBackground(0))
    private let photoView = UIImageView()
    private let photoShade = VibeGradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.6)],
                                              start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 1))
    private let textView = UITextView()
    private let placeholderLabel = UILabel.vibeLabel(.bold, 26, style: .title1, color: UIColor.white.withAlphaComponent(0.6), lines: 0)
    private let counterLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: UIColor.white.withAlphaComponent(0.8))
    private var textCenterConstraint: NSLayoutConstraint?
    private var textBottomConstraint: NSLayoutConstraint?

    private lazy var closeButton = toolButton("xmark", label: "Close") { [weak self] in self?.dismiss(animated: true) }
    private lazy var paletteButton = toolButton("paintpalette.fill", label: "Change background") { [weak self] in self?.nextBackground() }
    private lazy var photoButton = toolButton("photo.on.rectangle.angled", label: "Add a photo") { [weak self] in self?.photoTapped() }
    private let shareButton = UIButton(type: .system)

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setUI()
        updateMode()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    // MARK: - UI

    private func setUI() {
        canvas.layer.cornerRadius = 24
        canvas.layer.cornerCurve = .continuous
        canvas.clipsToBounds = true
        canvas.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(canvasTapped)))

        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true

        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.tintColor = .white
        textView.textAlignment = .center
        textView.isScrollEnabled = false
        textView.keyboardAppearance = .dark
        textView.delegate = self
        textView.accessibilityLabel = "Quick moment text"
        placeholderLabel.textAlignment = .center
        placeholderLabel.isUserInteractionEnabled = false

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .white
        config.baseForegroundColor = AppColor.Punch
        config.image = UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        config.imagePlacement = .trailing
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        config.attributedTitle = AttributedString("Share", attributes: AttributeContainer([.font: VibeFont.scaled(.bold, 16)]))
        shareButton.configuration = config
        shareButton.addAction(UIAction { [weak self] _ in self?.share() }, for: .touchUpInside)

        let tools = UIStackView(arrangedSubviews: [closeButton, UIView(), paletteButton, photoButton])
        tools.spacing = 10
        tools.alignment = .center
        let bottomBar = UIStackView(arrangedSubviews: [counterLabel, UIView(), shareButton])
        bottomBar.alignment = .center

        [canvas, tools, bottomBar].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [textBackground, photoView, photoShade, textView, placeholderLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            canvas.addSubview($0)
        }
        [textBackground, photoView, photoShade].forEach { $0.pinEdges(to: canvas) }

        let bottomBarResting = bottomBar.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -16)
        bottomBarResting.priority = .defaultHigh
        bottomBarResting.isActive = true
        let center = textView.centerYAnchor.constraint(equalTo: canvas.centerYAnchor, constant: -40)
        let bottom = textView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -16)
        textCenterConstraint = center
        textBottomConstraint = bottom

        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            tools.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 12),
            tools.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 12),
            tools.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -12),

            textView.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 28),
            textView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -28),
            textView.topAnchor.constraint(greaterThanOrEqualTo: tools.bottomAnchor, constant: 16),
            textView.bottomAnchor.constraint(lessThanOrEqualTo: bottomBar.topAnchor, constant: -16),
            center,

            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(lessThanOrEqualTo: canvas.bottomAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
    }

    private func toolButton(_ symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.3)
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
        let button = UIButton(configuration: config)
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 42),
            button.heightAnchor.constraint(equalToConstant: 42)
        ])
        return button
    }

    /// Text moments centre large text on a colour; photo moments show a caption above the Share bar.
    private func updateMode() {
        let isPhoto = photo != nil
        photoView.image = photo
        photoView.isHidden = !isPhoto
        photoShade.isHidden = !isPhoto
        textBackground.isHidden = isPhoto
        textBackground.setColors(VibeTheme.storyBackground(backgroundIndex))
        paletteButton.isHidden = isPhoto
        photoButton.configuration?.image = UIImage(systemName: isPhoto ? "trash.fill" : "photo.on.rectangle.angled",
                                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
        photoButton.accessibilityLabel = isPhoto ? "Remove photo" : "Add a photo"

        let size: CGFloat = isPhoto ? 18 : 28
        textView.font = VibeFont.scaled(.bold, size, style: isPhoto ? .body : .title1)
        placeholderLabel.font = textView.font
        placeholderLabel.text = isPhoto ? "Add a caption…" : "Type a quick moment…"
        textCenterConstraint?.isActive = !isPhoto
        textBottomConstraint?.isActive = isPhoto
        updateTextState()
    }

    private func updateTextState() {
        let text = textView.text ?? ""
        placeholderLabel.isHidden = !text.isEmpty
        counterLabel.text = "\(text.count)/\(MockQuickMomentStore.maxTextLength)"
        let hasContent = photo != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        shareButton.isEnabled = hasContent
        shareButton.alpha = hasContent ? 1 : 0.5
    }

    // MARK: - Actions

    @objc private func canvasTapped() {
        if textView.isFirstResponder {
            view.endEditing(true)
        } else {
            textView.becomeFirstResponder()
        }
    }

    private func nextBackground() {
        backgroundIndex = (backgroundIndex + 1) % VibeTheme.storyBackgrounds.count
        UISelectionFeedbackGenerator().selectionChanged()
        UIView.transition(with: textBackground, duration: 0.25, options: .transitionCrossDissolve) {
            self.textBackground.setColors(VibeTheme.storyBackground(self.backgroundIndex))
        }
    }

    private func photoTapped() {
        if photo != nil {
            photo = nil
            updateMode()
            return
        }
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func share() {
        let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = photo?.fixedOrientation()
        let background = backgroundIndex
        view.endEditing(true)
        dismiss(animated: true) { [onShare] in
            onShare?(text?.isEmpty == false ? text : nil, image == nil ? background : nil, image)
        }
    }
}

extension AddQuickMomentViewController: UITextViewDelegate {

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = (textView.text ?? "") as NSString
        return current.replacingCharacters(in: range, with: text).count <= MockQuickMomentStore.maxTextLength
    }

    func textViewDidChange(_ textView: UITextView) {
        updateTextState()
    }
}

extension AddQuickMomentViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async {
                self?.photo = image
                self?.updateMode()
            }
        }
    }
}
