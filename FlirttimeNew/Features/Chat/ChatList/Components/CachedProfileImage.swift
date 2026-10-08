//
//  CachedProfileImage.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import SwiftUI

struct CachedProfileImage: View {
    let userId: String
    let urlString: String?
    let size: CGFloat
    let isGroup: Bool
    let fallbackName: String

    @State private var cachedImage: UIImage? = nil
    @State private var isLoading = false

    @ObservedObject private var cacheObserver = ProfilePictureCache.shared

    var body: some View {
        Group {
            if let image = cachedImage {
                SwiftUI.Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                AvatarUtils.createAvatarView(
                    name: fallbackName,
                    size: size
                )
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: urlString) { _ in
            isLoading = false
            loadImage()
        }
        .onChange(of: cacheObserver.cacheUpdateCounter) { _ in
            if cachedImage == nil && !isLoading {
                loadImage()
            }
        }
    }

    private func loadImage() {
        guard !userId.isEmpty else { return }

        if let cached = ProfilePictureCache.shared.getCachedImageSync(userId: userId, urlString: urlString) {
            self.cachedImage = cached
            return
        }

        guard !isLoading else { return }

        isLoading = true

        ProfilePictureCache.shared.getImage(userId: userId, urlString: urlString) { image in
            DispatchQueue.main.async {
                if let image {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.cachedImage = image
                    }
                }
                self.isLoading = false
            }
        }
    }
}
