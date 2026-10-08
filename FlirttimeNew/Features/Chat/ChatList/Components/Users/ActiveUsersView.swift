//
//  ActiveUsersView.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

struct ActiveUsersView: View {
    let users: [ChatMessageRow]
    let onUserTap: (ChatMessageRow) -> Void
    let onlineUserIds: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ChatStrings.chat_activeUsers.localizedString())
                    .font(.chatMedium(size: 16))
                Spacer()
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(uniqueActiveChatUsers.prefix(24), id: \.id) { user in
                        Button(action: {
                            onUserTap(user)
                        }) {
                            VStack(spacing: 4) {
                                ZStack(alignment: .bottomTrailing) {
                                    let userDetails = user.getUserDetails()
                                    UserAvatarView(
                                        urlString: userDetails?.profilePicture,
                                        isGroup: false,
                                        groupTitle: nil,
                                        groupParticipants: nil,
                                        userDetails: userDetails
                                    )

                                    // Online indicator
                                    Circle()
                                        .fill(kGreen)
                                        .frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(kWhite, lineWidth: 2))
                                        .offset(x: 4, y: -4)
                                }

                                let userDetails = user.getUserDetails()
                                Text(userDetails?.fullName ?? userDetails?.userName ?? user.title ?? "-")
                                    .font(.chatMedium(size: 12))
                                    .lineLimit(1)
                                    .frame(width: 60)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .animation(.default, value: uniqueActiveChatUsers.map { $0.id ?? "" })
            }
            .frame(height: 82)
        }
        .applyRTLEnvironment()
    }
    
    private var uniqueActiveChatUsers: [ChatMessageRow] {
        let uniqueUsers = users.reduce(into: [String: ChatMessageRow]()) { result, chatRow in
            if let userDetails = chatRow.getUserDetails(), let userId = userDetails.userId {
                result[userId] = chatRow
            }
        }

        // Filter for users that are online based on onlineUserIds, then sort alphabetically
        return Array(uniqueUsers.values).filter { chat in
            if chat.settings?.isBlocked == true { return false }
            if let userDetails = chat.getUserDetails(),
               let userId = userDetails.userId {
                if BlockedUsersManager.shared.isBlocked(id: userId) { return false }
                return onlineUserIds.contains(userId)
            }
            return false
        }.sorted { chat1, chat2 in
            let name1 = chat1.getUserDetails()?.fullName ?? chat1.getUserDetails()?.userName ?? chat1.title ?? ""
            let name2 = chat2.getUserDetails()?.fullName ?? chat2.getUserDetails()?.userName ?? chat2.title ?? ""
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
    }
}
