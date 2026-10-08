//
//  ChatSheets.swift
//  FlirttimeNew
//

import SwiftUI
import Kingfisher
import RxSwift
import Swinject

// MARK: - Poll Votes Sheet

/// Voters list is creator-only. Non-creators should not open this sheet.
final class PollVotesSheetViewModel: ObservableObject {
    let pollId: String
    let pollQuestion: String
    let options: [PollOption]
    let currentUserId: String
    let canSeeVoters: Bool

    @Published var votersByOptionId: [String: [ChatPollVoterRow]] = [:]
    @Published var nextCursorByOptionId: [String: String?] = [:]
    @Published var isLoading = false
    @Published var loadingMoreOptionId: String?
    @Published var errorMessage: String?

    private let disposeBag = DisposeBag()

    init(
        pollId: String,
        pollQuestion: String,
        options: [PollOption],
        currentUserId: String,
        canSeeVoters: Bool
    ) {
        self.pollId = pollId
        self.pollQuestion = pollQuestion
        self.options = options
        self.currentUserId = currentUserId
        self.canSeeVoters = canSeeVoters
    }

    func loadIfNeeded() {
        guard canSeeVoters, !isLoading else { return }
        let optionsWithVotes = options.filter { max($0.votes?.count ?? 0, $0.voteCount) > 0 }
        guard !optionsWithVotes.isEmpty else { return }
        guard !pollId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Fallback: embed any local voters already on options
            var map: [String: [ChatPollVoterRow]] = [:]
            for opt in optionsWithVotes {
                map[opt.optionId] = (opt.votes ?? []).map {
                    ChatPollVoterRow(id: $0.userId, username: $0.userName, fullName: $0.fullName, profilePicture: $0.profilePicture, isVerified: nil, votedAt: $0.votedAt)
                }
            }
            votersByOptionId = map
            return
        }

        guard let session = Container.sharedContainer.resolve(SessionManager.self) else {
            errorMessage = "Session unavailable"
            return
        }

        isLoading = true
        errorMessage = nil

        let requests = optionsWithVotes.map { option in
            session.fetchChatPollVoters(pollId: pollId, optionId: option.optionId, limit: 80)
                .map { (option.optionId, $0) }
                .catch { _ in Single.just((option.optionId, ChatPollVotersAPIData())) }
        }

        Observable.zip(requests.map { $0.asObservable() })
            .observe(on: MainScheduler.instance)
            .subscribe(
                onNext: { [weak self] results in
                    guard let self else { return }
                    var map: [String: [ChatPollVoterRow]] = [:]
                    var cursors: [String: String?] = [:]
                    for (optionId, page) in results {
                        map[optionId] = page.rows
                        cursors[optionId] = page.nextCursor
                    }
                    self.votersByOptionId = map
                    self.nextCursorByOptionId = cursors
                    self.isLoading = false
                },
                onError: { [weak self] error in
                    self?.isLoading = false
                    let msg = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.errorMessage = msg.isEmpty ? "Could not load voters" : msg
                }
            )
            .disposed(by: disposeBag)
    }

    func loadMore(for optionId: String) {
        guard canSeeVoters,
              loadingMoreOptionId == nil,
              let cursor = nextCursorByOptionId[optionId] ?? nil,
              !cursor.isEmpty else { return }

        guard let session = Container.sharedContainer.resolve(SessionManager.self) else { return }

        loadingMoreOptionId = optionId
        session.fetchChatPollVoters(pollId: pollId, optionId: optionId, limit: 40, cursor: cursor)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] page in
                    guard let self else { return }
                    var existing = self.votersByOptionId[optionId] ?? []
                    let existingIds = Set(existing.map(\.id))
                    existing.append(contentsOf: page.rows.filter { !existingIds.contains($0.id) })
                    self.votersByOptionId[optionId] = existing
                    self.nextCursorByOptionId[optionId] = page.nextCursor
                    self.loadingMoreOptionId = nil
                },
                onFailure: { [weak self] _ in
                    self?.loadingMoreOptionId = nil
                }
            )
            .disposed(by: disposeBag)
    }
}

