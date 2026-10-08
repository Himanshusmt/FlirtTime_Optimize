//
//  ChatListHeader.swift
//  FlirttimeNew
//

import SwiftUI

struct ChatListHeader: View {
    var body: some View {
        HStack(alignment: .center) {
            Text(ChatStrings.chat_chats.localizedString())
                .font(.chatSemiBold(size: 28))
                .foregroundColor(.chatTextPrimary)
            Spacer()
        }
        .frame(height: 40)
        .padding(.horizontal)
        .padding(.top, 8)
        .applyRTLEnvironment()
    }
}
