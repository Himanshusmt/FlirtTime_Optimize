//
//  ChatTheme.swift
//  FlirttimeNew
//

import SwiftUI
import UIKit

/// Chat and calling design tokens, derived from FlirtTime's `AppColor` palette and Fredoka type.
enum ChatTheme {
    // MARK: Brand
    static let primary = AppColor.Punch
    static let primaryDark = AppColor.MexicanRed
    static let primaryLight = AppColor.Carnation
    static let primarySoft = AppColor.Lavenderblush

    // MARK: Text
    static let textPrimary = AppColor.MineShaft
    static let textSecondary = AppColor.DoveGray
    static let textTertiary = AppColor.SilverChalice
    static let textOnPrimary = AppColor.AppWhite

    // MARK: Surfaces
    static let background = AppColor.AppWhite
    static let surface = AppColor.WildSand
    static let surfaceAlt = AppColor.AthensGray
    static let separator = AppColor.Gallery

    // MARK: Bubbles
    static let outgoingBubble = AppColor.Punch
    static let incomingBubble = AppColor.Serenade
    static let incomingText = AppColor.MineShaft
    static let outgoingText = AppColor.AppWhite
    static let replyAccent = AppColor.Carnation
    static let timeOutgoing = AppColor.Punch
    static let timeIncoming = AppColor.SilverChalice
    static let datePill = AppColor.AthensGray
    static let datePillText = AppColor.DoveGray

    // MARK: Status
    static let error = AppColor.AlertBottomFailure
    static let success = AppColor.OceanGreen
    static let warning = AppColor.BrightSun
    static let link = AppColor.BlueRibbon
    static let readReceipt = AppColor.Punch

    /// Avatar gradients for users without a profile picture.
    static let avatarGradients: [[UIColor]] = [
        [AppColor.Punch, AppColor.MexicanRed],
        [AppColor.Carnation, AppColor.Amaranth],
        [AppColor.Portage, AppColor.ElectricViolet],
        [AppColor.DodgerBlue, AppColor.BlueRibbon],
        [AppColor.SeaPinkish, AppColor.Punch],
        [AppColor.BrightSun, AppColor.Carnation],
        [AppColor.OceanGreen, AppColor.CongressBlue],
        [AppColor.SeaPink, AppColor.Cherrywood]
    ]
}

// MARK: - SwiftUI colors

extension Color {
    static let chatPrimary = Color(uiColor: ChatTheme.primary)
    static let chatPrimaryDark = Color(uiColor: ChatTheme.primaryDark)
    static let chatPrimaryLight = Color(uiColor: ChatTheme.primaryLight)
    static let chatPrimarySoft = Color(uiColor: ChatTheme.primarySoft)
    static let chatTextPrimary = Color(uiColor: ChatTheme.textPrimary)
    static let chatTextSecondary = Color(uiColor: ChatTheme.textSecondary)
    static let chatTextTertiary = Color(uiColor: ChatTheme.textTertiary)
    static let chatBackground = Color(uiColor: ChatTheme.background)
    static let chatSurface = Color(uiColor: ChatTheme.surface)
    static let chatSurfaceAlt = Color(uiColor: ChatTheme.surfaceAlt)
    static let chatSeparator = Color(uiColor: ChatTheme.separator)
    static let chatError = Color(uiColor: ChatTheme.error)
    static let chatSuccess = Color(uiColor: ChatTheme.success)
    static let chatWarning = Color(uiColor: ChatTheme.warning)
    static let chatLink = Color(uiColor: ChatTheme.link)
}

// MARK: - Fonts

private enum ChatFontName {
    static let regular = "Fredoka-Regular"
    static let medium = "Fredoka-Medium"
    static let semibold = "Fredoka-SemiBold"

    static func name(for weight: UIFont.Weight) -> String {
        if weight >= .semibold { return semibold }
        if weight >= .medium { return medium }
        return regular
    }

    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .medium: return medium
        case .semibold, .bold, .heavy, .black: return semibold
        default: return regular
        }
    }
}

extension UIFont {
    static func chat(_ weight: UIFont.Weight = .regular, size: CGFloat) -> UIFont {
        UIFont(name: ChatFontName.name(for: weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func chatRegular(size: CGFloat) -> UIFont { chat(.regular, size: size) }
    static func chatMedium(size: CGFloat) -> UIFont { chat(.medium, size: size) }
    static func chatSemiBold(size: CGFloat) -> UIFont { chat(.semibold, size: size) }
    static func chatBold(size: CGFloat) -> UIFont { chat(.bold, size: size) }
}

extension Font {
    static func chat(_ weight: Font.Weight = .regular, size: CGFloat) -> Font {
        .custom(ChatFontName.name(for: weight), size: size)
    }

    static func chatRegular(size: CGFloat) -> Font { chat(.regular, size: size) }
    static func chatMedium(size: CGFloat) -> Font { chat(.medium, size: size) }
    static func chatSemiBold(size: CGFloat) -> Font { chat(.semibold, size: size) }
    static func chatBold(size: CGFloat) -> Font { chat(.bold, size: size) }
}