struct PollVotesSheetView: View {
    @StateObject private var viewModel: PollVotesSheetViewModel
    @Environment(\.dismiss) var dismiss

    init(
        pollId: String,
        pollQuestion: String,
        options: [PollOption],
        currentUserId: String,
        canSeeVoters: Bool
    ) {
        _viewModel = StateObject(
            wrappedValue: PollVotesSheetViewModel(
                pollId: pollId,
                pollQuestion: pollQuestion,
                options: options,
                currentUserId: currentUserId,
                canSeeVoters: canSeeVoters
            )
        )
    }

    /// Legacy convenience — prefers embedded votes when API id is unavailable.
    init(
        pollQuestion: String,
        options: [PollOption],
        isFromSelf: Bool,
        currentUserId: String
    ) {
        self.init(
            pollId: "",
            pollQuestion: pollQuestion,
            options: options,
            currentUserId: currentUserId,
            canSeeVoters: isFromSelf
        )
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.pollQuestion)
                        .font(.chatBold(size: 18))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.chatRegular(size: 14))
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }

                    ForEach(Array(viewModel.options.enumerated()), id: \.element.optionId) { index, option in
                        VoteOptionSection(
                            option: option,
                            optionIndex: index + 1,
                            currentUserId: viewModel.currentUserId,
                            voters: viewModel.canSeeVoters
                                ? (viewModel.votersByOptionId[option.optionId] ?? [])
                                : [],
                            showVoters: viewModel.canSeeVoters,
                            nextCursor: (viewModel.nextCursorByOptionId[option.optionId] ?? nil),
                            isLoadingMore: viewModel.loadingMoreOptionId == option.optionId,
                            onLoadMore: { viewModel.loadMore(for: option.optionId) }
                        )
                    }
                }
            }
            .background(Color.chatSurface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(ChatStrings.chat_voteDetails.localizedString())
                        .font(.chatBold(size: 17))
                        .foregroundColor(.black)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        SwiftUI.Image(systemName: "xmark")
                            .font(.chat(.medium, size: 16))
                            .foregroundColor(.gray)
                    }
                }
            }
            .onAppear { viewModel.loadIfNeeded() }
        }
        .applyRTLEnvironment()
    }
}

struct VoteOptionSection: View {
    let option: PollOption
    let optionIndex: Int
    let currentUserId: String
    var voters: [ChatPollVoterRow] = []
    var showVoters: Bool = true
    var nextCursor: String? = nil
    var isLoadingMore: Bool = false
    var onLoadMore: (() -> Void)? = nil

