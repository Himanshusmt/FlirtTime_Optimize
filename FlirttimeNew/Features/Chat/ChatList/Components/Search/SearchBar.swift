//
//  SearchBar.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

struct SearchBar: View {
    @Binding var searchText: String

    var body: some View {
        HStack {
            SwiftUI.Image(ChatAssets.search)
                .foregroundColor(.black)
                .rtlMirror()

            RTLTextField(ChatStrings.chat_search.localizedString(), text: $searchText)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    SwiftUI.Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.chat(size: 16))
                }
            }
        }
        .padding(10)
        .background(kLightBackground)
        .cornerRadius(24)
        .padding(.horizontal)
        .padding(.top, 4)
        .applyRTLEnvironment()
    }
}
