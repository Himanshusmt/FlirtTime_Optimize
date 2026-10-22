//
//  SearchBar.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

struct SearchBar: View {
    @Binding var searchText: String
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 10) {
            SwiftUI.Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color.chatPrimary)
                .frame(width: 22, height: 22)
                .rtlMirror()

            RTLTextField(
                ChatStrings.chat_search.localizedString(),
                text: $searchText,
                fontSize: 16,
                isFocused: $isFocused,
                placeholderColor: AppColor.Boulder,
                tintColor: AppColor.Punch
            )
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 40)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    SwiftUI.Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(uiColor: AppColor.Boulder))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 40)
        .padding(4)
        .background(Capsule().fill(Color.white))
        .overlay(
            Capsule()
                .stroke(isFocused ? Color.chatPrimary : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
        .applyRTLEnvironment()
    }
}
