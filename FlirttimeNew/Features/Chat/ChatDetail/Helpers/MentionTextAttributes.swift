//
//  MentionTextAttributes.swift
//  FlirttimeNew
//
//  Created on 09/04/26.
//

import SwiftUI

enum MentionTextAttributes {

    static func extractMentionQuery(text: String, cursorPosition: Int) -> (query: String, range: Range<String.Index>)? {
        guard cursorPosition > 0, cursorPosition <= text.count else { return nil }

        let startIndex = text.startIndex
        let cursorIndex = text.index(startIndex, offsetBy: cursorPosition)

        // Walk backwards from cursor to find '@'
        var currentIndex = cursorIndex
        var queryLength = 0

        while currentIndex > startIndex {
            let prevIndex = text.index(before: currentIndex)
            let char = text[prevIndex]

            if char == "@" {
                // Check character before '@' is valid (whitespace/start-of-string)
                if prevIndex == startIndex {
                    let range = prevIndex..<cursorIndex
                    let query = String(text[range]).dropFirst() // drop '@'
                    return (query: String(query), range: range)
                }
                let beforeAt = text.index(before: prevIndex)
                let charBefore = text[beforeAt]
                if charBefore.isWhitespace || charBefore == "\n" {
                    let range = prevIndex..<cursorIndex
                    let query = String(text[range]).dropFirst()
                    return (query: String(query), range: range)
                }
                return nil // '@' is mid-word (e.g., email)
            }

            if char.isWhitespace || char == "\n" {
                return nil // Hit whitespace before finding '@'
            }

            // Part of the query — keep walking back
            currentIndex = prevIndex
            queryLength += 1
        }

        return nil
    }

    static func buildAttributedContent(
        text: String,
        mentions: [String]?,
        groupParticipants: [GroupParticipant],
        baseColor: Color,
        isFromSelf: Bool = false
    ) -> AttributedString {
        guard let mentions = mentions, !mentions.isEmpty else {
            return AttributedString(text)
        }

        // Build a set of mentioned userIds
        let mentionedUserIds = Set(mentions)

        // Build a map of userName -> userId from participants
        var userNameToUserId: [String: String] = [:]
        for p in groupParticipants {
            userNameToUserId[p.userName.lowercased()] = p.userId
        }

        // Find all @word patterns
        let pattern = "@(\\w+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return AttributedString(text)
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        // Build attributed string — only set font on the whole string.
        // Color is handled by the parent Text view's .foregroundColor() modifier,
        // so non-mention text keeps the default color for that bubble type.
        var attributed = AttributedString(text)
        attributed.font = .chatRegular(size: 15)

        // Highlight ONLY the @username spans with a distinct color + bold.
        for match in matches.reversed() {
            guard let nsRange = Range(match.range(at: 0), in: text),
                  let userNameRange = Range(match.range(at: 1), in: text) else { continue }

            let userName = String(text[userNameRange]).lowercased()

            // Special case: @all is a broadcast — highlight whenever there are any mentions.
            let shouldHighlight: Bool
            if userName == "all" {
                shouldHighlight = !mentionedUserIds.isEmpty
            } else {
                guard let userId = userNameToUserId[userName],
                      mentionedUserIds.contains(userId) else { continue }
                shouldHighlight = true
            }
            guard shouldHighlight else { continue }

            // Convert String range to AttributedString range
            let lower = AttributedString.Index(nsRange.lowerBound, within: attributed)
            let upper = AttributedString.Index(nsRange.upperBound, within: attributed)
            guard let attrLower = lower, let attrUpper = upper else { continue }
            let attrRange = attrLower..<attrUpper

            var highlightAttributes = AttributeContainer()
            highlightAttributes.foregroundColor = isFromSelf ? Color.white : Color.chatPrimary
            highlightAttributes.font = .chatSemiBold(size: 15)

            attributed[attrRange].mergeAttributes(highlightAttributes)
        }

        return attributed
    }
}
