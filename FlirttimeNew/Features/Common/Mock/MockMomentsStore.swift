//
//  MockMomentsStore.swift
//  FlirttimeNew
//
//  Local stand-in for the OneVibe `vibes/` + `gifts/` endpoints used by the Home tab.
//  State is persisted to disk and returned in the server response models, so replacing a
//  mock view-model method with its API call needs no UI changes.
//

import UIKit

final class MockMomentsStore {

    static let shared = MockMomentsStore()

    static let maxCaptionLength = 1000
    static let maxImagesPerVibe = 5

    private struct State: Codable {
        var vibes: [MomentsPost]
        var comments: [String: [MomentsComment]]
        var receivedGifts: [String: [MomentsReceivedGift]]
        var coinBalance: Int
        /// Optional so files saved before reporting existed still decode.
        var reportedVibeIds: [String]?
    }

    private let fileURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("mock_vibes_v4.json")

    private var state: State

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = MockMomentsStore.seedState()
        }
    }

    // MARK: - Current user

    var currentUserID: String {
        String(MockDataStore.shared.currentUserID)
    }

    var currentUserAuthor: MomentsAuthor {
        MockMomentsStore.makeCurrentUserAuthor()
    }

    private static func makeCurrentUserAuthor() -> MomentsAuthor {
        let info = MockDataStore.shared.currentUserResponse()?.data?.userInfo
        let name = info?.displayName ?? UserDataManager.shared.displayName ?? "You"
        let location = info?.locationShow == false ? nil : info?.location
        return MomentsAuthor(userId: String(MockDataStore.shared.currentUserID),
                          userName: name,
                          fullName: info?.fullname ?? name,
                          profilePicture: info?.avatar,
                          verified: info?.gestureIsVerified ?? false,
                          location: location)
    }

    // MARK: - Feed

    /// `authorID` limits the feed to one author's moments (GET vibes/?userId=).
    func feed(page: Int, limit: Int, authorID: String? = nil) -> MomentsFeedResponse {
        let reported = Set(state.reportedVibeIds ?? [])
        let sorted = state.vibes.filter {
            !reported.contains($0.id) && (authorID == nil || ($0.author?.userId ?? $0.userId) == authorID)
        }.sorted {
            (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
        }
        let start = max(page - 1, 0) * limit
        let rows = start < sorted.count ? Array(sorted[start..<min(start + limit, sorted.count)]) : []
        let data = MomentsFeedData(rows: rows, count: sorted.count, hasMore: start + rows.count < sorted.count, page: page, limit: limit)
        return MomentsFeedResponse(success: true, message: "", data: data)
    }

    /// Stand-in for the per-image upload endpoint; returns the stored file name.
    func uploadImage(_ image: UIImage) -> String? {
        LocalImageStore.shared.save(image)
    }

    func createVibe(caption: String, imagePaths: [String], location: String? = nil) -> CreateMomentsPostResponse {
        let id = UUID().uuidString
        let media = imagePaths.prefix(MockMomentsStore.maxImagesPerVibe).map {
            MomentsMedia(id: UUID().uuidString, filePath: $0, fileType: "image")
        }
        let vibe = MomentsPost(id: id,
                        userId: currentUserID,
                        caption: String(caption.prefix(MockMomentsStore.maxCaptionLength)),
                        media: media,
                        likesCount: 0,
                        commentsCount: 0,
                        giftCount: 0,
                        shareCount: 0,
                        hasLiked: false,
                        createdAt: MomentsDate.string(from: Date()),
                        author: currentUserAuthor,
                        location: location)
        state.vibes.append(vibe)
        persist()
        return CreateMomentsPostResponse(success: true, message: "Moment posted successfully", data: vibe)
    }

    func deleteVibe(vibeId: String) -> MomentsActionResponse {
        guard let index = state.vibes.firstIndex(where: { $0.id == vibeId }) else {
            return MomentsActionResponse(success: false, message: "Moment not found")
        }
        guard (state.vibes[index].author?.userId ?? state.vibes[index].userId) == currentUserID else {
            return MomentsActionResponse(success: false, message: "You can only delete your own moments")
        }
        let paths = state.vibes[index].media?.compactMap(\.filePath) ?? []
        state.vibes.remove(at: index)
        state.comments[vibeId] = nil
        state.receivedGifts[vibeId] = nil
        persist()
        paths.forEach { LocalImageStore.shared.remove($0) }
        return MomentsActionResponse(success: true, message: "Moment deleted")
    }

    func reportVibe(vibeId: String, reason: String) -> MomentsActionResponse {
        guard state.vibes.contains(where: { $0.id == vibeId }) else {
            return MomentsActionResponse(success: false, message: "Moment not found")
        }
        var reported = state.reportedVibeIds ?? []
        if !reported.contains(vibeId) {
            reported.append(vibeId)
        }
        state.reportedVibeIds = reported
        persist()
        return MomentsActionResponse(success: true, message: "Thanks for reporting. We'll review this moment.")
    }

    /// Stand-in for POST vibes/{id}/share. Returns the updated share count.
    func recordShare(vibeId: String) -> Int? {
        guard let index = state.vibes.firstIndex(where: { $0.id == vibeId }) else { return nil }
        let count = (state.vibes[index].shareCount ?? 0) + 1
        state.vibes[index].shareCount = count
        persist()
        return count
    }

    // MARK: - Likes

    func setLike(vibeId: String, liked: Bool) -> MomentsLikeResponse {
        guard let index = state.vibes.firstIndex(where: { $0.id == vibeId }) else {
            return MomentsLikeResponse(success: false, message: "Moment not found", data: nil)
        }
        if (state.vibes[index].hasLiked ?? false) != liked {
            let count = state.vibes[index].likesCount ?? 0
            state.vibes[index].likesCount = liked ? count + 1 : max(count - 1, 0)
            state.vibes[index].hasLiked = liked
            persist()
        }
        let vibe = state.vibes[index]
        return MomentsLikeResponse(success: true, message: "", data: MomentsLikeData(likesCount: vibe.likesCount, hasLiked: vibe.hasLiked))
    }

    // MARK: - Comments

    func comments(vibeId: String) -> MomentsCommentListResponse {
        let rows = (state.comments[vibeId] ?? []).sorted {
            (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
        }
        return MomentsCommentListResponse(success: true, message: "", data: MomentsCommentData(rows: rows, count: rows.count, hasMore: false))
    }

    func addComment(vibeId: String, body: String) -> CreateMomentsCommentResponse {
        guard let index = state.vibes.firstIndex(where: { $0.id == vibeId }) else {
            return CreateMomentsCommentResponse(success: false, message: "Moment not found", data: nil)
        }
        let comment = MomentsComment(id: UUID().uuidString,
                                  vibeId: vibeId,
                                  body: body,
                                  createdAt: MomentsDate.string(from: Date()),
                                  author: currentUserAuthor)
        state.comments[vibeId, default: []].append(comment)
        state.vibes[index].commentsCount = state.comments[vibeId]?.count ?? 0
        persist()
        return CreateMomentsCommentResponse(success: true, message: "Comment added", data: comment)
    }

    // MARK: - Gifts

    func giftCatalog() -> MomentsGiftCatalogResponse {
        MomentsGiftCatalogResponse(success: true, data: MomentsGiftCatalogData(gifts: MockMomentsStore.catalog, coinBalance: state.coinBalance))
    }

    func sendGifts(vibeId: String, giftIds: [Int]) -> MomentsSendGiftResponse {
        guard let index = state.vibes.firstIndex(where: { $0.id == vibeId }) else {
            return MomentsSendGiftResponse(success: false, message: "Moment not found", data: nil)
        }
        let gifts = giftIds.compactMap { id in MockMomentsStore.catalog.first { $0.id == id } }
        let total = gifts.reduce(0) { $0 + ($1.amount ?? 0) }
        guard total <= state.coinBalance else {
            return MomentsSendGiftResponse(success: false,
                                        message: "Insufficient coin balance",
                                        data: MomentsSendGiftData(giftCount: state.vibes[index].giftCount, coinBalance: state.coinBalance))
        }
        let sender = currentUserAuthor
        let now = MomentsDate.string(from: Date())
        let received = gifts.map {
            MomentsReceivedGift(id: UUID().uuidString, giftId: $0.id, coinsUsed: $0.amount, createdAt: now, gift: $0, sender: sender)
        }
        state.receivedGifts[vibeId, default: []].append(contentsOf: received)
        state.vibes[index].giftCount = (state.vibes[index].giftCount ?? 0) + gifts.count
        state.coinBalance -= total
        persist()
        return MomentsSendGiftResponse(success: true,
                                    message: "Gift sent successfully",
                                    data: MomentsSendGiftData(giftCount: state.vibes[index].giftCount, coinBalance: state.coinBalance))
    }

    func receivedGifts(vibeId: String) -> MomentsReceivedGiftsResponse {
        let gifts = (state.receivedGifts[vibeId] ?? []).sorted {
            (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
        }
        return MomentsReceivedGiftsResponse(success: true,
                                         totalGifts: gifts.count,
                                         totalCoins: gifts.reduce(0) { $0 + ($1.coinsUsed ?? 0) },
                                         gifts: gifts)
    }

    func reset() {
        state = MockMomentsStore.seedState()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let catalog: [MomentsGift] = [
        MomentsGift(id: 1, title: "Rose", icon: "🌹", amount: 1),
        MomentsGift(id: 2, title: "Heart", icon: "💖", amount: 5),
        MomentsGift(id: 3, title: "Chocolate", icon: "🍫", amount: 10),
        MomentsGift(id: 4, title: "Teddy", icon: "🧸", amount: 20),
        MomentsGift(id: 5, title: "Bouquet", icon: "💐", amount: 50),
        MomentsGift(id: 6, title: "Ring", icon: "💍", amount: 100),
        MomentsGift(id: 7, title: "Crown", icon: "👑", amount: 200),
        MomentsGift(id: 8, title: "Sports car", icon: "🏎️", amount: 500)
    ]

    private static func author(_ person: MockPerson) -> MomentsAuthor {
        MomentsAuthor(userId: String(person.id),
                   userName: person.displayName,
                   fullName: person.fullname,
                   profilePicture: person.photos.first,
                   verified: person.isVerified,
                   location: person.location)
    }

    private static func timestamp(minutesAgo: Int) -> String {
        MomentsDate.string(from: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }

    private static func seedState() -> State {
        let seeds: [(personID: Int, caption: String, photos: [String], minutesAgo: Int, likes: Int, gifts: Int, shares: Int)] = [
            (101, "Sunday mood: coffee, playlist on shuffle and zero plans ☕️🎶", ["mock-cindy-1"], 12, 24, 3, 2),
            (103, "Made it to the top! Nothing beats mountain air after a long week 🏔️", ["mock-riya-1", "mock-riya-2"], 45, 58, 6, 8),
            (105, "Street food tour tonight. Who's in? 🌮", [], 90, 17, 0, 1),
            (102, "Currently reading three books at once and regretting nothing 📚", ["mock-ally-0"], 180, 33, 2, 4),
            (106, "Leg day done. Netflix recommendations please 🍿", [], 300, 12, 1, 0),
            (104, "Tried a new pasta recipe and it actually worked 🍝", ["mock-meera-1"], 420, 41, 4, 5),
            (107, "My dog judged me for singing in the shower again 🐶", ["mock-tanya-1"], 600, 76, 9, 12),
            (108, "Classical music + rainy evenings = perfect combo 🎻", [], 900, 19, 0, 2),
            (101, "Sunsets hit different when you're with the right people 🌅", ["mock-sara-1", "mock-cindy-0"], 1500, 88, 11, 15),
            (103, "Chai over coffee. Fight me ☕️", [], 2200, 27, 1, 3),
            (105, "Spontaneous road trip to the lakes 🚗💨", ["mock-sara-3"], 3100, 64, 5, 7),
            (106, "Morning runs are my therapy 🏃‍♀️", ["mock-nisha-0"], 4400, 22, 0, 1)
        ]

        var vibes: [MomentsPost] = []
        var comments: [String: [MomentsComment]] = [:]
        let commenters = [102, 104, 106, 108, 101, 103]
        let commentTexts = ["Love this! 😍", "So true 😂", "Take me with you next time!", "This is such a vibe ✨", "Absolutely stunning 🔥"]

        for (index, seed) in seeds.enumerated() {
            guard let person = MockPeople.person(id: seed.personID) else { continue }
            let id = "vibe-\(index + 1)"
            let commentCount = index % 4
            comments[id] = (0..<commentCount).compactMap { offset in
                let commenterID = commenters[(index + offset) % commenters.count]
                guard commenterID != seed.personID, let commenter = MockPeople.person(id: commenterID) else { return nil }
                return MomentsComment(id: "\(id)-c\(offset + 1)",
                                   vibeId: id,
                                   body: commentTexts[(index + offset) % commentTexts.count],
                                   createdAt: timestamp(minutesAgo: max(seed.minutesAgo - (offset + 1) * 5, 1)),
                                   author: author(commenter))
            }
            vibes.append(MomentsPost(id: id,
                              userId: String(person.id),
                              caption: seed.caption,
                              media: seed.photos.enumerated().map { MomentsMedia(id: "\(id)-m\($0)", filePath: $1, fileType: "image") },
                              likesCount: seed.likes,
                              commentsCount: comments[id]?.count ?? 0,
                              giftCount: seed.gifts,
                              shareCount: seed.shares,
                              hasLiked: index % 3 == 0,
                              createdAt: timestamp(minutesAgo: seed.minutesAgo),
                              author: author(person)))
        }

        // The signed-in user's own moment, so the "received gifts" sheet has data.
        let me = makeCurrentUserAuthor()
        let ownID = "vibe-own-1"
        let senders = [101, 103].compactMap(MockPeople.person(id:))
        let ownGifts: [MomentsReceivedGift] = senders.enumerated().map { index, sender in
            let gift = catalog[index == 0 ? 1 : 3]
            return MomentsReceivedGift(id: "\(ownID)-g\(index + 1)",
                                    giftId: gift.id,
                                    coinsUsed: gift.amount,
                                    createdAt: timestamp(minutesAgo: 200 - index * 30),
                                    gift: gift,
                                    sender: author(sender))
        }
        if let commenter = MockPeople.person(id: 102) {
            comments[ownID] = [MomentsComment(id: "\(ownID)-c1", vibeId: ownID, body: "Looking great! 💫",
                                           createdAt: timestamp(minutesAgo: 230), author: author(commenter))]
        }
        vibes.append(MomentsPost(id: ownID,
                          userId: me.userId,
                          caption: "First moment on FlirtTime! Say hi 👋",
                          media: [],
                          likesCount: 9,
                          commentsCount: comments[ownID]?.count ?? 0,
                          giftCount: ownGifts.count,
                          shareCount: 2,
                          hasLiked: false,
                          createdAt: timestamp(minutesAgo: 240),
                          author: me))

        let ownPhotoVibes: [(caption: String, photos: [String], minutesAgo: Int, likes: Int, comments: Int)] = [
            ("Planning the next getaway. Suggestions welcome 🗺️", ["mock-me-moment-0"], 35, 14, 0),
            ("Forest walks reset everything 🌲", ["mock-me-moment-1"], 150, 21, 0)
        ]
        for (index, seed) in ownPhotoVibes.enumerated() {
            let id = "vibe-own-\(index + 2)"
            vibes.append(MomentsPost(id: id,
                              userId: me.userId,
                              caption: seed.caption,
                              media: seed.photos.enumerated().map { MomentsMedia(id: "\(id)-m\($0)", filePath: $1, fileType: "image") },
                              likesCount: seed.likes,
                              commentsCount: seed.comments,
                              giftCount: 0,
                              shareCount: index == 0 ? 1 : 3,
                              hasLiked: false,
                              createdAt: timestamp(minutesAgo: seed.minutesAgo),
                              author: me))
        }

        return State(vibes: vibes, comments: comments, receivedGifts: [ownID: ownGifts], coinBalance: 500)
    }
}
