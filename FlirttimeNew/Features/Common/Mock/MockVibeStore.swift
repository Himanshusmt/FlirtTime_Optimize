//
//  MockVibeStore.swift
//  FlirttimeNew
//
//  Local stand-in for the OneVibe `vibes/` + `gifts/` endpoints used by the Home tab.
//  State is persisted to disk and returned in the server response models, so replacing a
//  mock view-model method with its API call needs no UI changes.
//

import UIKit

final class MockVibeStore {

    static let shared = MockVibeStore()

    static let maxCaptionLength = 1000
    static let maxImagesPerVibe = 5

    private struct State: Codable {
        var vibes: [Vibe]
        var comments: [String: [VibeComment]]
        var receivedGifts: [String: [VibeReceivedGift]]
        var coinBalance: Int
        /// Optional so files saved before reporting existed still decode.
        var reportedVibeIds: [String]?
    }

    private let fileURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("mock_vibes.json")

    private var state: State

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = MockVibeStore.seedState()
        }
    }

    // MARK: - Current user

    var currentUserID: String {
        String(MockDataStore.shared.currentUserID)
    }

    var currentUserAuthor: VibeAuthor {
        MockVibeStore.makeCurrentUserAuthor()
    }

    private static func makeCurrentUserAuthor() -> VibeAuthor {
        let info = MockDataStore.shared.currentUserResponse()?.data?.userInfo
        let name = info?.displayName ?? UserDataManager.shared.displayName ?? "You"
        return VibeAuthor(userId: String(MockDataStore.shared.currentUserID),
                          userName: name,
                          fullName: info?.fullname ?? name,
                          profilePicture: info?.avatar,
                          verified: info?.gestureIsVerified ?? false)
    }

    // MARK: - Feed

    func feed(page: Int, limit: Int) -> VibeFeedResponse {
        let reported = Set(state.reportedVibeIds ?? [])
        let sorted = state.vibes.filter { !reported.contains($0.id) }.sorted {
            (VibeDate.date(from: $0.createdAt) ?? .distantPast) > (VibeDate.date(from: $1.createdAt) ?? .distantPast)
        }
        let start = max(page - 1, 0) * limit
        let rows = start < sorted.count ? Array(sorted[start..<min(start + limit, sorted.count)]) : []
        let data = VibeFeedData(rows: rows, count: sorted.count, hasMore: start + rows.count < sorted.count, page: page, limit: limit)
        return VibeFeedResponse(success: true, message: "", data: data)
    }

    /// Stand-in for the per-image upload endpoint; returns the stored file name.
    func uploadImage(_ image: UIImage) -> String? {
        LocalImageStore.shared.save(image)
    }

    func createVibe(caption: String, imagePaths: [String]) -> CreateVibeResponse {
        let id = UUID().uuidString
        let media = imagePaths.prefix(MockVibeStore.maxImagesPerVibe).map {
            VibeMedia(id: UUID().uuidString, filePath: $0, fileType: "image")
        }
        let vibe = Vibe(id: id,
                        userId: currentUserID,
                        caption: String(caption.prefix(MockVibeStore.maxCaptionLength)),
                        media: media,
                        likesCount: 0,
                        commentsCount: 0,
                        giftCount: 0,
                        hasLiked: false,
                        createdAt: VibeDate.string(from: Date()),
                        author: currentUserAuthor)
        state.vibes.append(vibe)
        persist()
        return CreateVibeResponse(success: true, message: "Vibe posted successfully", data: vibe)
    }

    func deleteVibe(vibeId: String) -> VibeActionResponse {
        guard let index = state.vibes.firstIndex(where: { $0.id == vibeId }) else {
            return VibeActionResponse(success: false, message: "Vibe not found")
        }
        guard (state.vibes[index].author?.userId ?? state.vibes[index].userId) == currentUserID else {
            return VibeActionResponse(success: false, message: "You can only delete your own vibes")
        }
        let paths = state.vibes[index].media?.compactMap(\.filePath) ?? []
        state.vibes.remove(at: index)
        state.comments[vibeId] = nil
        state.receivedGifts[vibeId] = nil
        persist()
        paths.forEach { LocalImageStore.shared.remove($0) }
        return VibeActionResponse(success: true, message: "Vibe deleted")
    }

    func reportVibe(vibeId: String, reason: String) -> VibeActionResponse {
        guard state.vibes.contains(where: { $0.id == vibeId }) else {
            return VibeActionResponse(success: false, message: "Vibe not found")
        }
        var reported = state.reportedVibeIds ?? []
        if !reported.contains(vibeId) {
            reported.append(vibeId)
        }
        state.reportedVibeIds = reported
        persist()
        return VibeActionResponse(success: true, message: "Thanks for reporting. We'll review this vibe.")
    }

    // MARK: - Likes

    func setLike(vibeId: String, liked: Bool) -> VibeLikeResponse {
        guard let index = state.vibes.firstIndex(where: { $0.id == vibeId }) else {
            return VibeLikeResponse(success: false, message: "Vibe not found", data: nil)
        }
        if (state.vibes[index].hasLiked ?? false) != liked {
            let count = state.vibes[index].likesCount ?? 0
            state.vibes[index].likesCount = liked ? count + 1 : max(count - 1, 0)
            state.vibes[index].hasLiked = liked
            persist()
        }
        let vibe = state.vibes[index]
        return VibeLikeResponse(success: true, message: "", data: VibeLikeData(likesCount: vibe.likesCount, hasLiked: vibe.hasLiked))
    }

    // MARK: - Comments

    func comments(vibeId: String) -> VibeCommentListResponse {
        let rows = (state.comments[vibeId] ?? []).sorted {
            (VibeDate.date(from: $0.createdAt) ?? .distantPast) > (VibeDate.date(from: $1.createdAt) ?? .distantPast)
        }
        return VibeCommentListResponse(success: true, message: "", data: VibeCommentData(rows: rows, count: rows.count, hasMore: false))
    }

    func addComment(vibeId: String, body: String) -> CreateVibeCommentResponse {
        guard let index = state.vibes.firstIndex(where: { $0.id == vibeId }) else {
            return CreateVibeCommentResponse(success: false, message: "Vibe not found", data: nil)
        }
        let comment = VibeComment(id: UUID().uuidString,
                                  vibeId: vibeId,
                                  body: body,
                                  createdAt: VibeDate.string(from: Date()),
                                  author: currentUserAuthor)
        state.comments[vibeId, default: []].append(comment)
        state.vibes[index].commentsCount = state.comments[vibeId]?.count ?? 0
        persist()
        return CreateVibeCommentResponse(success: true, message: "Comment added", data: comment)
    }

    // MARK: - Gifts

    func giftCatalog() -> VibeGiftCatalogResponse {
        VibeGiftCatalogResponse(success: true, data: VibeGiftCatalogData(gifts: MockVibeStore.catalog, coinBalance: state.coinBalance))
    }

    func sendGifts(vibeId: String, giftIds: [Int]) -> VibeSendGiftResponse {
        guard let index = state.vibes.firstIndex(where: { $0.id == vibeId }) else {
            return VibeSendGiftResponse(success: false, message: "Vibe not found", data: nil)
        }
        let gifts = giftIds.compactMap { id in MockVibeStore.catalog.first { $0.id == id } }
        let total = gifts.reduce(0) { $0 + ($1.amount ?? 0) }
        guard total <= state.coinBalance else {
            return VibeSendGiftResponse(success: false,
                                        message: "Insufficient coin balance",
                                        data: VibeSendGiftData(giftCount: state.vibes[index].giftCount, coinBalance: state.coinBalance))
        }
        let sender = currentUserAuthor
        let now = VibeDate.string(from: Date())
        let received = gifts.map {
            VibeReceivedGift(id: UUID().uuidString, giftId: $0.id, coinsUsed: $0.amount, createdAt: now, gift: $0, sender: sender)
        }
        state.receivedGifts[vibeId, default: []].append(contentsOf: received)
        state.vibes[index].giftCount = (state.vibes[index].giftCount ?? 0) + gifts.count
        state.coinBalance -= total
        persist()
        return VibeSendGiftResponse(success: true,
                                    message: "Gift sent successfully",
                                    data: VibeSendGiftData(giftCount: state.vibes[index].giftCount, coinBalance: state.coinBalance))
    }

    func receivedGifts(vibeId: String) -> VibeReceivedGiftsResponse {
        let gifts = (state.receivedGifts[vibeId] ?? []).sorted {
            (VibeDate.date(from: $0.createdAt) ?? .distantPast) > (VibeDate.date(from: $1.createdAt) ?? .distantPast)
        }
        return VibeReceivedGiftsResponse(success: true,
                                         totalGifts: gifts.count,
                                         totalCoins: gifts.reduce(0) { $0 + ($1.coinsUsed ?? 0) },
                                         gifts: gifts)
    }

    func reset() {
        state = MockVibeStore.seedState()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let catalog: [VibeGift] = [
        VibeGift(id: 1, title: "Rose", icon: "🌹", amount: 1),
        VibeGift(id: 2, title: "Heart", icon: "💖", amount: 5),
        VibeGift(id: 3, title: "Chocolate", icon: "🍫", amount: 10),
        VibeGift(id: 4, title: "Teddy", icon: "🧸", amount: 20),
        VibeGift(id: 5, title: "Bouquet", icon: "💐", amount: 50),
        VibeGift(id: 6, title: "Ring", icon: "💍", amount: 100),
        VibeGift(id: 7, title: "Crown", icon: "👑", amount: 200),
        VibeGift(id: 8, title: "Sports car", icon: "🏎️", amount: 500)
    ]

    private static func author(_ person: MockPerson) -> VibeAuthor {
        VibeAuthor(userId: String(person.id),
                   userName: person.displayName,
                   fullName: person.fullname,
                   profilePicture: person.photos.first,
                   verified: person.isVerified)
    }

    private static func timestamp(minutesAgo: Int) -> String {
        VibeDate.string(from: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }

    private static func seedState() -> State {
        let seeds: [(personID: Int, caption: String, photos: [String], minutesAgo: Int, likes: Int, gifts: Int)] = [
            (101, "Sunday mood: coffee, playlist on shuffle and zero plans ☕️🎶", ["delete-24"], 12, 24, 3),
            (103, "Made it to the top! Nothing beats mountain air after a long week 🏔️", ["delete-8", "delete-24"], 45, 58, 6),
            (105, "Street food tour tonight. Who's in? 🌮", [], 90, 17, 0),
            (102, "Currently reading three books at once and regretting nothing 📚", ["delete-26"], 180, 33, 2),
            (106, "Leg day done. Netflix recommendations please 🍿", [], 300, 12, 1),
            (104, "Tried a new pasta recipe and it actually worked 🍝", ["delete-3"], 420, 41, 4),
            (107, "My dog judged me for singing in the shower again 🐶", ["delete-23"], 600, 76, 9),
            (108, "Classical music + rainy evenings = perfect combo 🎻", [], 900, 19, 0),
            (101, "Sunsets hit different when you're with the right people 🌅", ["delete-25", "delete-8"], 1500, 88, 11),
            (103, "Chai over coffee. Fight me ☕️", [], 2200, 27, 1),
            (105, "Spontaneous road trip to the lakes 🚗💨", ["delete-5"], 3100, 64, 5),
            (106, "Morning runs are my therapy 🏃‍♀️", ["delete-7"], 4400, 22, 0)
        ]

        var vibes: [Vibe] = []
        var comments: [String: [VibeComment]] = [:]
        let commenters = [102, 104, 106, 108, 101, 103]
        let commentTexts = ["Love this! 😍", "So true 😂", "Take me with you next time!", "This is such a vibe ✨", "Absolutely stunning 🔥"]

        for (index, seed) in seeds.enumerated() {
            guard let person = MockPeople.person(id: seed.personID) else { continue }
            let id = "vibe-\(index + 1)"
            let commentCount = index % 4
            comments[id] = (0..<commentCount).compactMap { offset in
                let commenterID = commenters[(index + offset) % commenters.count]
                guard commenterID != seed.personID, let commenter = MockPeople.person(id: commenterID) else { return nil }
                return VibeComment(id: "\(id)-c\(offset + 1)",
                                   vibeId: id,
                                   body: commentTexts[(index + offset) % commentTexts.count],
                                   createdAt: timestamp(minutesAgo: max(seed.minutesAgo - (offset + 1) * 5, 1)),
                                   author: author(commenter))
            }
            vibes.append(Vibe(id: id,
                              userId: String(person.id),
                              caption: seed.caption,
                              media: seed.photos.enumerated().map { VibeMedia(id: "\(id)-m\($0)", filePath: $1, fileType: "image") },
                              likesCount: seed.likes,
                              commentsCount: comments[id]?.count ?? 0,
                              giftCount: seed.gifts,
                              hasLiked: index % 3 == 0,
                              createdAt: timestamp(minutesAgo: seed.minutesAgo),
                              author: author(person)))
        }

        // The signed-in user's own vibe, so the "received gifts" sheet has data.
        let me = makeCurrentUserAuthor()
        let ownID = "vibe-own-1"
        let senders = [101, 103].compactMap(MockPeople.person(id:))
        let ownGifts: [VibeReceivedGift] = senders.enumerated().map { index, sender in
            let gift = catalog[index == 0 ? 1 : 3]
            return VibeReceivedGift(id: "\(ownID)-g\(index + 1)",
                                    giftId: gift.id,
                                    coinsUsed: gift.amount,
                                    createdAt: timestamp(minutesAgo: 200 - index * 30),
                                    gift: gift,
                                    sender: author(sender))
        }
        if let commenter = MockPeople.person(id: 102) {
            comments[ownID] = [VibeComment(id: "\(ownID)-c1", vibeId: ownID, body: "Looking great! 💫",
                                           createdAt: timestamp(minutesAgo: 230), author: author(commenter))]
        }
        vibes.append(Vibe(id: ownID,
                          userId: me.userId,
                          caption: "First vibe on FlirtTime! Say hi 👋",
                          media: [],
                          likesCount: 9,
                          commentsCount: comments[ownID]?.count ?? 0,
                          giftCount: ownGifts.count,
                          hasLiked: false,
                          createdAt: timestamp(minutesAgo: 240),
                          author: me))

        return State(vibes: vibes, comments: comments, receivedGifts: [ownID: ownGifts], coinBalance: 500)
    }
}
