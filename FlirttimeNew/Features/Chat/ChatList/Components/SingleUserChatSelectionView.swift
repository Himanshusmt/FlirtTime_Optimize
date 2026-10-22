//
//  SingleUserChatSelectionView.swift
//  FlirttimeNew
//
//  Created by Awais on 02/09/2025.
//

import SwiftUI
import Kingfisher

struct SingleUserChatSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ChatUserPickerViewModel()
    @State private var searchText = ""

    let currentUserId: String
    let onUserSelected: (SelectableUser) -> Void

    var filteredUsers: [SelectableUser] {
        viewModel.users.filter { user in
            user.id != currentUserId
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar

                if viewModel.isLoading && viewModel.users.isEmpty {
                    loadingView
                } else {
                    usersList
                }
            }
            .navigationTitle(ChatStrings.chat_newChat.localizedString())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        SwiftUI.Image(ChatAssets.back)
                            .rtlMirror()
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .onAppear {
                viewModel.reload(search: nil)
            }
            .onChange(of: searchText) { newValue in
                viewModel.search(text: newValue)
            }
            .dismissKeyboardOnTap()
            .applyRTLEnvironment()
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            SwiftUI.Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.chat(size: 16))
            
            RTLTextField(ChatStrings.chat_searchUsers.localizedString(), text: $searchText, fontSize: 16)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    SwiftUI.Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.chat(size: 16))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(25)
        .padding(.horizontal)
        .padding(.bottom, 16)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color.chatPrimary))
                .scaleEffect(1.2)
            
            Text(ChatStrings.chat_loadingUsers.localizedString())
                .font(.chatRegular(size: 16))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Users List
    private var usersList: some View {
        List {
            ForEach(filteredUsers) { user in
                userRow(user)
                    .onAppear {
                        viewModel.loadMoreIfNeeded(currentItem: user)
                    }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            viewModel.reload(search: searchText.isEmpty ? nil : searchText)
        }
    }
    
    // MARK: - User Row
    private func userRow(_ user: SelectableUser) -> some View {
        HStack(spacing: 12) {
            // Avatar
            avatarView(for: user, size: 50)
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.chatMedium(size: 16))
                    .foregroundColor(.black)
                
                Text("@\(user.username)")
                    .font(.chatRegular(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Arrow indicator
            SwiftUI.Image(systemName: "chevron.right")
                .flipsForRightToLeftLayoutDirection(true)
                .font(.chat(size: 14))
                .foregroundColor(.gray.opacity(0.6))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onUserSelected(user)
            dismiss()
        }
    }
    
    // MARK: - Avatar View
    private func avatarView(for user: SelectableUser, size: CGFloat) -> some View {
        Group {
            if let urlString = user.avatarURL, let url = URL(string: urlString) {
                KFImage(url)
                    .resizable()
                    .cancelOnDisappear(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.chatPrimary.opacity(0.7), Color.chatPrimaryDark.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(user.name.prefix(1)).uppercased())
                            .font(.chatBold(size: size / 2.4))
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

// MARK: - Forward Recipients (multi-select)

struct ForwardRecipientPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ForwardRecipientPickerViewModel()
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []

    let currentUserId: String
    let onForward: ([String]) -> Void

    var filteredUsers: [SelectableUser] {
        viewModel.users.filter { $0.id != currentUserId }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar

                if viewModel.isLoading && viewModel.users.isEmpty {
                    loadingView
                } else if filteredUsers.isEmpty {
                    emptyView
                } else {
                    usersList
                }

                if !selectedIds.isEmpty {
                    sendBar
                }
            }
            .navigationTitle(ChatStrings.chat_forwardTo.localizedString())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        SwiftUI.Image(ChatAssets.back)
                            .rtlMirror()
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .onAppear {
                if viewModel.users.isEmpty && !viewModel.isLoading {
                    viewModel.reload(search: searchText.isEmpty ? nil : searchText)
                }
            }
            .onChange(of: searchText) { newValue in
                viewModel.search(text: newValue)
            }
            .dismissKeyboardOnTap()
            .applyRTLEnvironment()
        }
    }

    private var searchBar: some View {
        HStack {
            SwiftUI.Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.chat(size: 16))

            RTLTextField(ChatStrings.chat_searchUsers.localizedString(), text: $searchText, fontSize: 16)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    SwiftUI.Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.chat(size: 16))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(25)
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color.chatPrimary))
                .scaleEffect(1.2)

            Text(ChatStrings.chat_loadingUsers.localizedString())
                .font(.chatRegular(size: 16))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Text(
                searchText.isEmpty
                    ? ChatStrings.chat_noContactsFound.localizedString()
                    : ChatStrings.chat_noResultsFound.localizedString()
            )
            .font(.chatRegular(size: 16))
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var usersList: some View {
        List {
            ForEach(filteredUsers) { user in
                userRow(user)
                    .onAppear {
                        viewModel.loadMoreIfNeeded(currentItem: user)
                    }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            viewModel.reload(search: searchText.isEmpty ? nil : searchText)
        }
    }

    private func userRow(_ user: SelectableUser) -> some View {
        let isSelected = selectedIds.contains(user.id)
        return HStack(spacing: 12) {
            avatarView(for: user, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.chatMedium(size: 16))
                    .foregroundColor(.black)

                if !user.username.isEmpty {
                    Text("@\(user.username)")
                        .font(.chatRegular(size: 14))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            SwiftUI.Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.chat(size: 22))
                .foregroundColor(isSelected ? Color.chatPrimary : .gray.opacity(0.4))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedIds.contains(user.id) {
                selectedIds.remove(user.id)
            } else {
                selectedIds.insert(user.id)
            }
        }
    }

    private var sendBar: some View {
        Button(action: {
            let ids = Array(selectedIds)
            guard !ids.isEmpty else { return }
            dismiss()
            onForward(ids)
        }) {
            HStack {
                Text(ChatStrings.chat_forward.localizedString())
                    .font(.chatMedium(size: 16))
                Text("(\(selectedIds.count))")
                    .font(.chatMedium(size: 16))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.chatPrimary)
            .cornerRadius(14)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    private func avatarView(for user: SelectableUser, size: CGFloat) -> some View {
        Group {
            if let urlString = user.avatarURL, let url = URL(string: urlString) {
                KFImage(url)
                    .resizable()
                    .cancelOnDisappear(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.chatPrimary.opacity(0.7), Color.chatPrimaryDark.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(user.name.prefix(1)).uppercased())
                            .font(.chatBold(size: size / 2.4))
                            .foregroundColor(.white)
                    )
            }
        }
    }
}
