//
//  MentionManager.swift
//  FlirttimeNew
//
//  Created on 09/04/26.
//

import SwiftUI

class MentionManager: ObservableObject {
    @Published var mentionQuery: String? = nil
    @Published var filteredParticipants: [GroupParticipant] = []

    var isGroupChat: Bool = false {
        didSet { updateFiltered() }
    }

    var allParticipants: [GroupParticipant] = [] {
        didSet { updateFiltered() }
    }

    var currentMentionRange: Range<String.Index>?

    // Sentinel participant representing "notify all members"
    static let allParticipant = GroupParticipant(
        id: "all",
        userId: "all",
        role: "",
        userName: "all",
        fullName: "All Members",
        profilePicture: nil
    )

    func updateQuery(_ query: String?, range: Range<String.Index>?) {
        if let query = query {
            mentionQuery = query
            currentMentionRange = range
            updateFiltered()
        } else {
            dismiss()
        }
    }

    /// Returns the text to insert and the range to replace when a participant is selected.
    func selectParticipant(_ participant: GroupParticipant) -> (text: String, replacingRange: Range<String.Index>?)? {
        guard let range = currentMentionRange else { return nil }
        let insertion = "@\(participant.userName) "
        return (text: insertion, replacingRange: range)
    }

    func dismiss() {
        mentionQuery = nil
        filteredParticipants = []
        currentMentionRange = nil
    }

    func buildMentionsMetadata(for text: String) -> [String] {
        guard isGroupChat, !allParticipants.isEmpty else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)

        // @all takes priority — return every participant's userId.
        let allPattern = "(?<![\\w])@all(?![\\w])"
        if (try? NSRegularExpression(pattern: allPattern, options: .caseInsensitive))?
            .firstMatch(in: text, range: nsRange) != nil {
            return allParticipants.map { $0.userId }
        }

        // Resolve individual @username mentions.
        guard let regex = try? NSRegularExpression(pattern: "@(\\w+)") else { return [] }
        let matches = regex.matches(in: text, options: [], range: nsRange)
        let userNameMap = Dictionary(uniqueKeysWithValues:
            allParticipants.map { ($0.userName.lowercased(), $0.userId) })
        var ids: [String] = []
        for match in matches {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[r]).lowercased()
            if let uid = userNameMap[name], !ids.contains(uid) {
                ids.append(uid)
            }
        }
        return ids
    }

    func buildSocketMentions(for text: String) -> [String] {
        guard isGroupChat, !allParticipants.isEmpty else { return [] }
        let pattern = "(?<![\\w])@all(?![\\w])"
        let nsRange = NSRange(text.startIndex..., in: text)
        if (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?
            .firstMatch(in: text, range: nsRange) != nil {
            return allParticipants.map { $0.userId }
        }
        return []
    }

    private func updateFiltered() {
        guard let query = mentionQuery, !query.isEmpty else {
            if isGroupChat {
                filteredParticipants = [Self.allParticipant] + allParticipants
            } else {
                filteredParticipants = allParticipants
            }
            return
        }
        let lowerQuery = query.lowercased()
        var results: [GroupParticipant] = []
        if isGroupChat && "all".hasPrefix(lowerQuery) {
            results.append(Self.allParticipant)
        }
        let matches = allParticipants.filter { p in
            p.userName.lowercased().hasPrefix(lowerQuery) ||
            p.fullName.lowercased().hasPrefix(lowerQuery)
        }
        results.append(contentsOf: matches)
        filteredParticipants = results
    }
}