    private var actualVoteCount: Int {
        max(option.votes?.count ?? 0, option.voteCount, voters.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("\(optionIndex)")
                    .font(.chatBold(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.chatPrimary)
                    .clipShape(Circle())

                Text(option.text)
                    .font(.chatSemiBold(size: 15))
                    .foregroundColor(.black)
                    .lineLimit(nil)

                Spacer()

                Text("\(actualVoteCount)")
                    .font(.chatBold(size: 15))
                    .foregroundColor(Color.chatPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)

            if showVoters {
                if !voters.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(voters) { vote in
                            HStack(spacing: 12) {
                                KFImage(URL(string: vote.profilePicture ?? ""))
                                    .placeholder {
                                        ZStack {
                                            Circle()
                                                .fill(Color.chatPrimary.opacity(0.15))
                                            Text(String(vote.displayName.prefix(1)).uppercased())
                                                .font(.chatBold(size: 14))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .resizable()
                                    .cancelOnDisappear(true)
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())

                                Text(vote.displayName)
                                    .font(.chatRegular(size: 14))
                                    .foregroundColor(.black)

                                if vote.id.caseInsensitiveCompare(currentUserId) == .orderedSame {
                                    Text(ChatStrings.chat_you.localizedString())
                                        .font(.chatMedium(size: 11))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.chatPrimary)
                                        .clipShape(Capsule())
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.chatSurface)
                        }

                        if let nextCursor, !nextCursor.isEmpty {
                            Button(action: { onLoadMore?() }) {
                                if isLoadingMore {
                                    ProgressView()
                                        .padding(.vertical, 10)
                                } else {
                                    Text("Load more")
                                        .font(.chatMedium(size: 13))
                                        .foregroundColor(Color.chatPrimary)
                                        .padding(.vertical, 10)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .background(Color.chatSurface)
                            .disabled(isLoadingMore)
                        }
                    }
                    .padding(.leading, 28)
                } else if actualVoteCount == 0 {
                    Text(ChatStrings.chat_noVotes.localizedString())
                        .font(.chatRegular(size: 13))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .padding(.leading, 28)
                        .background(Color.chatSurface)
                }
            }

            Divider()
                .padding(.leading, 16)
        }
    }
}

// MARK: - Reaction Users List

struct ReactionUsersListView: View {
    let reactions: [MessageReaction]
    let groupParticipants: [GroupParticipant]
    let headerUserData: UserRes?
    let currentUserId: String
    let currentUserName: String?
    let currentUserFullName: String?
    let currentUserProfilePicture: String?
    let findSenderByUserId: (String) -> (fullName: String?, userName: String?, profilePicture: String?)?
    let onRemoveReaction: (String) -> Void

    @State private var selectedEmojiIndex: Int = 0
    @Environment(\.dismiss) var dismiss

    private var isAllTab: Bool { selectedEmojiIndex == 0 }

    private var totalCount: Int {
        var seen = Set<String>()
        var count = 0
        for reaction in reactions {
            for user in reaction.users {
                if seen.insert(user.userId).inserted { count += 1 }
            }
        }
        return count
    }

    private var displayedUsers: [(user: ReactionUser, emoji: String)] {
        var seen = Set<String>()
        var result: [(user: ReactionUser, emoji: String)] = []
        let source: [(users: [ReactionUser], emoji: String)]
        if isAllTab {
            source = reactions.map { ($0.users, $0.emoji) }
        } else {
            let idx = selectedEmojiIndex - 1
            guard idx >= 0, idx < reactions.count else { return [] }
            source = [(reactions[idx].users, reactions[idx].emoji)]
        }
        for (users, emoji) in source {
            for user in users {
                if seen.insert(user.userId).inserted {
                    result.append((user, emoji))
                }
            }
        }
        return result
    }

    private var selectedReactionEmoji: String {
        let idx = selectedEmojiIndex - 1
        guard idx >= 0, idx < reactions.count else { return "" }
        return reactions[idx].emoji
    }

    private var selectedReactionCount: Int {
        let idx = selectedEmojiIndex - 1
        guard idx >= 0, idx < reactions.count else { return totalCount }
        return reactions[idx].count
    }

    var body: some View {
        VStack(spacing: 0) {
//            if reactions.count > 1 {
                emojiTabBar
//            }
//            reactionHeader
            Divider()
            if displayedUsers.isEmpty {
                emptyState
            } else {
                userList
            }
        }
        .background(Color(UIColor.systemBackground))
        .applyRTLEnvironment()
    }

    private var emojiTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedEmojiIndex = 0
                    }
                } label: {
                    let isSelected = isAllTab
                    HStack(spacing: 4) {
                        Text("All".localizedString())
                            .font(.chat(.semibold, size: 13))
                            .foregroundColor(isSelected ? Color.chatPrimary : .secondary)
                        Text("\(totalCount)")
                            .font(.chat(.medium, size: 13))
                            .foregroundColor(isSelected ? Color.chatPrimary : .secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.chatPrimary.opacity(0.12) : Color.gray.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isSelected ? Color.chatPrimary.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                ForEach(reactions.indices, id: \.self) { index in
                    let reaction = reactions[index]
                    let tabIndex = index + 1
                    let isSelected = tabIndex == selectedEmojiIndex
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedEmojiIndex = tabIndex
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(reaction.emoji)
                                .font(.chat(size: 18))
                            Text("\(reaction.count)")
                                .font(.chat(.medium, size: 13))
                                .foregroundColor(isSelected ? Color.chatPrimary : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.chatPrimary.opacity(0.12) : Color.gray.opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? Color.chatPrimary.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var reactionHeader: some View {
        HStack(spacing: 6) {
            if !isAllTab {
                Text(selectedReactionEmoji)
                    .font(.chat(size: 22))
            }
            Text("\(isAllTab ? totalCount : selectedReactionCount)")
                .font(.chat(.semibold, size: 17))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(ChatStrings.chat_noReactions.localizedString())
                .font(.chat(size: 15))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var userList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(displayedUsers, id: \.user.userId) { pair in
                    reactionUserRow(pair.user, emoji: pair.emoji)
                }
            }
        }
    }

    @ViewBuilder
    private func reactionUserRow(_ user: ReactionUser, emoji: String) -> some View {
        let info = resolvedDisplay(for: user)
        let isCurrentUser = user.userId == currentUserId
        HStack(spacing: 12) {
            if let urlString = info.profileURL, let url = URL(string: urlString) {
                KFImage(url)
                    .placeholder { avatarPlaceholder(info.initial) }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                avatarPlaceholder(info.initial)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isCurrentUser ? ChatStrings.chat_you.localizedString() : info.name)
                    .font(.chat(.medium, size: 15))
                    .foregroundColor(.primary)
                if isCurrentUser {
                    Text(ChatStrings.chat_tapToRemove.localizedString())
                        .font(.chat(size: 13))
                        .foregroundColor(.secondary)
                } else if let userName = info.username, userName != info.name {
                    Text("@\(userName)")
                        .font(.chat(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(emoji)
                .font(.chat(size: 20))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isCurrentUser else { return }
            onRemoveReaction(emoji)
            dismiss()
        }
    }

    private func avatarPlaceholder(_ initial: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.chatPrimary.opacity(0.12))
            Text(initial)
                .font(.chat(.semibold, size: 16))
                .foregroundColor(Color.chatPrimary)
        }
        .frame(width: 40, height: 40)
    }

    private func resolvedDisplay(for user: ReactionUser) -> (initial: String, name: String, username: String?, profileURL: String?) {
        var fullName: String? = user.fullName
        var userName: String? = user.userName
        var profile: String? = user.profilePicture

        if fullName == nil || userName == nil || profile == nil {
            if let participant = groupParticipants.first(where: { $0.userId == user.userId }) {
                if fullName == nil { fullName = participant.fullName }
                if userName == nil { userName = participant.userName }
                if profile == nil { profile = participant.profilePicture }
            }
        }

        if fullName == nil || userName == nil || profile == nil {
            if let header = headerUserData, header.userId == user.userId {
                if fullName == nil { fullName = header.fullName }
                if userName == nil { userName = header.userName }
                if profile == nil { profile = header.profilePicture ?? header.profilePictureDetails?.filePath }
            }
        }

        if fullName == nil || userName == nil || profile == nil {
            if let sender = findSenderByUserId(user.userId) {
                if fullName == nil { fullName = sender.fullName }
                if userName == nil { userName = sender.userName }
                if profile == nil { profile = sender.profilePicture }
            }
        }

        if user.userId == currentUserId {
            if fullName == nil { fullName = currentUserFullName }
            if userName == nil { userName = currentUserName }
            if profile == nil { profile = currentUserProfilePicture }
        }

        let name = fullName ?? userName ?? user.userId
        let initial = String(name.prefix(1)).uppercased()
        return (initial, name, userName, profile)
    }
}
