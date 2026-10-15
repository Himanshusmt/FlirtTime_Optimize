//
//  ShowOtherUserImageVC.swift
//  FlirtTime
//
//  Created by Smt MacMini on 03/01/25.
//
//  Full-screen photo viewer for another user's photos, with a composer to send them a compliment.
//

import UIKit
import Combine
import IQKeyboardManagerSwift

final class ShowOtherUserImageVC: BaseViewController {

    private static let maxMessageLength = 300
    private static let minMessageHeight: CGFloat = 36
    private static let maxMessageHeight: CGFloat = 104
    private static let photoHeight: CGFloat = 480
    /// Shared by every edge-aligned element so the photo, chips and message bar line up.
    private static let horizontalMargin: CGFloat = 20
    private static let sectionSpacing: CGFloat = 16

    /// Called when sending needs a subscription, after this screen is dismissed.
    var callBack: ((Bool) -> Void)?

    private let details: OtherUserProfileDetails
    private let photoPaths: [String]
    private var currentIndex: Int
    private var isSending = false {
        didSet { updateSendButton() }
    }

    private let viewModel = OtherUserProfileViewModel()
    private var cancellables: Set<AnyCancellable> = []

    private let nameLabel = UILabel.vibeLabel(.bold, 22, style: .title3, color: .white)
    private let counterLabel = UILabel.vibeLabel(.regular, 14, style: .footnote, color: UIColor.white.withAlphaComponent(0.75))
    private let closeButton = UIButton(type: .system)
    private let photoContainer = UIView()
    private let pageBarsStack = UIStackView()
    private lazy var photosCollectionView = makeCollectionView(layout: FullPagePhotoLayout())
    private let suggestionsScrollView = UIScrollView()
    private let messageContainer = UIView()
    private let messageTextView = UITextView()
    private let placeholderLabel = UILabel.vibeLabel(.regular, 16, color: UIColor.white.withAlphaComponent(0.6))
    private let characterCountLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: UIColor.white.withAlphaComponent(0.6))
    private let sendButton = UIButton(type: .system)
    private var messageHeightConstraint: NSLayoutConstraint!

    private var trimmedMessage: String {
        messageTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(details: OtherUserProfileDetails, startIndex: Int) {
        self.details = details
        self.photoPaths = details.photos.compactMap(\.image).filter { !$0.isEmpty }
        self.currentIndex = min(max(startIndex, 0), max(photoPaths.count - 1, 0))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        bindViewModel()
        updatePageIndicators()
        updateMessageState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        IQKeyboardManager.shared.isEnabled = false
        IQKeyboardManager.shared.enableAutoToolbar = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IQKeyboardManager.shared.isEnabled = true
        IQKeyboardManager.shared.enableAutoToolbar = true
    }

    /// The photo resizes with the keyboard; this keeps the current one in place.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The pager is nested inside the photo container, so its frame isn't final until the container lays out.
        photoContainer.layoutIfNeeded()
        let width = photosCollectionView.bounds.width
        guard width > 0, !photosCollectionView.isDragging, !photosCollectionView.isDecelerating else { return }
        let offset = CGPoint(x: CGFloat(currentIndex) * width, y: 0)
        if photosCollectionView.contentOffset != offset {
            photosCollectionView.contentOffset = offset
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        view.backgroundColor = .clear

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        let dim = UIView()
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        [blur, dim].forEach {
            view.addSubview($0)
            $0.pinEdges(to: view)
        }

        nameLabel.text = details.name
        let titleStack = UIStackView(arrangedSubviews: [nameLabel, counterLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        var closeConfig = UIButton.Configuration.filled()
        closeConfig.cornerStyle = .capsule
        closeConfig.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        closeConfig.baseForegroundColor = .white
        closeConfig.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        closeButton.configuration = closeConfig
        closeButton.accessibilityLabel = "Close"
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleStack, closeButton])
        header.alignment = .center
        header.spacing = 12

        photoContainer.layer.cornerRadius = 24
        photoContainer.layer.cornerCurve = .continuous
        photoContainer.clipsToBounds = true
        photoContainer.backgroundColor = UIColor.white.withAlphaComponent(0.08)

        photosCollectionView.isPagingEnabled = true
        photosCollectionView.register(ComplimentPhotoCell.self, forCellWithReuseIdentifier: ComplimentPhotoCell.identifier)
        let endEditingTap = UITapGestureRecognizer(target: self, action: #selector(endEditing))
        endEditingTap.cancelsTouchesInView = false
        photosCollectionView.addGestureRecognizer(endEditingTap)

        let bottomShade = MomentsGradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.4)],
                                              start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
        bottomShade.isUserInteractionEnabled = false
        pageBarsStack.axis = .horizontal
        pageBarsStack.spacing = 4
        pageBarsStack.distribution = .fillEqually
        pageBarsStack.isUserInteractionEnabled = false
        pageBarsStack.isHidden = photoPaths.count < 2
        bottomShade.isHidden = pageBarsStack.isHidden
        (0..<photoPaths.count).forEach { _ in
            let bar = UIView()
            bar.layer.cornerRadius = 1.5
            bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
            pageBarsStack.addArrangedSubview(bar)
        }

        [photosCollectionView, bottomShade, pageBarsStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            photoContainer.addSubview($0)
        }
        photosCollectionView.pinEdges(to: photoContainer)

        buildSuggestions()
        buildMessageBar()

        let messageRow = UIStackView(arrangedSubviews: [messageContainer, sendButton])
        messageRow.spacing = 10
        messageRow.alignment = .bottom

        [header, photoContainer, suggestionsScrollView, messageRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        // Header, photo, suggestions and message bar are stacked with fixed gaps and the photo is centred on screen.
        // When there isn't room (small screens or the keyboard), the photo gives up height first, then centring.
        let margin = Self.horizontalMargin
        let preferredPhotoHeight = photoContainer.heightAnchor.constraint(equalToConstant: Self.photoHeight)
        preferredPhotoHeight.priority = .defaultHigh
        let centerPhoto = photoContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        centerPhoto.priority = .defaultHigh - 10
        let minPhotoHeight = photoContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        minPhotoHeight.priority = .defaultHigh + 10
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor, constant: 8),
            header.bottomAnchor.constraint(equalTo: photoContainer.topAnchor, constant: -12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            photoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            photoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            preferredPhotoHeight,
            centerPhoto,
            minPhotoHeight,

            bottomShade.bottomAnchor.constraint(equalTo: photoContainer.bottomAnchor),
            bottomShade.leadingAnchor.constraint(equalTo: photoContainer.leadingAnchor),
            bottomShade.trailingAnchor.constraint(equalTo: photoContainer.trailingAnchor),
            bottomShade.heightAnchor.constraint(equalToConstant: 56),
            pageBarsStack.bottomAnchor.constraint(equalTo: photoContainer.bottomAnchor, constant: -14),
            pageBarsStack.leadingAnchor.constraint(equalTo: photoContainer.leadingAnchor, constant: 16),
            pageBarsStack.trailingAnchor.constraint(equalTo: photoContainer.trailingAnchor, constant: -16),

            suggestionsScrollView.topAnchor.constraint(equalTo: photoContainer.bottomAnchor, constant: Self.sectionSpacing),
            suggestionsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            suggestionsScrollView.bottomAnchor.constraint(equalTo: messageRow.topAnchor, constant: -12),
            suggestionsScrollView.heightAnchor.constraint(equalToConstant: 36),

            messageRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            messageRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            messageRow.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
    }

    private func makeCollectionView(layout: UICollectionViewLayout) -> UICollectionView {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = self
        collectionView.delegate = self
        return collectionView
    }

    private func buildSuggestions() {
        let stack = UIStackView()
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        Constants.Compliment.suggestions.forEach { suggestion in
            var config = UIButton.Configuration.filled()
            config.cornerStyle = .capsule
            config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.14)
            config.baseForegroundColor = .white
            config.background.strokeColor = UIColor.white.withAlphaComponent(0.3)
            config.background.strokeWidth = 1
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            config.attributedTitle = AttributedString(suggestion, attributes: AttributeContainer([
                .font: MomentsFont.scaled(.medium, 14, style: .subheadline)
            ]))
            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in self?.useSuggestion(suggestion) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        suggestionsScrollView.showsHorizontalScrollIndicator = false
        suggestionsScrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: suggestionsScrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: suggestionsScrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: suggestionsScrollView.contentLayoutGuide.leadingAnchor, constant: Self.horizontalMargin),
            stack.trailingAnchor.constraint(equalTo: suggestionsScrollView.contentLayoutGuide.trailingAnchor, constant: -Self.horizontalMargin),
            stack.heightAnchor.constraint(equalTo: suggestionsScrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    private func buildMessageBar() {
        messageContainer.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        messageContainer.layer.cornerRadius = 24
        messageContainer.layer.cornerCurve = .continuous
        messageContainer.layer.borderWidth = 1
        messageContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor

        messageTextView.backgroundColor = .clear
        messageTextView.textColor = .white
        messageTextView.tintColor = .white
        messageTextView.font = MomentsFont.scaled(.regular, 16)
        messageTextView.adjustsFontForContentSizeCategory = true
        messageTextView.keyboardAppearance = .dark
        messageTextView.isScrollEnabled = false
        messageTextView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        messageTextView.textContainer.lineFragmentPadding = 0
        messageTextView.accessibilityLabel = "Compliment for \(details.name)"
        messageTextView.delegate = self

        placeholderLabel.text = String(format: Constants.Compliment.placeholderFormat, details.name)
        placeholderLabel.isAccessibilityElement = false
        characterCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        characterCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        [messageTextView, placeholderLabel, characterCountLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            messageContainer.addSubview($0)
        }

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Punch
        config.baseForegroundColor = .white
        // Stays red when disabled instead of the system grey; `updateSendButton` fades it.
        config.background.backgroundColorTransformer = UIConfigurationColorTransformer { _ in AppColor.Punch }
        config.imageColorTransformer = UIConfigurationColorTransformer { _ in .white }
        config.image = UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
        sendButton.configuration = config
        sendButton.accessibilityLabel = "Send compliment"
        sendButton.addAction(UIAction { [weak self] _ in self?.sendCompliment() }, for: .touchUpInside)

        messageHeightConstraint = messageTextView.heightAnchor.constraint(equalToConstant: Self.minMessageHeight)
        NSLayoutConstraint.activate([
            messageTextView.topAnchor.constraint(equalTo: messageContainer.topAnchor, constant: 6),
            messageTextView.bottomAnchor.constraint(equalTo: messageContainer.bottomAnchor, constant: -6),
            messageTextView.leadingAnchor.constraint(equalTo: messageContainer.leadingAnchor, constant: 18),
            messageTextView.trailingAnchor.constraint(equalTo: characterCountLabel.leadingAnchor, constant: -8),
            messageHeightConstraint,

            placeholderLabel.leadingAnchor.constraint(equalTo: messageTextView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: messageTextView.trailingAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: messageTextView.topAnchor, constant: Self.minMessageHeight / 2),

            characterCountLabel.trailingAnchor.constraint(equalTo: messageContainer.trailingAnchor, constant: -16),
            characterCountLabel.bottomAnchor.constraint(equalTo: messageTextView.bottomAnchor, constant: -9),

            sendButton.widthAnchor.constraint(equalToConstant: 48),
            sendButton.heightAnchor.constraint(equalToConstant: 48),
            messageContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.$aSendCompliment.compactMap { $0 }.receive(on: DispatchQueue.main).sink { [weak self] compliment in
            guard let self else { return }
            self.isSending = false
            let message = compliment.message.flatMap { $0.isEmpty ? nil : $0 } ?? Constants.Compliment.sent
            self.dismiss(animated: true) {
                self.showNewAlertPopUp(Title: "Success", Msg: message, isSuccess: true, CompletionHandler: { _ in })
            }
        }.store(in: &cancellables)

        viewModel.$errorSendCompliment.compactMap { $0 }.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self else { return }
            self.isSending = false
            self.showNewAlertPopUp(Title: "Failed", Msg: error, isSuccess: false, CompletionHandler: { _ in })
        }.store(in: &cancellables)

        viewModel.$errorState.compactMap { $0 }.receive(on: DispatchQueue.main).sink { [weak self] state in
            guard let self else { return }
            self.isSending = false
            self.dismiss(animated: true) { self.callBack?(state) }
        }.store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func endEditing() {
        view.endEditing(true)
    }

    private func useSuggestion(_ suggestion: String) {
        messageTextView.text = String(suggestion.prefix(Self.maxMessageLength))
        updateMessageState()
        if !messageTextView.isFirstResponder {
            messageTextView.becomeFirstResponder()
        }
    }

    private func sendCompliment() {
        let message = trimmedMessage
        guard !message.isEmpty, !isSending else { return }
        view.endEditing(true)
        isSending = true
        viewModel.sendCompliment(userID: details.remoteUserID ?? String(details.userID), message: message)
    }

    private func setCurrentIndex(_ index: Int) {
        guard index != currentIndex, photoPaths.indices.contains(index) else { return }
        currentIndex = index
        updatePageIndicators()
    }

    // MARK: - State

    private func updatePageIndicators() {
        counterLabel.text = photoPaths.isEmpty ? nil : "Photo \(currentIndex + 1) of \(photoPaths.count)"
        counterLabel.isHidden = photoPaths.count < 2
        pageBarsStack.arrangedSubviews.enumerated().forEach { index, bar in
            bar.backgroundColor = index == currentIndex ? AppColor.Punch : UIColor.white.withAlphaComponent(0.5)
        }
    }

    private func updateMessageState() {
        let text = messageTextView.text ?? ""
        placeholderLabel.isHidden = !text.isEmpty
        // An empty label has no width, so the text view gets the full row until typing starts.
        characterCountLabel.text = text.isEmpty ? nil : "\(text.count)/\(Self.maxMessageLength)"
        messageContainer.layoutIfNeeded()
        updateMessageHeight()
        updateSendButton()
    }

    private func updateMessageHeight() {
        let width = messageTextView.bounds.width
        guard width > 0 else { return }
        let fitting = messageTextView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        messageTextView.isScrollEnabled = fitting > Self.maxMessageHeight
        messageHeightConstraint.constant = min(max(fitting, Self.minMessageHeight), Self.maxMessageHeight)
    }

    private func updateSendButton() {
        sendButton.isEnabled = !trimmedMessage.isEmpty && !isSending
        sendButton.configuration?.showsActivityIndicator = isSending
        sendButton.alpha = sendButton.isEnabled || isSending ? 1 : 0.45
    }
}

// MARK: - Photos

extension ShowOtherUserImageVC: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photoPaths.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ComplimentPhotoCell.identifier, for: indexPath) as! ComplimentPhotoCell
        cell.configure(path: photoPaths[indexPath.item])
        cell.accessibilityLabel = "\(details.name)'s photo \(indexPath.item + 1) of \(photoPaths.count)"
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === photosCollectionView, scrollView.isDragging || scrollView.isDecelerating else { return }
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        setCurrentIndex(Int((scrollView.contentOffset.x / width).rounded()))
    }
}

// MARK: - Message

extension ShowOtherUserImageVC: UITextViewDelegate {

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let stringRange = Range(range, in: textView.text) else { return false }
        return textView.text.replacingCharacters(in: stringRange, with: text).count <= Self.maxMessageLength
    }

    func textViewDidChange(_ textView: UITextView) {
        updateMessageState()
    }
}

// MARK: - Layout

/// Horizontal pages that always match the collection view's size, which changes as the keyboard shows and hides.
private final class FullPagePhotoLayout: UICollectionViewFlowLayout {

    override init() {
        super.init()
        scrollDirection = .horizontal
        minimumLineSpacing = 0
        minimumInteritemSpacing = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepare() {
        if let size = collectionView?.bounds.size, size.width > 0, size.height > 0 {
            itemSize = size
        }
        super.prepare()
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
    }
}

// MARK: - Cell

/// A full-size page in the photo pager.
final class ComplimentPhotoCell: UICollectionViewCell {
    static let identifier = "ComplimentPhotoCell"

    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.pinEdges(to: contentView)
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(path: String) {
        imageView.loadImage(path: path, placeholder: UIImage(named: "ProfileBlur"))
    }
}
