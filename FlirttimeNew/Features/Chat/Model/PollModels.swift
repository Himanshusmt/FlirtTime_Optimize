//
//  PollModels.swift
//  FlirttimeNew
//
//  Created by Awais on 07/09/25.
//

import Foundation

struct PollData: Codable, Equatable, Hashable {
    /// Server poll UUID — required for `POST chat/polls/{pollId}/vote` (FE `ChatPollSummary.id`).
    var id: String?
    let settings: PollSettings?
    let question: String
    let options: [PollOption]
    let totalVotes: Int
    /// Options the current user has selected (FE `myOptionIds`).
    var myOptionIds: [String]
    var isClosed: Bool
    var version: Int?
    var closesAt: String?
    var createdBy: String?

    enum CodingKeys: String, CodingKey {
        case id, settings, question, options, totalVotes
        case myOptionIds, isClosed, version, closesAt, createdBy
        case allowMultiple, isAnonymous
        case multipleAnswers = "multiple_answers"
        case multipleAnswersCamel = "multipleAnswers"
        case anonymous
    }

    init(
        id: String? = nil,
        settings: PollSettings?,
        question: String,
        options: [PollOption],
        totalVotes: Int,
        myOptionIds: [String] = [],
        isClosed: Bool = false,
        version: Int? = nil,
        closesAt: String? = nil,
        createdBy: String? = nil
    ) {
        self.id = id
        self.settings = settings
        self.question = question
        self.options = options
        self.totalVotes = totalVotes
        self.myOptionIds = myOptionIds
        self.isClosed = isClosed
        self.version = version
        self.closesAt = closesAt
        self.createdBy = createdBy
    }

    static func == (lhs: PollData, rhs: PollData) -> Bool {
        guard lhs.id == rhs.id,
              lhs.question == rhs.question,
              lhs.totalVotes == rhs.totalVotes,
              lhs.isClosed == rhs.isClosed,
              lhs.myOptionIds == rhs.myOptionIds,
              lhs.options.count == rhs.options.count else { return false }
        for (lo, ro) in zip(lhs.options, rhs.options) {
            if lo.voteCount != ro.voteCount || lo.optionId != ro.optionId { return false }
            let lVoters = Set(lo.votes?.map { $0.userId } ?? [])
            let rVoters = Set(ro.votes?.map { $0.userId } ?? [])
            if lVoters != rVoters { return false }
        }
        return true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(question)
        hasher.combine(totalVotes)
        hasher.combine(isClosed)
        hasher.combine(myOptionIds)
        for opt in options {
            hasher.combine(opt.optionId)
            hasher.combine(opt.voteCount)
            opt.votes?.forEach { hasher.combine($0.userId) }
        }
    }

    var allowsMultipleAnswers: Bool {
        settings?.multipleAnswers == true
    }

    var isAnonymousPoll: Bool {
        settings?.anonymous == true
    }

    /// Poll creator can open the voters list; everyone else only sees counts.
    func isCreatedBy(userId: String) -> Bool {
        let me = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !me.isEmpty else { return false }
        if let createdBy, !createdBy.isEmpty {
            return createdBy.caseInsensitiveCompare(me) == .orderedSame
        }
        return false
    }

    /// Resolve the current user's selected option ids from `myOptionIds` or voter lists.
    func resolvedMyOptionIds(currentUserId: String) -> [String] {
        if !myOptionIds.isEmpty { return myOptionIds }
        guard !currentUserId.isEmpty else { return [] }
        return options.compactMap { opt in
            let voted = opt.votes?.contains(where: {
                $0.userId.caseInsensitiveCompare(currentUserId) == .orderedSame
            }) ?? false
            return voted ? opt.optionId : nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        question = try container.decodeIfPresent(String.self, forKey: .question) ?? ""
        let decodedOptions = try container.decodeIfPresent([PollOption].self, forKey: .options)
        options = decodedOptions ?? []
        if let total = try container.decodeIfPresent(Int.self, forKey: .totalVotes) {
            totalVotes = total
        } else {
            totalVotes = options.reduce(0) { $0 + $1.voteCount }
        }
        myOptionIds = try container.decodeIfPresent([String].self, forKey: .myOptionIds) ?? []
        isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        closesAt = try container.decodeIfPresent(String.self, forKey: .closesAt)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)

        if let nested = try container.decodeIfPresent(PollSettings.self, forKey: .settings) {
            settings = nested
        } else {
            settings = Self.decodeRootSettings(from: container)
        }
    }

