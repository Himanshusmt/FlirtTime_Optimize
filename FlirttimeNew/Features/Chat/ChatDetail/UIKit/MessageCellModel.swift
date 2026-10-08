import UIKit

// MARK: - Message Kind

enum MessageKind: Equatable, Hashable {
    case text
    case image
    case video
    case audio
    case contact
    case post
    case vibe
    case reel
    case story
    case poll
    case location
    case deleted
    case system
    case unknown

    static func kind(for message: ConversationMessage) -> MessageKind {
        switch rawKind(for: message) {
        case .contact, .post, .vibe, .reel, .story, .poll, .location:
            return .unknown
        case let kind:
            return kind
        }
    }

    private static func rawKind(for message: ConversationMessage) -> MessageKind {
        if message.isSystemMessage { return .system }
        if message.metadata?["isContact"]?.value as? Bool == true { return .contact }

        let msgType = (message.messageType ?? message.type ?? "").lowercased()

        // Shared content / special types must win over media-album heuristics
        // (a shared carousel post can include multiple media entries).
        switch msgType {
        case "post": return Self.postOrVibe(for: message)
        case "reel": return .reel
        case "story": return .story
        case "poll": return .poll
        case "location": return .location
        case "system": return .system
        case "text": return .text
        default: break
        }

        if message.post != nil { return Self.postOrVibe(for: message) }
        if message.sharedPost != nil { return Self.postOrVibe(for: message) }
        if message.reel != nil { return .reel }
        if message.story != nil { return .story }
        if let sc = message.sharedContentInfo {
            switch (sc.contentType ?? sc.mediaType ?? "").lowercased() {
            case "reel": return .reel
            case "story": return .story
            default: return Self.postOrVibe(for: message)
            }
        }
        if message.poll != nil { return .poll }
        if message.serverLocation != nil { return .location }

        // Multi-media albums always use the image grid cell (WhatsApp-style).
        // Must run before single image/video type checks — mixed albums use messageType "video".
        if let media = message.media, media.count > 1 {
            let allAudio = media.allSatisfy { ($0.type ?? "").lowercased() == "audio" }
            if !allAudio { return .image }
        }

        switch msgType {
        case "image", "photo": return .image
        case "video": return .video
        case "audio", "voice": return .audio
        default: break
        }

        if let media = message.media, !media.isEmpty {
            let url = media[0].url?.lowercased() ?? ""
            let mediaType = (media[0].type ?? "").lowercased()
            // Prefer explicit medias[].type/kind over URL extension — voice notes
            // use audio/mp4 and may end in .mp4 while remaining audio.
            if mediaType == "audio" || mediaType == "voice" { return .audio }
            if mediaType == "video" { return .video }
            if mediaType == "image" || mediaType == "photo" { return .image }
            if url.hasSuffix(".mp4") || url.hasSuffix(".mov") || url.hasSuffix(".m4v") {
                return .video
            }
            if url.hasSuffix(".mp3") || url.hasSuffix(".m4a") || url.hasSuffix(".wav") {
                return .audio
            }
            if url.hasSuffix(".jpg") || url.hasSuffix(".jpeg") || url.hasSuffix(".png") || url.hasSuffix(".webp") {
                return .image
            }
        }
        return .unknown
    }

    private static func postOrVibe(for message: ConversationMessage) -> MessageKind {
        message.isTextOnlySharedVibe ? .vibe : .post
    }

    var cellIdentifier: String {
        switch self {
        case .text: return TextMessageCell.cellId
        case .image: return ImageMessageCell.cellId
        case .video: return VideoMessageCell.cellId
        case .audio: return ChatAudioMessageCell.cellId
        case .contact: return ContactMessageCell.cellId
        case .location: return LocationMessageCell.cellId
        case .poll, .post, .vibe, .reel, .story: return TextMessageCell.cellId
        case .deleted: return TextMessageCell.cellId
        case .system: return SystemMessageCell.cellId
        case .unknown: return TextMessageCell.cellId
        }
    }

    var estimatedHeight: CGFloat {
        switch self {
        case .text: return 72
        case .image: return 280
        case .video: return 280
        case .audio: return 80
        case .contact: return 64
        case .poll: return 200
        case .location: return 310
        case .post: return 220
        case .vibe: return 130
        case .reel: return 380
        case .story: return 280
        case .deleted: return 44
        case .system: return 36
        case .unknown: return 72
        }
    }
}

// MARK: - Cell Model

struct MessageCellModel: Hashable {
    let stableId: String
    let message: ConversationMessage
    let kind: MessageKind
    let isIncoming: Bool
    let isGroupChat: Bool
    let senderName: String?
    let senderAvatar: String?
    let displayContent: String
    let translation: String?
    let isShowingTranslation: Bool
    let timeText: String
    let deliveryStatus: DeliveryStatus
    var isUploading: Bool
    let replyPreview: ReplyPreviewModel?
    let reactions: [MessageReaction]
    let isEdited: Bool
    let isPinned: Bool
    let isForwarded: Bool
    let isDeletedState: Bool
    let mediaItems: [MediaItemModel]
    let pollData: PollData?
    let locationData: ServerLocationSimple?
    let sharedPost: Post?
    let sharedReel: ReelResponse?
    let sharedStory: ChatStory?
    let isSingleEmoji: Bool
    let mentionedUserNames: Set<String>
    var isSelected: Bool
    let currentUserId: String?
    let measuredHeight: CGFloat
    let fullHeight: CGFloat
    let needsTruncation: Bool

