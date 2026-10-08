//
//  FloatingActionButton.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import SwiftUI

struct FloatingActionButton: View {
    
    let onNewChat: () -> Void
    
    var body: some View {
        Button(action: { onNewChat() }) {
            ZStack {
                SwiftUI.Image(ChatAssets.edit)
            }
        }
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .applyRTLEnvironment()
    }
}