    private static func decodeRootSettings(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> PollSettings {
        let multiple =
            (try? container.decodeIfPresent(Bool.self, forKey: .allowMultiple))
            ?? (try? container.decodeIfPresent(Bool.self, forKey: .multipleAnswersCamel))
            ?? (try? container.decodeIfPresent(Bool.self, forKey: .multipleAnswers))
            ?? false
        let anon =
            (try? container.decodeIfPresent(Bool.self, forKey: .isAnonymous))
            ?? (try? container.decodeIfPresent(Bool.self, forKey: .anonymous))
            ?? false
        return PollSettings(multipleAnswers: multiple, anonymous: anon)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(settings, forKey: .settings)
        try container.encode(question, forKey: .question)
        try container.encode(options, forKey: .options)
        try container.encode(totalVotes, forKey: .totalVotes)
        try container.encode(myOptionIds, forKey: .myOptionIds)
        try container.encode(isClosed, forKey: .isClosed)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(closesAt, forKey: .closesAt)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        if let settings {
            try container.encode(settings.multipleAnswers, forKey: .allowMultiple)
            try container.encode(settings.anonymous, forKey: .isAnonymous)
        }
    }

    /// Apply a compact vote-API / socket poll summary onto this poll (counts + myOptionIds; voters optional).
    func applyingSummary(_ summary: PollData) -> PollData {
        let mergedOptions: [PollOption] = summary.options.map { summaryOpt in
            let existing = options.first(where: { $0.optionId == summaryOpt.optionId })
            // Compact API has no voter list — keep local voters only when counts still match.
            let keepVoters: [PollVoter]? = {
                guard let existingVotes = existing?.votes, !existingVotes.isEmpty else {
                    return summaryOpt.votes
                }
                if existingVotes.count == summaryOpt.voteCount {
                    return existingVotes
                }
                return summaryOpt.votes
            }()
            return PollOption(
                text: summaryOpt.text.isEmpty ? (existing?.text ?? "") : summaryOpt.text,
                voteCount: summaryOpt.voteCount,
                optionId: summaryOpt.optionId,
                votes: keepVoters
            )
        }
        return PollData(
            id: summary.id ?? id,
            settings: summary.settings ?? settings,
            question: summary.question.isEmpty ? question : summary.question,
            options: mergedOptions.isEmpty ? options : mergedOptions,
            totalVotes: summary.totalVotes,
            myOptionIds: summary.myOptionIds,
            isClosed: summary.isClosed,
            version: summary.version ?? version,
            closesAt: summary.closesAt ?? closesAt,
            createdBy: summary.createdBy ?? createdBy
        )
    }
}

struct PollSettings: Codable, Equatable, Hashable {
    let multipleAnswers: Bool
    let anonymous: Bool

    init(multipleAnswers: Bool, anonymous: Bool) {
        self.multipleAnswers = multipleAnswers
        self.anonymous = anonymous
    }

    enum CodingKeys: String, CodingKey {
        case multipleAnswers = "multiple_answers"
        case multipleAnswersCamel = "multipleAnswers"
        case anonymous
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        var mAnswers: Bool = false
        if let val = try? container.decodeIfPresent(Bool.self, forKey: .multipleAnswers) { mAnswers = val }
        else if let val = try? container.decodeIfPresent(Bool.self, forKey: .multipleAnswersCamel) { mAnswers = val }
        else if let intVal = try? container.decodeIfPresent(Int.self, forKey: .multipleAnswers) { mAnswers = intVal != 0 }
        else if let intVal = try? container.decodeIfPresent(Int.self, forKey: .multipleAnswersCamel) { mAnswers = intVal != 0 }

        var anon: Bool = false
        if let val = try? container.decodeIfPresent(Bool.self, forKey: .anonymous) { anon = val }
        else if let intVal = try? container.decodeIfPresent(Int.self, forKey: .anonymous) { anon = intVal != 0 }

        self.multipleAnswers = mAnswers
        self.anonymous = anon
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(multipleAnswers, forKey: .multipleAnswers)
        try container.encode(anonymous, forKey: .anonymous)
    }
}

struct PollOption: Codable, Identifiable, Hashable {
    let text: String
    let voteCount: Int
    let optionId: String
    let votes: [PollVoter]?
    /// FE `percent` (0–100); optional for UI bars.
    let percent: Int?

    var id: String { optionId }

