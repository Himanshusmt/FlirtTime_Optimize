import UIKit

enum MessageCellMetrics {
    static let cellPadTop: CGFloat = 4
    static let cellPadBottom: CGFloat = 4
    static let cellHorizontalInset: CGFloat = 12
    static let outgoingLeadingMin: CGFloat = 40
    static let lineSpacing: CGFloat = 4

    static let textProfilePadTop: CGFloat = 10
    static let textProfilePadBottom: CGFloat = 10
    static let textProfilePadH: CGFloat = 12
    static let mediaProfilePadTop: CGFloat = 0
    static let mediaProfilePadBottom: CGFloat = 0
    static let mediaProfilePadH: CGFloat = 0

    static let columnSpacing: CGFloat = 4
    static let contentStackSpacing: CGFloat = 8

    static let senderNameFont: UIFont = UIFont.chat(.semibold, size: 12)
    static let senderNameLineHeight: CGFloat = 14
    /// Header row height for group sender name only
    static var senderHeaderHeight: CGFloat { senderNameLineHeight }

    static let pinnedCapsulePadV: CGFloat = 3
    static let pinnedCapsulePadH: CGFloat = 8
    static let pinnedIconSize: CGFloat = 8
    static let pinnedLabelFont: UIFont = UIFont.chat(size: 10)
    static let pinnedCapsuleHeight: CGFloat = 18

    static let forwardedCapsulePadV: CGFloat = 4
    static let forwardedCapsulePadH: CGFloat = 8
    static let forwardedIconSize: CGFloat = 10
    static let forwardedLabelFont: UIFont = UIFont.chat(size: 11)
    static let forwardedCapsuleHeight: CGFloat = 22

    static let replyAccentBarLeading: CGFloat = 5
    static let replyAccentBarWidth: CGFloat = 3
    static let replyAccentBarPadV: CGFloat = 5
    static let replyContentRowPadV: CGFloat = 6
    static let replyContentRowTrailing: CGFloat = 6
    static let replyAccentToContentGap: CGFloat = 8
    static let replyThumbnailSize: CGFloat = 48
    static let replyTypeIconSize: CGFloat = 12
    static let replyRowSpacing: CGFloat = 2
    static let replyBodyRowSpacing: CGFloat = 4
    static let replyContentRowSpacing: CGFloat = 8
    static let replySenderFont: UIFont = UIFont.chat(.semibold, size: 11)
    static let replyContentFont: UIFont = UIFont.chat(size: 11)
    static let replySenderLineHeight: CGFloat = 15
    static let replyContentLineHeight: CGFloat = 15
    static let replyMaxBodyLines: Int = 3

    static let footerHeight: CGFloat = 14
    static let footerInternalSpacing: CGFloat = 4
    static let timeFont: UIFont = UIFont.chat(size: 11)
    static let editedFont: UIFont = UIFont.chat(size: 9)
    static let statusIconWidth: CGFloat = 16
    static let statusIconSize: CGFloat = 13

    static let reactionPillHeight: CGFloat = 22
    static let reactionBubbleOverlap: CGFloat = -10
    static let reactionPostGap: CGFloat = 4

    static let translationGlobeSize: CGFloat = 11
    static let translationLabelFont: UIFont = UIFont.chat(size: 10)
    static let translationRowGap: CGFloat = 3
    static let translationExtraWidth: CGFloat = 24

    static let bodyFont: UIFont = UIFont(name: "Fredoka-Regular", size: 16) ?? UIFont.chat(size: 16)
    static let bodyBoldFont: UIFont = UIFont(name: "Fredoka-SemiBold", size: 16)
        ?? UIFont(name: "Fredoka-SemiBold", size: 16)
        ?? UIFont.chat(.bold, size: 16)
    static let bodyLineSpacing: CGFloat = 3
    static let bodyBufferBot: CGFloat = 2
    static let bodyMinH: CGFloat = 20

    static let emojiFont: UIFont = UIFont.chat(size: 42)

    static let maxBubbleWidthRatio: CGFloat = 0.72
    static let minTextBubbleWidth: CGFloat = 60
    static let minReplyBubbleWidth: CGFloat = 180
    static let deletedMinBubbleWidth: CGFloat = 80
    static let mediaReplyBubblePadH: CGFloat = 8
    static let imageVideoBubbleWidth: CGFloat = 200
    static let imageVideoContentHeight: CGFloat = 250
    static let audioBubbleWidth: CGFloat = 306
    static let contactBubbleWidth: CGFloat = 220
    static let locationMapHeight: CGFloat = 180
    static let sharedContentRatio: CGFloat = 0.54
    static let reelAspect: CGFloat = 1.25
    static let storyAspect: CGFloat = 0.9

    static let vibeBodyFont: UIFont = UIFont(name: "Fredoka-SemiBold", size: 16)
        ?? UIFont.chat(.bold, size: 16)
    static let vibeMaxLines: Int = 3
    static let vibeHeaderAvatar: CGFloat = 24
    static let vibeCardPadH: CGFloat = 12
    static let vibeCardPadTop: CGFloat = 10
    static let vibeCardPadBottom: CGFloat = 12
    static let vibeHeaderToBody: CGFloat = 8

    static let maxCollapsedLines: Int = 10
    static let readMoreExtraHeight: CGFloat = 28
}