    private static var heightCache: [String: (collapsed: CGFloat, full: CGFloat, truncates: Bool)] = [:]
    private static var heightCacheOrder: [String] = []
    private static let heightCacheLimit = 500

    static func flushHeightCache() {
        heightCache.removeAll()
        heightCacheOrder.removeAll()
    }

    static func invalidateHeightCache(forStableId stableId: String) {
        let prefix = "\(stableId)#"
        heightCache = heightCache.filter { !$0.key.hasPrefix(prefix) }
        heightCacheOrder.removeAll { $0.hasPrefix(prefix) }
    }

    static func from(
        _ message: ConversationMessage,
        isGroupChat: Bool,
        currentUserId: String?,
        showingTranslation: Bool = false,
        groupParticipants: [GroupParticipant] = []
    ) -> MessageCellModel {
        let isIncoming = message.senderId != currentUserId
        let kind = MessageKind.kind(for: message)
//        let senderName = MessageCellModel.displayName(for: message.sender)
        let senderName = MessageCellModel.resolveSenderName(
            for: message,
            groupParticipants: groupParticipants
        )
        let senderId = message.senderId ?? message.sender?.id
        let senderAvatar = message.sender?.profilePicture
            ?? groupParticipants.first(where: {
                $0.userId == senderId || $0.id == senderId
            })?.profilePicture
        let timeText = Self.formatTime(message.createdAt)

        let deliveryStatus = DeliveryStatus.from(message: message, currentUserId: currentUserId)

        // Spinner over outgoing image/video until the message actually leaves "sending".
        // Also keep it if the background uploader is still active (race before status updates).
        let isOutgoingVisualMedia = !isIncoming && (kind == .image || kind == .video)
        let isUploading: Bool
        if isOutgoingVisualMedia && deliveryStatus == .sending {
            isUploading = true
        } else if isOutgoingVisualMedia {
            isUploading = MainActor.assumeIsolated {
                BackgroundUploadService.shared.isActive(tempId: message.stableId)
            }
        } else {
            isUploading = false
        }
        let replyPreview = message.replyToId.map { reply -> ReplyPreviewModel in
            var preview = ReplyPreviewModel.from(reply)
            // NEW replyTo often only has senderId — resolve display name from participants
            // (groups) or synthesized DM peer/self entries.
            if preview.senderName == "Unknown" || preview.senderName.isEmpty {
                let senderId = (reply.sender.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !senderId.isEmpty,
                   let participant = groupParticipants.first(where: {
                       $0.userId == senderId || $0.id == senderId
                   }) {
                    let resolved = GroupParticipantDisplay.displayName(
                        fullName: participant.fullName,
                        userName: participant.userName,
                        fallback: ""
                    )
                    if !resolved.isEmpty {
                        preview = ReplyPreviewModel(
                            messageId: preview.messageId,
                            senderName: resolved,
                            content: preview.content,
                            thumbnailURL: preview.thumbnailURL,
                            messageType: preview.messageType
                        )
                    }
                }
                if preview.senderName == "Unknown" || preview.senderName.isEmpty,
                   !senderId.isEmpty, senderId == currentUserId {
                    preview = ReplyPreviewModel(
                        messageId: preview.messageId,
                        senderName: ChatStrings.chat_you.localizedString(),
                        content: preview.content,
                        thumbnailURL: preview.thumbnailURL,
                        messageType: preview.messageType
                    )
                }
            }
            return preview
        }
        let reactions = message.reactions ?? []
        let sanitizedTranslation = ChatTranslationText.sanitized(message.translation)
        let visibleTranslation = showingTranslation && sanitizedTranslation != nil
        var displayContent = visibleTranslation
            ? (sanitizedTranslation ?? "")
            : (message.originalContentForDisplay.isEmpty ? (message.content ?? "") : message.originalContentForDisplay)

        let isDeletedState = Self.isMessageDeleted(message)
        if isDeletedState {
            let serverContent = message.content ?? ""
            displayContent = serverContent.isEmpty
                ? ChatStrings.chat_messageDeleted.localizedString()
                : serverContent
        }
        // Contact messages: reconstruct full display text from metadata if content was truncated
        if message.metadata?["isContact"]?.value as? Bool == true,
           !visibleTranslation {
            let contactName = message.metadata?["contactName"]?.value as? String
            let contactPhone = message.metadata?["contactPhone"]?.value as? String
            if let name = contactName, !name.isEmpty {
                let phone = contactPhone ?? ""
                let reconstructed = "Contact: \(name)\nPhone: \(phone)"
                // Only use reconstructed version if it's more complete than what the server returned
                if !displayContent.contains("\n") || displayContent.count < reconstructed.count {
                    displayContent = reconstructed
                }
            }
        }
        
        if displayContent.containsHTMLMarkup || (displayContent.contains("<") && displayContent.contains(">")) {
            displayContent = displayContent.htmlToString
        }

        
        
        let isSingleEmoji = Self.checkSingleEmoji(displayContent.trimmingCharacters(in: .whitespaces))

        var mediaItems = (message.media ?? []).enumerated().map { index, media in
            MediaItemModel.from(media, fallbackId: "\(message.id)_\(index)")
        }

        // Fallback for optimistic messages that have content URL but no media array
        if mediaItems.isEmpty {
            if (kind == .image || kind == .video), let url = message.content {
                mediaItems = [MediaItemModel(
                    id: message.id,
                    url: url,
                    thumbnailURL: message.thumbnail,
                    type: kind == .video ? "video" : "image",
                    fileName: nil,
                    fileSize: nil,
                    duration: nil
                )]
            }
        }

        // Resolve @mentions from metadata and/or @username tokens in display text
        let mentionedUserNames = Self.resolveMentionedUserNames(
            from: message,
            displayText: displayContent,
            participants: groupParticipants
        )

        let hasReactions = !(reactions.isEmpty)

        let currentWidth = Int(MessageCellModel.screenWidth)
        let replyId = message.replyToId?.id ?? ""
        let isForwarded = (message.metadata?["isForwarded"]?.value as? Bool == true)
        let heightKey = "\(message.stableId)#\(kind)#\(displayContent.count)#\(isIncoming)#\(isGroupChat)#\(hasReactions)#\(message.isPinned == true)#\(isForwarded)#\(replyId)#\(mentionedUserNames.count)#\(visibleTranslation)#\(currentWidth)#\(isDeletedState)"

        let collapsedHeight: CGFloat
        let fullHeight: CGFloat
        let needsTruncation: Bool

        if let cached = Self.heightCache[heightKey] {
            collapsedHeight = cached.collapsed
            fullHeight = cached.full
            needsTruncation = cached.truncates
        } else {
            let measuredHeight = MessageCellModel.measureHeight(
                kind: kind,
                message: message,
                isIncoming: isIncoming,
                isGroupChat: isGroupChat,
                hasReactions: hasReactions,
                displayText: displayContent,
                mentionedUserNames: mentionedUserNames,
                showingTranslation: visibleTranslation
            )

            if (kind == .text || kind == .unknown) && !displayContent.isEmpty && !isSingleEmoji {
                let textAttr = Self.measureAttributedText(displayContent, mentions: mentionedUserNames)
                let fullTextH = ceil(textAttr.boundingRect(
                    with: CGSize(width: maxBubbleContentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil).height)
                let lineHeight = MessageCellMetrics.bodyFont.lineHeight
                let tenLineH = (lineHeight + MessageCellMetrics.bodyLineSpacing) * CGFloat(MessageCellMetrics.maxCollapsedLines)
                needsTruncation = fullTextH > tenLineH
                fullHeight = measuredHeight
                if needsTruncation {
                    let textDelta = fullTextH - tenLineH
                    collapsedHeight = measuredHeight - textDelta + MessageCellMetrics.readMoreExtraHeight
                } else {
                    collapsedHeight = measuredHeight
                }
            } else {
                needsTruncation = false
                fullHeight = measuredHeight
                collapsedHeight = measuredHeight
            }

            Self.heightCache[heightKey] = (collapsedHeight, fullHeight, needsTruncation)
            Self.heightCacheOrder.append(heightKey)
            if Self.heightCacheOrder.count > Self.heightCacheLimit {
                let toRemove = Self.heightCacheOrder.prefix(Self.heightCacheLimit / 5)
                for key in toRemove {
                    Self.heightCache.removeValue(forKey: key)
                }
                Self.heightCacheOrder.removeFirst(toRemove.count)
            }
        }

        return MessageCellModel(
            stableId: message.stableId,
            message: message,
            kind: kind,
            isIncoming: isIncoming,
            isGroupChat: isGroupChat,
            senderName: senderName,
            senderAvatar: senderAvatar,
            displayContent: displayContent,
            translation: message.translation,
            isShowingTranslation: visibleTranslation,
            timeText: timeText,
            deliveryStatus: deliveryStatus,
            isUploading: isUploading,
            replyPreview: replyPreview,
            reactions: reactions,
            isEdited: message.isEdited == true,
            isPinned: message.isPinned == true,
            isForwarded: message.metadata?["isForwarded"]?.value as? Bool == true,
            isDeletedState: isDeletedState,
            mediaItems: mediaItems,
            pollData: message.poll,
            locationData: message.serverLocation,
            sharedPost: message.post,
            sharedReel: message.reel,
            sharedStory: message.story,
            isSingleEmoji: isSingleEmoji,
            mentionedUserNames: mentionedUserNames,
            isSelected: false,
            currentUserId: currentUserId,
            measuredHeight: collapsedHeight,
            fullHeight: fullHeight,
            needsTruncation: needsTruncation
        )
    }

    static func displayName(for sender: ConversationMessageSender?) -> String? {
        guard let sender else { return nil }
        if let name = GroupParticipantDisplay.cleanName(sender.fullName) { return name }
        if let name = GroupParticipantDisplay.cleanName(sender.userName) { return name }
        return nil
    }

    static func resolveSenderName(
        for message: ConversationMessage,
        groupParticipants: [GroupParticipant]
    ) -> String? {
        // 1. Nested sender (OLD payloads) — never show raw id
        if let name = GroupParticipantDisplay.cleanName(message.sender?.fullName) {
            return name
        }
        if let name = GroupParticipantDisplay.cleanName(message.sender?.userName) {
            return name
        }

        // 2. FE: memberNameById.get(msg.senderId) — match userId or member id
        guard let senderId = message.senderId ?? message.sender?.id, !senderId.isEmpty else {
            return nil
        }

        if let participant = groupParticipants.first(where: {
            $0.userId == senderId || $0.id == senderId
        }) {
            return GroupParticipantDisplay.displayName(
                fullName: participant.fullName,
                userName: participant.userName
            )
        }

        // 3. FE fallback when members not loaded / name missing
        return "Member"
    }

    private static let isoParserFull: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let isoParserShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static var screenWidth: CGFloat { UIScreen.main.bounds.width }
    static var maxBubbleContentWidth: CGFloat { floor(screenWidth * MessageCellMetrics.maxBubbleWidthRatio) - (MessageCellMetrics.textProfilePadH * 2) }

    private static func formatTime(_ isoString: String?) -> String {
        guard let isoString else { return "" }
        if let date = isoParserFull.date(from: isoString) {
            return DateFormatterCache.timeFormatter.string(from: date)
        }
        if let date = isoParserShort.date(from: isoString) {
            return DateFormatterCache.timeFormatter.string(from: date)
        }
        return ""
    }

    static func checkSingleEmoji(_ text: String) -> Bool {
        guard text.count == 1, let first = text.first else { return false }
        let scalars = first.unicodeScalars
        return scalars.allSatisfy { scalar in
            scalar.properties.isEmoji ||
            scalar == "\u{200D}" ||     // ZWJ (combines emoji into one cluster)
            scalar == "\u{FE0F}" ||     // Variation selector (emoji presentation)
            scalar == "\u{FE0E}" ||     // Variation selector (text presentation)
            scalar.properties.isEmojiModifier ||
            scalar.properties.isEmojiModifierBase
        }
    }

    private static let mentionMeasureRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "(?<![\\w])@[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*")

    static func isMessageDeleted(_ message: ConversationMessage) -> Bool {
        message.isDeleted == true
            || message.status?.lowercased() == "deleted"
            || (message.metadata?["isDeletedEveryone"]?.value as? Bool == true)
    }

    static func deletedBubbleWidth(for displayContent: String) -> CGFloat {
        let maxBubbleW = floor(screenWidth * MessageCellMetrics.maxBubbleWidthRatio)
        let labelConstraintW = maxBubbleW - (MessageCellMetrics.textProfilePadH * 2)
        let font = UIFont.italicSystemFont(ofSize: 14)
        let attr = NSAttributedString(
            string: displayContent.trimmingCharacters(in: .whitespaces),
            attributes: [.font: font]
        )
        let textW = ceil(attr.boundingRect(
            with: CGSize(width: labelConstraintW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).width)
        let deletedPad: CGFloat = (MessageCellMetrics.textProfilePadH * 2) + (MessageCellMetrics.bodyBufferBot * 2)
        return min(max(textW + deletedPad, MessageCellMetrics.deletedMinBubbleWidth), maxBubbleW)
    }

    static func measureAttributedText(_ text: String, mentions: Set<String>) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let baseFont = MessageCellMetrics.bodyFont
        let boldFont = MessageCellMetrics.bodyBoldFont

        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = MessageCellMetrics.bodyLineSpacing
        attr.addAttribute(.paragraphStyle, value: ps, range: fullRange)
        attr.addAttribute(.font, value: baseFont, range: fullRange)

        // Always measure @mentions as bold so layout matches rendered bubbles
        if let regex = mentionMeasureRegex {
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                attr.addAttribute(.font, value: boldFont, range: match.range)
            }
        }
        return attr
    }