    enum CodingKeys: String, CodingKey {
        case text, votes, percent
        case voteCount = "vote_count"
        case voteCountCamel = "voteCount"
        case votesCount
        case optionId = "option_id"
        case optionIdCamel = "optionId"
        case id
    }

    init(text: String, voteCount: Int, optionId: String, votes: [PollVoter]?, percent: Int? = nil) {
        self.text = text
        self.voteCount = voteCount
        self.optionId = optionId
        self.votes = votes
        self.percent = percent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""

        if let vc = try? container.decodeIfPresent(Int.self, forKey: .voteCount) {
            voteCount = vc ?? 0
        } else if let vc = try? container.decodeIfPresent(Int.self, forKey: .voteCountCamel) {
            voteCount = vc ?? 0
        } else if let vc = try? container.decodeIfPresent(Int.self, forKey: .votesCount) {
            voteCount = vc ?? 0
        } else {
            voteCount = 0
        }

        if let oid = try? container.decode(String.self, forKey: .optionId) {
            optionId = oid
        } else if let oid = try? container.decode(String.self, forKey: .optionIdCamel) {
            optionId = oid
        } else if let oid = try? container.decode(String.self, forKey: .id) {
            optionId = oid
        } else if let oidInt = try? container.decode(Int.self, forKey: .optionId) {
            optionId = String(oidInt)
        } else if let oidInt = try? container.decode(Int.self, forKey: .optionIdCamel) {
            optionId = String(oidInt)
        } else if let oidInt = try? container.decode(Int.self, forKey: .id) {
            optionId = String(oidInt)
        } else {
            optionId = UUID().uuidString
        }

        votes = try container.decodeIfPresent([PollVoter].self, forKey: .votes)
        percent = try container.decodeIfPresent(Int.self, forKey: .percent)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(votes, forKey: .votes)
        try container.encode(voteCount, forKey: .voteCount)
        try container.encode(optionId, forKey: .optionId)
        try container.encode(optionId, forKey: .id)
        try container.encodeIfPresent(percent, forKey: .percent)
    }
}

struct PollVoter: Codable, Hashable {
    let userId: String
    let userName: String?
    let fullName: String?
    let profilePicture: String?
    let votedAt: String?

    init(userId: String,
         userName: String? = nil,
         fullName: String? = nil,
         profilePicture: String? = nil,
         votedAt: String? = nil) {
        self.userId = userId
        self.userName = userName
        self.fullName = fullName
        self.profilePicture = profilePicture
        self.votedAt = votedAt
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case userIdCamel = "userId"
        case userName = "user_name"
        case userNameCamel = "userName"
        case fullName = "full_name"
        case fullNameCamel = "fullName"
        case profilePicture = "profile_picture"
        case profilePictureCamel = "profilePicture"
        case votedAt = "voted_at"
        case votedAtCamel = "votedAt"
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let uid = try? container.decodeIfPresent(String.self, forKey: .userId) { userId = uid ?? "" }
        else if let uid = try? container.decodeIfPresent(String.self, forKey: .userIdCamel) { userId = uid ?? "" }
        else if let uid = try? container.decodeIfPresent(String.self, forKey: .id) { userId = uid ?? "" }
        else { userId = "" }

        if let uname = try? container.decodeIfPresent(String.self, forKey: .userName) { userName = uname }
        else if let uname = try? container.decodeIfPresent(String.self, forKey: .userNameCamel) { userName = uname }
        else { userName = nil }

        if let fname = try? container.decodeIfPresent(String.self, forKey: .fullName) { fullName = fname }
        else if let fname = try? container.decodeIfPresent(String.self, forKey: .fullNameCamel) { fullName = fname }
        else { fullName = nil }

        if let pic = try? container.decodeIfPresent(String.self, forKey: .profilePicture) { profilePicture = pic }
        else if let pic = try? container.decodeIfPresent(String.self, forKey: .profilePictureCamel) { profilePicture = pic }
        else { profilePicture = nil }

        if let vAt = try? container.decodeIfPresent(String.self, forKey: .votedAt) { votedAt = vAt }
        else if let vAt = try? container.decodeIfPresent(String.self, forKey: .votedAtCamel) { votedAt = vAt }
        else { votedAt = nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(userName, forKey: .userName)
        try container.encodeIfPresent(fullName, forKey: .fullName)
        try container.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try container.encodeIfPresent(votedAt, forKey: .votedAt)
    }
}

struct CreatePollRequest: Codable {
    let conversationId: String
    let question: String
    let options: [String]
    let allowMultipleAnswers: Bool

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case question, options
        case allowMultipleAnswers = "allow_multiple_answers"
    }
}

struct CreatePollResponse: Codable {
    let success: Bool
    let message: String?
    let data: PollData?
}

/// FE `votePoll` body — `{ optionIds: string[] }` (pollId is path param).
struct ChatPollVoteRequestBody {
    let optionIds: [String]

