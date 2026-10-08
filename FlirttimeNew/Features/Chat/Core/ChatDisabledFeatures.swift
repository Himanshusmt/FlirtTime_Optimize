//
//  ChatDisabledFeatures.swift
//  FlirttimeNew
//

import RxSwift
import UIKit

// FlirtTime chat is 1:1 only. These stand in for OneVibe's channel services so the
// shared chat code (which branches on `isChannel`) compiles; those branches never run.

final class ChannelRepository {
    func getCachedChannel(id: String) -> ChannelSummary? { nil }

    func getCachedChannels() async -> [ChannelSummary] { [] }

    func saveChannelDetails(
        id: String,
        isAdmin: Bool,
        isFollowed: Bool,
        followersCount: Int?,
        name: String? = nil,
        icon: String? = nil,
        shareLink: String? = nil
    ) {}
}

final class ChannelSocketService {
    static let shared = ChannelSocketService()

    func setupSocketListeners() {}

    func invalidateSocketListeners() {}

    func toggleFollow(
        channelId: String,
        channel: ChannelSummary? = nil,
        currentlyFollowing: Bool,
        completion: @escaping (_ newFollowState: Bool) -> Void
    ) {
        completion(currentlyFollowing)
    }

    func deleteChannel(channelId: String, completion: @escaping () -> Void) {}
}

/// Lightweight toast used by the chat screens.
enum GlobalToast {
    static let shared = GlobalToastPresenter()
}

final class GlobalToastPresenter {
    func show(_ message: String) {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }

            let label = PaddingLabel()
            label.text = message
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = UIFont.chat(.medium, size: 14)
            label.textColor = ChatTheme.textOnPrimary
            label.backgroundColor = ChatTheme.textPrimary.withAlphaComponent(0.9)
            label.layer.cornerRadius = 18
            label.clipsToBounds = true
            label.alpha = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            window.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: window.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -90),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -24)
            ])
            UIView.animate(withDuration: 0.2, animations: { label.alpha = 1 }) { _ in
                UIView.animate(withDuration: 0.25, delay: 2, options: [], animations: { label.alpha = 0 }) { _ in
                    label.removeFromSuperview()
                }
            }
        }
    }

    private final class PaddingLabel: UILabel {
        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)))
        }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(width: size.width + 32, height: size.height + 20)
        }
    }
}

extension SessionManager {
    private var channelsUnsupported: Error { APIError.apiError("Channels are not supported in FlirtTime") }

    func sendChannelChatMessage(
        channelId: String,
        body: String? = nil,
        type: String? = nil,
        mediaIds: [String]? = nil,
        clientMessageId: String? = nil,
        replyToId: String? = nil
    ) -> Single<ConversationMessage> {
        .error(channelsUnsupported)
    }

    func getChannelMessages(channelId: String, page: Int = 1, limit: Int = 50) -> Single<ConversationMessagesResponse> {
        .error(channelsUnsupported)
    }

    func getChannelMessagesBefore(channelId: String, beforeDate: Date, page: Int = 1, limit: Int = 20) -> Single<ConversationMessagesResponse> {
        .error(channelsUnsupported)
    }

    func getChannelMessagesAfter(channelId: String, afterDate: Date, limit: Int = 100) -> Single<ConversationMessagesResponse> {
        .error(channelsUnsupported)
    }

    func fetchChatPollVoters(
        pollId: String,
        optionId: String,
        limit: Int = 40,
        cursor: String? = nil,
        page: Int? = nil
    ) -> Single<ChatPollVotersAPIData> {
        .error(APIError.apiError("Polls are not supported in FlirtTime"))
    }
}