    static func measureHeight(
        kind: MessageKind,
        message: ConversationMessage,
        isIncoming: Bool,
        isGroupChat: Bool,
        hasReactions: Bool,
        displayText: String,
        mentionedUserNames: Set<String> = [],
        showingTranslation: Bool = false
    ) -> CGFloat {

        if kind == .system {
            let text = message.content ?? ""
            let font = UIFont.chat(.medium, size: 12)
            let textH = ceil(text.boundingRect(
                with: CGSize(width: screenWidth * 0.75 - 24, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: font],
                context: nil).height)
            return ceil(textH + 24)
        }

        if Self.isMessageDeleted(message) {
            let bubbleW = Self.deletedBubbleWidth(for: displayText)
            let labelW = max(bubbleW - (MessageCellMetrics.textProfilePadH * 2), 50)
            let font = UIFont.italicSystemFont(ofSize: 14)
            let attr = NSAttributedString(string: displayText, attributes: [.font: font])
            let textH = ceil(attr.boundingRect(
                with: CGSize(width: labelW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil).height)
            let cellPad = MessageCellMetrics.cellPadTop + MessageCellMetrics.cellPadBottom
            let bubblePadV = MessageCellMetrics.textProfilePadTop + MessageCellMetrics.textProfilePadBottom
            let columnGap = MessageCellMetrics.columnSpacing
            let footer = MessageCellMetrics.footerHeight
            var h: CGFloat = cellPad + bubblePadV + columnGap + footer
            if isIncoming && isGroupChat {
                h += MessageCellMetrics.senderHeaderHeight + columnGap
            }
            return ceil(h + max(textH + MessageCellMetrics.bodyBufferBot, MessageCellMetrics.bodyMinH))
        }

        let hasBubblePadding = (kind == .text || kind == .unknown || kind == .deleted || kind == .contact)
        let cellPad = MessageCellMetrics.cellPadTop + MessageCellMetrics.cellPadBottom
        let columnGap = MessageCellMetrics.columnSpacing
        let footer = MessageCellMetrics.footerHeight
        let bubblePadV = hasBubblePadding
            ? MessageCellMetrics.textProfilePadTop + MessageCellMetrics.textProfilePadBottom
            : 0
        var h: CGFloat = cellPad + bubblePadV + columnGap + footer

        if isIncoming && isGroupChat {
            h += MessageCellMetrics.senderHeaderHeight + columnGap
        }

        if message.isPinned == true {
            h += MessageCellMetrics.pinnedCapsuleHeight + columnGap
        }

        if message.metadata?["isForwarded"]?.value as? Bool == true {
            h += MessageCellMetrics.forwardedCapsuleHeight + columnGap
        }

        if let replyTo = message.replyToId {
            let isSingleEmojiForReply = checkSingleEmoji(displayText.trimmingCharacters(in: .whitespaces))
            let replyContentWidth = Self.bubbleContentWidthForReply(
                kind: kind,
                displayContent: displayText,
                isSingleEmoji: isSingleEmojiForReply,
                showingTranslation: showingTranslation,
                mentionedUserNames: mentionedUserNames
            )
            h += Self.measureReplyPreviewHeight(replyTo: replyTo, availableContentWidth: replyContentWidth)
                + MessageCellMetrics.contentStackSpacing
        }

        switch kind {
        case .text, .unknown:
            let raw = displayText
            if raw.isEmpty {
                h += MessageCellMetrics.bodyMinH
            } else {
                let isSingle = checkSingleEmoji(raw.trimmingCharacters(in: .whitespaces))
                if isSingle {
                    let textH = ceil(raw.boundingRect(
                        with: CGSize(width: maxBubbleContentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: MessageCellMetrics.emojiFont],
                        context: nil).height)
                    h += max(textH + MessageCellMetrics.bodyBufferBot, MessageCellMetrics.bodyMinH)
                } else {
                    let textAttr = Self.measureAttributedText(raw, mentions: mentionedUserNames)
                    let textH = ceil(textAttr.boundingRect(
                        with: CGSize(width: maxBubbleContentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil).height)
                    h += max(textH + MessageCellMetrics.bodyBufferBot, MessageCellMetrics.bodyMinH)
                }
            }

            if showingTranslation {
                h += MessageCellMetrics.translationGlobeSize + MessageCellMetrics.translationRowGap
            }

        case .image:
            h += MessageCellMetrics.imageVideoContentHeight

        case .video:
            h += MessageCellMetrics.imageVideoContentHeight

        case .audio:
            // audioContainer: 8 top + playButton(50) + 8 bottom = 66
            h += 66

        case .contact:
            // icon(36) + text rows(name ~18 + phone ~16) + padding(12) = 48
            h += 48

        case .poll:
            let poll = message.poll
            let options = poll?.options ?? []
            let optionCount = options.count

            let qFont = UIFont(name: "Fredoka-Medium", size: 16) ?? UIFont.chat(.medium, size: 16)
            let oFont = UIFont(name: "Fredoka-Regular", size: 15) ?? UIFont.chat(size: 15)

            let questionWidth = maxBubbleContentWidth - 4
            let optionTextWidth = max(maxBubbleContentWidth - 123, 50)

            var pollH: CGFloat = 14 + 20 + 10

            let qText = poll?.question ?? ""
            let qH: CGFloat = qText.isEmpty ? 20 : ceil(qText.boundingRect(
                with: CGSize(width: questionWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: qFont],
                context: nil).height)
            pollH += max(qH, 20) + 16

            for i in 0..<optionCount {
                let oText = options[i].text
                let oH: CGFloat = oText.isEmpty ? 20 : ceil(oText.boundingRect(
                    with: CGSize(width: optionTextWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: oFont],
                    context: nil).height)
                pollH += max(oH, 20) + 20
                if i < optionCount - 1 { pollH += 8 }
            }

            pollH += 12 + 20 + 14
            h += pollH

        case .location:
            h += MessageCellMetrics.locationMapHeight + 76

        case .post:
            let postBubbleW = ceil(screenWidth * MessageCellMetrics.sharedContentRatio)
            var postContent: CGFloat = 8 + 24 + 8 + 1 + postBubbleW
            let captionText = (
                message.sharedPost?.caption
                ?? message.sharedContentInfo?.caption
                ?? message.post?.caption
                ?? ConversationMessage.captionFromSharedPreview(message.content)
                ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !captionText.isEmpty {
                postContent += 8 + 30 + 10
            } else {
                postContent += 10
            }
            h += postContent

        case .vibe:
            let vibeBubbleW = ceil(screenWidth * MessageCellMetrics.sharedContentRatio)
            let textWidth = max(vibeBubbleW - (MessageCellMetrics.vibeCardPadH * 2), 50)
            let caption = message.sharedCaptionPlainText
            let font = MessageCellMetrics.vibeBodyFont
            let measured = caption.isEmpty ? font.lineHeight : ceil(caption.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height)
            let maxTextH = ceil(font.lineHeight) * CGFloat(MessageCellMetrics.vibeMaxLines)
            let textH = min(max(measured, ceil(font.lineHeight)), maxTextH)
            h += MessageCellMetrics.vibeCardPadTop
                + MessageCellMetrics.vibeHeaderAvatar
                + MessageCellMetrics.vibeHeaderToBody
                + textH
                + MessageCellMetrics.vibeCardPadBottom

        case .reel:
            let reelBubbleW = ceil(screenWidth * MessageCellMetrics.sharedContentRatio)
            h += ceil(reelBubbleW * MessageCellMetrics.reelAspect)

        case .story:
            let storyBubbleW = ceil(screenWidth * MessageCellMetrics.sharedContentRatio)
            let storyImageH = floor((storyBubbleW - 20) * MessageCellMetrics.storyAspect)
            h += 8 + 24 + 8 + storyImageH + 8 + 40 + 8

        case .deleted:
            h += MessageCellMetrics.bodyMinH

        case .system:
            break
        }

        if hasReactions {
            h += MessageCellMetrics.reactionPillHeight
                + MessageCellMetrics.reactionBubbleOverlap
                + MessageCellMetrics.reactionPostGap
        }

        return ceil(h)
    }

    static func computeBubbleWidth(
        kind: MessageKind,
        displayContent: String,
        isSingleEmoji: Bool,
        hasReply: Bool,
        showingTranslation: Bool,
        mentionedUserNames: Set<String>
    ) -> CGFloat {
        let screenW = screenWidth
        let maxBW = floor(screenW * MessageCellMetrics.maxBubbleWidthRatio)

        switch kind {
        case .text, .unknown, .deleted:
            if isSingleEmoji && !hasReply { return MessageCellMetrics.minTextBubbleWidth }
            if isSingleEmoji { return MessageCellMetrics.minReplyBubbleWidth }
            let constraintW = maxBW - (MessageCellMetrics.textProfilePadH * 2)
            let attrText = measureAttributedText(
                displayContent.trimmingCharacters(in: .whitespaces),
                mentions: mentionedUserNames
            )
            let textW = ceil(attrText.boundingRect(
                with: CGSize(width: constraintW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).width)
            var translationMinW: CGFloat = 0
            if showingTranslation {
                let translatedStr = ChatStrings.chat_translated.localizedString()
                let translatedW = ceil((translatedStr as NSString).size(withAttributes: [
                    .font: MessageCellMetrics.translationLabelFont
                ]).width)
                translationMinW = MessageCellMetrics.translationGlobeSize
                    + MessageCellMetrics.translationRowGap
                    + translatedW
            }
            let replyMinW: CGFloat = hasReply ? MessageCellMetrics.minReplyBubbleWidth : 0
            return min(
                max(textW + (MessageCellMetrics.textProfilePadH * 2),
                    replyMinW,
                    MessageCellMetrics.minTextBubbleWidth,
                    translationMinW + (MessageCellMetrics.textProfilePadH * 2)),
                maxBW
            )

        case .image, .video:
            return MessageCellMetrics.imageVideoBubbleWidth

        case .audio:
            return MessageCellMetrics.audioBubbleWidth

        case .contact:
            return MessageCellMetrics.contactBubbleWidth

        case .poll, .location:
            return maxBW

        case .post, .vibe, .reel, .story:
            return screenW * MessageCellMetrics.sharedContentRatio

        case .system:
            return maxBW * 0.75
        }
    }

    private static func bubbleContentWidthForReply(
        kind: MessageKind,
        displayContent: String,
        isSingleEmoji: Bool,
        showingTranslation: Bool,
        mentionedUserNames: Set<String>
    ) -> CGFloat {
        let bubbleW = computeBubbleWidth(
            kind: kind,
            displayContent: displayContent,
            isSingleEmoji: isSingleEmoji,
            hasReply: true,
            showingTranslation: showingTranslation,
            mentionedUserNames: mentionedUserNames
        )
        let insets: CGFloat
        switch kind {
        case .text, .unknown, .deleted:
            insets = MessageCellMetrics.textProfilePadH * 2
        default:
            insets = MessageCellMetrics.mediaReplyBubblePadH * 2
        }
        return max(bubbleW - insets, 0)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stableId)
        hasher.combine(kind)
        hasher.combine(displayContent)
        hasher.combine(isShowingTranslation)
        hasher.combine(deliveryStatus)
        hasher.combine(isUploading)
        hasher.combine(isPinned)
        hasher.combine(isEdited)
        hasher.combine(isDeletedState)
        hasher.combine(reactions)
        hasher.combine(mediaItems)
        hasher.combine(mentionedUserNames)
        hasher.combine(pollData)
    }

    static func == (lhs: MessageCellModel, rhs: MessageCellModel) -> Bool {
        lhs.stableId == rhs.stableId
            && lhs.kind == rhs.kind
            && lhs.displayContent == rhs.displayContent
            && lhs.isShowingTranslation == rhs.isShowingTranslation
            && lhs.deliveryStatus == rhs.deliveryStatus
            && lhs.isUploading == rhs.isUploading
            && lhs.isPinned == rhs.isPinned
            && lhs.isEdited == rhs.isEdited
            && lhs.isDeletedState == rhs.isDeletedState
            && lhs.reactions == rhs.reactions
            && lhs.mediaItems == rhs.mediaItems
            && lhs.mentionedUserNames == rhs.mentionedUserNames
            && lhs.pollData == rhs.pollData
    }

    private static func measureReplyPreviewHeight(
        replyTo: ReplyToMessage,
        availableContentWidth: CGFloat
    ) -> CGFloat {
        let replyContent = replyTo.content ?? ""
        let rawType = (replyTo.type ?? "").lowercased()
        let typeName = ConversationMessage.messageTypeDisplayName(rawType)

        let previewText: String
        if typeName.isEmpty || typeName == ChatStrings.chat_message.localizedString() {
            previewText = replyContent.isEmpty ? "" : String(replyContent.prefix(200))
        } else {
            previewText = typeName
        }

        let hasThumbnail = ["image", "video", "reel", "post", "story"].contains(rawType)
        let hasTypeIcon = !["text", ""].contains(rawType)

        let accentArea = MessageCellMetrics.replyAccentBarLeading
            + MessageCellMetrics.replyAccentBarWidth
            + MessageCellMetrics.replyAccentToContentGap
            + MessageCellMetrics.replyContentRowTrailing
        var textWidth = max(availableContentWidth - accentArea, 0)
        if hasThumbnail {
            textWidth -= MessageCellMetrics.replyThumbnailSize + MessageCellMetrics.replyContentRowSpacing
        }
        if hasTypeIcon {
            textWidth -= MessageCellMetrics.replyTypeIconSize + MessageCellMetrics.replyBodyRowSpacing
        }

        let senderH: CGFloat = MessageCellMetrics.replySenderLineHeight
        let maxBodyH: CGFloat = CGFloat(MessageCellMetrics.replyMaxBodyLines) * MessageCellMetrics.replyContentLineHeight

        let bodyH: CGFloat
        if previewText.isEmpty {
            bodyH = 0
        } else {
            let measured = ceil(previewText.boundingRect(
                with: CGSize(width: max(textWidth, 50), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: MessageCellMetrics.replyContentFont],
                context: nil).height)
            bodyH = min(measured, maxBodyH)
        }

        let textStackH = senderH + MessageCellMetrics.replyRowSpacing + bodyH
        let contentFloor: CGFloat = hasThumbnail ? MessageCellMetrics.replyThumbnailSize : 0
        let containerH = max(textStackH, contentFloor)
            + MessageCellMetrics.replyContentRowPadV * 2
        return ceil(containerH)
    }

    private static let mentionTokenRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "(?<![\\w])@([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*)", options: [])

    /// Collects @mention usernames for cache keys / taps.
    /// Always parses `@username` from visible text so group bubbles stay bold even when
    /// participant usernames don't match metadata (common after REST / incomplete members).
    private static func resolveMentionedUserNames(
        from message: ConversationMessage,
        displayText: String,
        participants: [GroupParticipant]
    ) -> Set<String> {
        var names = Set<String>()

        // 1) Metadata userIds → participant usernames (when both are available)
        if let mentionsEntry = message.metadata?["mentions"], !participants.isEmpty {
            let mentionIds: [String]
            if let ids = mentionsEntry.value as? [String] {
                mentionIds = ids
            } else if let anyArray = mentionsEntry.jsonCompatibleValue as? [Any] {
                mentionIds = anyArray.compactMap { $0 as? String }
            } else {
                mentionIds = []
            }
            if !mentionIds.isEmpty {
                let mentionedUserIds = Set(mentionIds)
                for p in participants where mentionedUserIds.contains(p.userId) {
                    let name = p.userName.lowercased()
                    if !name.isEmpty { names.insert(name) }
                }
                if !names.isEmpty {
                    names.insert("all")
                }
            }
        }

        // 2) Always parse @tokens from visible text (source of truth for bold rendering)
        let text = displayText.isEmpty
            ? (message.originalContentForDisplay.isEmpty
               ? (message.content ?? "")
               : message.originalContentForDisplay)
            : displayText
        guard !text.isEmpty, let regex = mentionTokenRegex else { return names }

        let nsRange = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: nsRange) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            names.insert(String(text[nameRange]).lowercased())
        }

        return names
    }
}