    var asParameters: [String: Any] {
        ["optionIds": optionIds]
    }
}

/// Unwrapped `data` from `POST chat/polls/{pollId}/vote` (FE: `{ poll: ChatPollSummary }`).
struct ChatPollVoteAPIData: Codable {
    let poll: PollData?

    enum CodingKeys: String, CodingKey {
        case poll
    }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let nested = try c.decodeIfPresent(PollData.self, forKey: .poll) {
            poll = nested
            return
        }
        // Some backends return the poll object directly as `data`
        poll = try? PollData(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(poll, forKey: .poll)
    }
}

/// FE `fetchPollVoters` — `GET chat/polls/{pollId}/options/{optionId}/voters`
struct ChatPollVotersAPIData: Codable {
    let rows: [ChatPollVoterRow]
    let nextCursor: String?
    let limit: Int?
    let page: Int?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case rows, voters, items, users, data
        case nextCursor, cursor, limit, page, hasMore
    }

    init(
        rows: [ChatPollVoterRow] = [],
        nextCursor: String? = nil,
        limit: Int? = nil,
        page: Int? = nil,
        hasMore: Bool? = nil
    ) {
        self.rows = rows
        self.nextCursor = nextCursor
        self.limit = limit
        self.page = page
        self.hasMore = hasMore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = Self.decodeRows(from: c)
        nextCursor = (try? c.decodeIfPresent(String.self, forKey: .nextCursor))
            ?? (try? c.decodeIfPresent(String.self, forKey: .cursor))
        limit = try? c.decodeIfPresent(Int.self, forKey: .limit)
        page = try? c.decodeIfPresent(Int.self, forKey: .page)
        hasMore = try? c.decodeIfPresent(Bool.self, forKey: .hasMore)
    }

    private static func decodeRows(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [ChatPollVoterRow] {
        if let rows = try? container.decode([ChatPollVoterRow].self, forKey: .rows) {
            return rows
        }
        if let rows = try? container.decode([ChatPollVoterRow].self, forKey: .voters) {
            return rows
        }
        if let rows = try? container.decode([ChatPollVoterRow].self, forKey: .items) {
            return rows
        }
        if let rows = try? container.decode([ChatPollVoterRow].self, forKey: .users) {
            return rows
        }
        if let rows = try? container.decode([ChatPollVoterRow].self, forKey: .data) {
            return rows
        }
        return []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rows, forKey: .rows)
        try c.encodeIfPresent(nextCursor, forKey: .nextCursor)
        try c.encodeIfPresent(limit, forKey: .limit)
        try c.encodeIfPresent(page, forKey: .page)
        try c.encodeIfPresent(hasMore, forKey: .hasMore)
    }
}

struct ChatPollVoterRow: Codable, Identifiable, Hashable {
    let id: String
    let username: String?
    let fullName: String?
    let profilePicture: String?
    let isVerified: Bool?
    let votedAt: String?

