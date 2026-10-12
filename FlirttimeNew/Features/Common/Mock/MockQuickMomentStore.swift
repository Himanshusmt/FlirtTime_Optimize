//
//  MockQuickMomentStore.swift
//  FlirttimeNew
//
//  Local stand-in for the Quick Moments endpoints. State is persisted to disk and returned in
//  the server response models, so the view model can switch to the API without UI changes.
//

import UIKit

final class MockQuickMomentStore {

    static let shared = MockQuickMomentStore()

    static let maxTextLength = 200

    private let fileURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("mock_quick_moments_v1.json")

    private var moments: [QuickMoment]

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([QuickMoment].self, from: data) {
            moments = saved
        } else {
            moments = MockQuickMomentStore.seed()
        }
    }

    // MARK: - Endpoints

    func list(userID: String) -> QuickMomentListResponse {
        let rows = moments.filter { $0.userId == userID }.sorted {
            (VibeDate.date(from: $0.createdAt) ?? .distantPast) > (VibeDate.date(from: $1.createdAt) ?? .distantPast)
        }
        return QuickMomentListResponse(success: true, message: "", data: rows)
    }

    func create(text: String?, background: Int?, image: UIImage?) -> CreateQuickMomentResponse {
        var mediaPath: String?
        if let image {
            guard let name = LocalImageStore.shared.save(image) else {
                return CreateQuickMomentResponse(success: false, message: "Unable to upload photo", data: nil)
            }
            mediaPath = name
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.map { String($0.prefix(MockQuickMomentStore.maxTextLength)) }
        guard mediaPath != nil || body?.isEmpty == false else {
            return CreateQuickMomentResponse(success: false, message: "Add a photo or write something", data: nil)
        }
        let moment = QuickMoment(id: UUID().uuidString,
                                 userId: MockVibeStore.shared.currentUserID,
                                 mediaPath: mediaPath,
                                 text: body?.isEmpty == false ? body : nil,
                                 background: mediaPath == nil ? background : nil,
                                 createdAt: VibeDate.string(from: Date()),
                                 reactions: [],
                                 replies: [])
        moments.append(moment)
        persist()
        return CreateQuickMomentResponse(success: true, message: "Quick moment shared", data: moment)
    }

    func delete(id: String) -> VibeActionResponse {
        guard let index = moments.firstIndex(where: { $0.id == id }) else {
            return VibeActionResponse(success: false, message: "Quick moment not found")
        }
        guard moments[index].userId == MockVibeStore.shared.currentUserID else {
            return VibeActionResponse(success: false, message: "You can only delete your own quick moments")
        }
        let removed = moments.remove(at: index)
        persist()
        if let path = removed.mediaPath { LocalImageStore.shared.remove(path) }
        return VibeActionResponse(success: true, message: "Quick moment deleted")
    }

    func reset() {
        moments = MockQuickMomentStore.seed()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private func persist() {
        guard let data = try? JSONEncoder().encode(moments) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func timestamp(minutesAgo: Int) -> String {
        VibeDate.string(from: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }

    private static func author(_ id: Int) -> VibeAuthor? {
        guard let person = MockPeople.person(id: id) else { return nil }
        return VibeAuthor(userId: String(person.id), userName: person.displayName, fullName: person.fullname,
                          profilePicture: person.photos.first, verified: person.isVerified, location: person.location)
    }

    private static func seed() -> [QuickMoment] {
        let me = MockVibeStore.shared.currentUserID
        let seeds: [(media: String?, text: String?, background: Int?, minutesAgo: Int,
                     reactions: [(Int, String)], replies: [(Int, String)])] = [
            (nil, "Who's up for coffee this evening? ☕️", 1, 20,
             [(101, "😍"), (103, "🔥"), (105, "😍")], [(101, "Me! Name the place ☕️"), (104, "Only if it's cold brew 😄")]),
            ("mock-me-moment-2", "Sunrise hike done ⛰️", nil, 140,
             [(102, "🔥"), (106, "👏")], [(103, "Which trail was this? Looks amazing")]),
            ("mock-me-moment-3", "Meet my weekend buddy 🐱", nil, 380,
             [(107, "😍"), (101, "❤️"), (104, "😂"), (108, "😍")], [])
        ]
        return seeds.enumerated().map { index, seed in
            let id = "qm-own-\(index + 1)"
            return QuickMoment(
                id: id,
                userId: me,
                mediaPath: seed.media,
                text: seed.text,
                background: seed.background,
                createdAt: timestamp(minutesAgo: seed.minutesAgo),
                reactions: seed.reactions.enumerated().compactMap { offset, reaction in
                    QuickMomentReaction(id: "\(id)-r\(offset + 1)", emoji: reaction.1,
                                        createdAt: timestamp(minutesAgo: max(seed.minutesAgo - (offset + 1) * 4, 1)),
                                        author: author(reaction.0))
                },
                replies: seed.replies.enumerated().compactMap { offset, reply in
                    QuickMomentReply(id: "\(id)-c\(offset + 1)", body: reply.1,
                                     createdAt: timestamp(minutesAgo: max(seed.minutesAgo - (offset + 1) * 6, 1)),
                                     author: author(reply.0))
                })
        }
    }
}