// MARK: - Delivery Status

enum DeliveryStatus: Equatable, Hashable {
    case sending
    case sent
    case delivered
    case read
    case failed

    static func from(message: ConversationMessage, currentUserId: String?) -> DeliveryStatus {
        switch message.deliveryStatus {
        case .sending:  return .sending
        case .sent:     return .sent
        case .delivered: return .delivered
        case .read:     return .read
        case .failed:   return .failed
        case .unknown:  break
        }
        // Fallback for unknown / non-outgoing messages
        guard message.senderId == currentUserId else { return .sent }
        // Prefer sent over sending when status is unknown — avoids delete-only options sheet
        // and clock ticks on already-delivered server messages.
        if message.isOptimisticTemporary { return .sending }
        return .sent
    }

    var icon: UIImage? {
        switch self {
        case .sending:  return UIImage(systemName: "clock")
        case .sent:     return UIImage(named: ChatAssets.tickSent)?.withRenderingMode(.alwaysTemplate)
        case .delivered: return UIImage(named: ChatAssets.tickDelivered)?.withRenderingMode(.alwaysTemplate)
        case .read:     return UIImage(named: ChatAssets.tickRead)?.withRenderingMode(.alwaysTemplate)
        case .failed:   return UIImage(systemName: "exclamationmark.circle")
        }
    }

