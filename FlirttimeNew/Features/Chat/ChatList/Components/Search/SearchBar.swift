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
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 40)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    SwiftUI.Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(uiColor: AppColor.Boulder))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 52)
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isFocused ? Color.chatPrimary : Color(uiColor: AppColor.Silver), lineWidth: 1.5)
        )
        .shadow(color: Color(uiColor: AppColor.AppBlack).opacity(0.08), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
        .applyRTLEnvironment()
    }
}
