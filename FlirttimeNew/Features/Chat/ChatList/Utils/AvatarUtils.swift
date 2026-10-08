//
//  AvatarUtils.swift
//  FlirttimeNew
//
//  Created by Awais on 02/09/2025.
//

import SwiftUI

struct AvatarUtils {
    
    static func createInitials(from names: [String], maxInitials: Int = 3) -> String {
        let validNames = names.compactMap { name in
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        
        let initials = validNames.prefix(maxInitials).compactMap { name in
            name.first?.uppercased()
        }
        
        return initials.joined()
    }

    static func createInitials(from name: String, maxInitials: Int = 2) -> String {
        return createInitials(from: [name], maxInitials: maxInitials)
    }
    
    static func generateAvatarColors(for name: String) -> [Color] {
        let predefinedColors: [[Color]] = ChatTheme.avatarGradients.map { $0.map { Color(uiColor: $0) } }
        
        // Use string hash to consistently select colors
        let hash = abs(name.hash)
        return predefinedColors[hash % predefinedColors.count]
    }

    static func generateAvatarColor(for name: String) -> Color {
        return  Color.chatPrimary
    }
    
    static func createAvatarView(
        name: String,
        size: CGFloat,
        useGradient: Bool = false,
        maxInitials: Int = 1
    ) -> some View {
        let initials = createInitials(from: name, maxInitials: maxInitials)
        
        return ZStack {
            if useGradient {
                let colors = generateAvatarColors(for: name)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
            } else {
                let color = generateAvatarColor(for: name)
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            }
            
            Text(initials)
                .font(.chat(.bold, size: size * 0.36))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    static func createGroupAvatarView(
        names: [String],
        size: CGFloat,
        useGradient: Bool = false,
        maxInitials: Int = 1
    ) -> some View {
        let initials = createInitials(from: names, maxInitials: maxInitials)
        let combinedName = names.joined(separator: " ")
        
        return ZStack {
            if useGradient {
                let colors = generateAvatarColors(for: combinedName)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
            } else {
                let color = generateAvatarColor(for: combinedName)
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            }
            
            Text(initials)
                .font(.chat(.bold, size: size * 0.36))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Convenience Extensions

extension String {
    var initials: String {
        return AvatarUtils.createInitials(from: self)
    }
    
    var avatarColors: [Color] {
        return AvatarUtils.generateAvatarColors(for: self)
    }
    
    var avatarColor: Color {
        return AvatarUtils.generateAvatarColor(for: self)
    }
}