    var tintColor: UIColor {
        switch self {
        case .sending:  return ChatTheme.primary
        case .sent:     return ChatTheme.timeOutgoing
        case .delivered: return ChatTheme.timeOutgoing
        case .read:     return ChatTheme.readReceipt
        case .failed:   return UIColor.systemRed
        }
    }
}

// MARK: - Reply Preview Model

struct ReplyPreviewModel: Hashable {
    let messageId: String
    let senderName: String
    let content: String
    let thumbnailURL: String?
    /// Normalised type: "text" | "image" | "video" | "audio" | "post" | "reel" | "story" | "poll" | "location"
    let messageType: String

    var isVideo: Bool { messageType == "video" || messageType == "reel" }

    static func from(_ reply: ReplyToMessage) -> ReplyPreviewModel {
        let name = reply.sender.fullName ?? reply.sender.userName ?? "Unknown"

        // Resolve message type
        let rawType = (reply.type ?? "").lowercased()
        let messageType: String
        if !rawType.isEmpty && rawType != "unknown" {
            messageType = rawType
        } else if reply.poll != nil {
            messageType = "poll"
        } else if reply.location != nil {
            messageType = "location"
        } else if let first = reply.media?.first {
            let url  = (first.url  ?? "").lowercased()
            let type = (first.type ?? "").lowercased()
            if type == "video" || url.hasSuffix(".mp4") || url.hasSuffix(".mov") || url.hasSuffix(".m4v") {
                messageType = "video"
            } else {
                messageType = "image"
            }
        } else {
            messageType = "text"
        }

        let content   = reply.content ?? ""

        // Reel, post, story: no thumbnail in reply preview
        let showThumbnail: Bool
        switch messageType {
        case "reel", "post", "story":
            showThumbnail = false
        default:
            showThumbnail = true
        }
        let thumbnail = showThumbnail
            ? (reply.thumbnail ?? reply.media?.first?.thumbnail ?? reply.media?.first?.url)
            : nil

        return ReplyPreviewModel(
            messageId: reply.id ?? "",
            senderName: name,
            content: String(content.prefix(200)),
            thumbnailURL: thumbnail,
            messageType: messageType
        )
    }
}