    var displayName: String {
        let name = (fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let uname = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !uname.isEmpty { return uname }
        return "Unknown"
    }

    enum CodingKeys: String, CodingKey {
        case id, username, userName, fullName, profilePicture, profileImage
        case avatarUrl, avatar, image, isVerified, verified, votedAt
    }

    init(
        id: String,
        username: String? = nil,
        fullName: String? = nil,
        profilePicture: String? = nil,
        isVerified: Bool? = nil,
        votedAt: String? = nil
    ) {
        self.id = id
        self.username = username
        self.fullName = fullName
        self.profilePicture = profilePicture
        self.isVerified = isVerified
        self.votedAt = votedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let decodedId = try c.decodeIfPresent(String.self, forKey: .id), !decodedId.isEmpty {
            id = decodedId
        } else {
            id = UUID().uuidString
        }

        if let value = try c.decodeIfPresent(String.self, forKey: .username) {
            username = value
        } else {
            username = try c.decodeIfPresent(String.self, forKey: .userName)
        }

        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        profilePicture = Self.decodeProfilePicture(from: c)
        isVerified = Self.decodeIsVerified(from: c)
        votedAt = try c.decodeIfPresent(String.self, forKey: .votedAt)
    }

    private static func decodeProfilePicture(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> String? {
        let keys: [CodingKeys] = [.profilePicture, .profileImage, .avatarUrl, .avatar, .image]
        for key in keys {
            guard let value = try? container.decode(String.self, forKey: key),
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private static func decodeIsVerified(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> Bool? {
        if let value = try? container.decode(Bool.self, forKey: .isVerified) {
            return value
        }
        if let value = try? container.decode(Bool.self, forKey: .verified) {
            return value
        }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(isVerified, forKey: .isVerified)
        try c.encodeIfPresent(votedAt, forKey: .votedAt)
    }

    func asPollVoter() -> PollVoter {
        PollVoter(
            userId: id,
            userName: username,
            fullName: fullName,
            profilePicture: profilePicture,
            votedAt: votedAt
        )
    }
}

struct PollVoteRequest: Codable {
    let pollId: String
    let optionIds: [String]

    enum CodingKeys: String, CodingKey {
        case pollId = "poll_id"
        case optionIdsSnake = "option_ids"
        case optionIds
    }

    init(pollId: String, optionIds: [String]) {
        self.pollId = pollId
        self.optionIds = optionIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pollId = try container.decode(String.self, forKey: .pollId)
        if let ids = try container.decodeIfPresent([String].self, forKey: .optionIds) {
            optionIds = ids
        } else {
            optionIds = try container.decodeIfPresent([String].self, forKey: .optionIdsSnake) ?? []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pollId, forKey: .pollId)
        try container.encode(optionIds, forKey: .optionIds)
    }
}

struct PollVoteResponse: Codable {
    let success: Bool
    let message: String?
    let data: PollData?
}

extension ConversationMessage {
    var pollData: PollData? {
        return poll
    }

    var messageReactions: [MessageReaction] {
        if let wrapper = reactionsWrapper {
            return wrapper.data
        }
        return reactions ?? []
    }

    var reactionsCount: Int {
        if let wrapper = reactionsWrapper {
            return wrapper.count ?? 0
        }
        return reactions?.reduce(0) { $0 + $1.count } ?? 0
    }

    func hasUserReacted(with emoji: String, userId: String) -> Bool {
        return messageReactions.contains { reaction in
            reaction.emoji == emoji && reaction.users.contains { $0.userId == userId }
        }
    }

    func getUserReactions(userId: String) -> [MessageReaction] {
        return messageReactions.filter { reaction in
            reaction.users.contains { $0.userId == userId }
        }
    }

    var totalUniqueReactionUsers: Int {
        let allUserIds = messageReactions.flatMap { $0.users.map { $0.userId } }
        return Set(allUserIds).count
    }
}

struct PollCreationData {
    var question: String = ""
    var options: [String] = ["", ""]
    let allowMultipleAnswers: Bool = false
    let isAnonymous: Bool = false

    var isValid: Bool {
        let nonEmptyOptions = options.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        nonEmptyOptions.count >= 2
    }

    var validOptions: [String] {
        return options.compactMap { option in
            let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    func toRESTPollPayload() -> [String: Any] {
        [
            "question": question,
            "options": validOptions,
            "allowMultiple": allowMultipleAnswers,
            "isAnonymous": isAnonymous
        ]
    }

    @available(*, deprecated, message: "Use REST sendViaREST / toRESTPollPayload — socket send removed")
    func toSocketMessage(conversationId: String, chatType: String = "direct", content: String = "") -> [String: Any] {
        [
            "conversationId": conversationId,
            "type": "poll",
            "body": content.isEmpty ? question : content,
            "poll": toRESTPollPayload(),
            "clientMessageId": UUID().uuidString
        ]
    }
}

struct PollMessageData: Codable {
    let question: String
    let options: [PollOptionData]
    let settings: PollMessageSettings?

    struct PollOptionData: Codable {
        let text: String
    }

    struct PollMessageSettings: Codable {
        let multiple_answers: Bool
        let anonymous: Bool
    }
}

struct CreatePollMessage: Codable {
    let conversationId: String
    let messageType: String
    let chatType: String
    let content: String
    let pollData: PollMessageData

    enum CodingKeys: String, CodingKey {
        case conversationId, messageType, chatType, content, pollData
    }
}
