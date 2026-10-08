import UIKit

final class TextMessageCell: BaseMessageCell {

    static let cellId = "TextMessageCell"
    static let mentionUsernameAttribute = NSAttributedString.Key("mentionUsername")

    private static let dataDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue |
               NSTextCheckingResult.CheckingType.phoneNumber.rawValue
    )

    /// Matches @mentions including dots (e.g. @john.doe). Negative lookbehind skips emails.
    private static let mentionRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "(?<![\\w])@[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*")

    private static let allowedLinkSchemes: Set<String> = ["http", "https", "tel", "mailto", "sms"]

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let translationIndicator: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var previousDisplayContent: String = ""

    // "Read more" / "Less" truncation
    private static let maxCollapsedLines = 10
    private var isExpanded = false
    private var fullAttributedText: NSAttributedString?

    static var expandedMessageIds: Set<String> = []

    private let readMoreButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = UIFont.chat(.medium, size: 14)
        btn.setTitleColor(.systemBlue, for: .normal)
        btn.isHidden = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContentArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContentArea()
    }

    private func setupContentArea() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(readMoreButton)
        stack.addArrangedSubview(translationIndicator)

        let indicatorRow = UIStackView()
        indicatorRow.axis = .horizontal
        indicatorRow.spacing = 3
        indicatorRow.alignment = .center
        indicatorRow.translatesAutoresizingMaskIntoConstraints = false

        let globeIcon = UIImageView(image: UIImage(systemName: "globe"))
        globeIcon.tintColor = .secondaryLabel
        globeIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            globeIcon.widthAnchor.constraint(equalToConstant: 11),
            globeIcon.heightAnchor.constraint(equalToConstant: 11),
        ])

        let translatedLabel = UILabel()
        translatedLabel.text = ChatStrings.chat_translated.localizedString()
        translatedLabel.font = UIFont.chat(size: 10)
        translatedLabel.textColor = .secondaryLabel

        indicatorRow.addArrangedSubview(globeIcon)
        indicatorRow.addArrangedSubview(translatedLabel)
        translationIndicator.addSubview(indicatorRow)
        NSLayoutConstraint.activate([
            indicatorRow.topAnchor.constraint(equalTo: translationIndicator.topAnchor),
            indicatorRow.leadingAnchor.constraint(equalTo: translationIndicator.leadingAnchor),
            indicatorRow.bottomAnchor.constraint(equalTo: translationIndicator.bottomAnchor),
        ])

        contentArea.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        // Link tap gesture
        messageLabel.isUserInteractionEnabled = true
        let linkTap = UITapGestureRecognizer(target: self, action: #selector(handleLinkTap(_:)))
        messageLabel.addGestureRecognizer(linkTap)

        readMoreButton.addTarget(self, action: #selector(handleReadMoreTap), for: .touchUpInside)
    }

    override func configureContent(with model: MessageCellModel) {
        let text = model.displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentChanged = text != previousDisplayContent && !previousDisplayContent.isEmpty
        previousDisplayContent = text

        if model.isSingleEmoji {
            messageLabel.font = UIFont.chat(size: 42)
            messageLabel.textAlignment = model.replyPreview != nil
                ? (model.isIncoming ? .left : .right)
                : .center
            messageLabel.text = text.trimmingCharacters(in: .whitespaces)
            messageLabel.textColor = .label
            translationIndicator.isHidden = true
            readMoreButton.isHidden = true
            fullAttributedText = nil
            isExpanded = false
        } else {
            messageLabel.font = UIFont(name: "Fredoka-Regular", size: 15) ?? UIFont.chat(size: 15)
            messageLabel.textAlignment = .natural

            let textIsLight = !model.isIncoming //&& model.replyPreview == nil
            messageLabel.textColor = textIsLight ? ChatTheme.outgoingText : ChatTheme.incomingText
            let attrText = attributedText(
                from: text, isIncoming: model.isIncoming, lightText: textIsLight,
                mentionedUserNames: model.mentionedUserNames
            )

            if contentChanged {
                UIView.transition(
                    with: messageLabel,
                    duration: 0.25,
                    options: .transitionCrossDissolve,
                    animations: { self.messageLabel.attributedText = attrText }
                )
            } else {
                messageLabel.attributedText = attrText
            }

            let alreadyExpanded = Self.expandedMessageIds.contains(model.stableId)
            fullAttributedText = nil
            isExpanded = alreadyExpanded

            if model.needsTruncation {
                fullAttributedText = attrText
                if alreadyExpanded {
                    messageLabel.numberOfLines = 0
                    readMoreButton.isHidden = true
                } else {
                    messageLabel.numberOfLines = Self.maxCollapsedLines
                    readMoreButton.setTitle(ChatStrings.chat_readMore.localizedString(), for: .normal)
                    readMoreButton.isHidden = false
                }
            } else {
                messageLabel.numberOfLines = 0
                readMoreButton.isHidden = true
            }
        }

        // Translation indicator: animate visibility change
        let hasTranslation = model.translation != nil
        let showTranslation = hasTranslation && model.isShowingTranslation
        if showTranslation {
            if translationIndicator.isHidden {
                translationIndicator.isHidden = false
                translationIndicator.alpha = 0
                UIView.animate(withDuration: 0.25) {
                    self.translationIndicator.alpha = 1
                }
            }
        } else {
            if !translationIndicator.isHidden {
                UIView.animate(withDuration: 0.2, animations: {
                    self.translationIndicator.alpha = 0
                }, completion: { _ in
                    self.translationIndicator.isHidden = true
                    self.translationIndicator.alpha = 1
                })
            }
        }
    }

    private static let htmlCache = NSCache<NSString, NSAttributedString>()

    private func attributedText(
        from text: String,
        isIncoming: Bool,
        lightText: Bool,
        mentionedUserNames: Set<String>
    ) -> NSAttributedString {

//        let cacheKey = "\(lightText ? 1 : 0)|\(text)" as NSString
        let mentionKey = mentionedUserNames.sorted().joined(separator: ",")
        // v2: always bold @tokens (ignore participant-match gating)
        let cacheKey = "v2|\(lightText ? 1 : 0)|\(mentionKey)|\(text)" as NSString
        if let cached = Self.htmlCache.object(forKey: cacheKey) {
            return cached
        }

        // MARK: - Extract plain text (strip HTML tags)
        let plainText: String
        if text.contains("<") && text.contains(">") {
            plainText = text
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;",  with: "&")
                .replacingOccurrences(of: "&lt;",   with: "<")
                .replacingOccurrences(of: "&gt;",   with: ">")
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "\\/",    with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            plainText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !plainText.isEmpty else { return NSAttributedString(string: "") }

        let attributed = NSMutableAttributedString(string: plainText)
        let fullRange  = NSRange(location: 0, length: attributed.length)

        // MARK: - Base style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing           = 3
        paragraphStyle.paragraphSpacing      = 0   // ← explicit zero kills the extra gap
        paragraphStyle.paragraphSpacingBefore = 0

        let baseColor: UIColor = lightText ? .white : .label
        let baseFont  = UIFont(name: "Fredoka-Regular", size: 15) ?? UIFont.chat(size: 15)
        // Prefer Bold over SemiBold so mentions read clearly against Regular body text
        let boldFont  = UIFont(name: "Fredoka-SemiBold", size: 16)
            ?? UIFont(name: "Fredoka-SemiBold", size: 16)
            ?? UIFont.chat(.bold, size: 16)

        attributed.addAttributes([
            .paragraphStyle:  paragraphStyle,
            .foregroundColor: baseColor,
            .font:            baseFont,
        ], range: fullRange)

        // MARK: - Links
        if let detector = TextMessageCell.dataDetector {
            let matches = detector.matches(in: plainText,
                                           range: NSRange(location: 0, length: plainText.utf16.count))
            for match in matches {
                guard NSMaxRange(match.range) <= attributed.length else { continue }
                attributed.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: lightText
                        ? UIColor.white.withAlphaComponent(0.9)
                        : UIColor.systemBlue,
                ], range: match.range)
            }
        }

        // MARK: - Mentions (always style @tokens in the bubble — do not require participant match)
        if let regex = TextMessageCell.mentionRegex {
            let matches = regex.matches(
                in: plainText,
                range: NSRange(location: 0, length: plainText.utf16.count)
            )

            for match in matches {
                guard NSMaxRange(match.range) <= attributed.length,
                      let range = Range(match.range, in: plainText) else {
                    continue
                }

                let userName = String(String(plainText[range]).dropFirst()).lowercased()

                let mentionColor: UIColor = isIncoming
                    ? ChatTheme.primary
                    : UIColor.white

                attributed.addAttributes([
                    .font: boldFont,
                    .foregroundColor: mentionColor,
                    TextMessageCell.mentionUsernameAttribute: userName
                ], range: match.range)
            }
        }

        Self.htmlCache.setObject(attributed, forKey: cacheKey)
        return attributed
    }

    @objc private func handleLinkTap(_ gesture: UITapGestureRecognizer) {
        guard let model = cellModel else { return }
        let text = model.displayContent
        guard !text.isEmpty, let label = gesture.view as? UILabel else { return }

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: label.bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = label.numberOfLines
        textContainer.lineBreakMode = label.lineBreakMode
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage(attributedString: label.attributedText ?? NSAttributedString(string: text))
        textStorage.addLayoutManager(layoutManager)

        let tapPoint = gesture.location(in: label)
        let characterIndex = layoutManager.characterIndex(for: tapPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard characterIndex < textStorage.length else { return }

        // Mentions first — do not depend on the URL/phone data detector
        let tappedAttrs = textStorage.attributes(at: characterIndex, effectiveRange: nil)
        if let username = tappedAttrs[TextMessageCell.mentionUsernameAttribute] as? String {
            actionsDelegate?.cellDidTapMention(self, username: username)
            return
        }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard let detector = TextMessageCell.dataDetector else { return }
        let matches = detector.matches(in: text, range: fullRange)

        for match in matches {
            if characterIndex >= match.range.location && characterIndex < match.range.location + match.range.length {
                if let url = match.url {
                    if let scheme = url.scheme?.lowercased(), Self.allowedLinkSchemes.contains(scheme) {
                        actionsDelegate?.cellDidTapLink(self, url: url)
                    }
                } else if match.resultType == .phoneNumber, let phoneNumber = match.phoneNumber {
                    if let url = URL(string: "tel://\(phoneNumber.filter { $0.isNumber })") {
                        actionsDelegate?.cellDidTapLink(self, url: url)
                    }
                }
                return
            }
        }
    }

    @objc private func handleReadMoreTap() {
        guard !isExpanded else { return }
        isExpanded = true
        let spring = UISpringTimingParameters(dampingRatio: 0.85)
        let animator = UIViewPropertyAnimator(duration: 0.3, timingParameters: spring)
        animator.addAnimations { [weak self] in
            guard let self = self else { return }
            self.messageLabel.numberOfLines = 0
            self.readMoreButton.isHidden = true
            self.actionsDelegate?.cellDidToggleExpand(self)
        }
        animator.startAnimation()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        previousDisplayContent = ""
        messageLabel.attributedText = nil
        messageLabel.text = nil
        messageLabel.numberOfLines = 0
        messageLabel.font = UIFont(name: "Fredoka-Regular", size: 15) ?? UIFont.chat(size: 15)
        messageLabel.textColor = .label
        messageLabel.textAlignment = .natural
        translationIndicator.isHidden = true
        readMoreButton.isHidden = true
        fullAttributedText = nil
        isExpanded = false
    }

    override func configureBubbleAppearance(model: MessageCellModel) {
        if model.isSingleEmoji {
            bubbleContainer.backgroundColor = .clear
            bubbleContainer.layer.cornerRadius = 0
            setBubbleContentInsets(top: 0, horizontal: 0, bottom: 0)
            return
        }

            super.configureBubbleAppearance(model: model)
    }
}