// MARK: - Media Item Model

struct MediaItemModel: Hashable {
    let id: String
    let url: String?
    let thumbnailURL: String?
    let type: String?
    let fileName: String?
    let fileSize: Int?
    let duration: Double?

    static func from(_ media: ConversationMedia, fallbackId: String = "") -> MediaItemModel {
        let resolvedId: String
        if let id = media.id, !id.isEmpty {
            resolvedId = id
        } else if let url = media.url, !url.isEmpty {
            resolvedId = url
        } else {
            resolvedId = fallbackId
        }
        return MediaItemModel(
            id: resolvedId,
            url: media.url,
            thumbnailURL: media.thumbnail,
            type: media.type,
            fileName: media.fileName,
            fileSize: media.fileSize,
            duration: media.duration
        )
    }

    var isVideo: Bool {
        let normalizedType = (type ?? "").lowercased()
        if normalizedType == "audio" || normalizedType == "voice" { return false }
        if normalizedType == "video" { return true }
        let ext = (url ?? fileName ?? "").lowercased()
        return ext.hasSuffix(".mp4") || ext.hasSuffix(".mov") || ext.hasSuffix(".m4v")
    }

    var isImage: Bool {
        if isVideo { return false }
        let normalizedType = (type ?? "").lowercased()
        if normalizedType == "image" || normalizedType == "photo" { return true }
        let ext = (url ?? fileName ?? "").lowercased()
        return ext.hasSuffix(".jpg") || ext.hasSuffix(".jpeg") || ext.hasSuffix(".png") || ext.hasSuffix(".webp")
    }
}

// MARK: - Date Section

struct ChatDateSection: Hashable {
    let date: String
    let displayText: String

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM dd, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func displayText(for dateStr: String) -> String {
        guard let date = isoFormatter.date(from: dateStr) else { return dateStr }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return ChatStrings.chat_today.localizedString() }
        if calendar.isDateInYesterday(date) { return ChatStrings.chat_yesterday.localizedString() }

        return displayFormatter.string(from: date)
    }
}

// MARK: - UIColor Extension

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
