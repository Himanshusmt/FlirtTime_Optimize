//
//  ChatDetailViewModel+Media.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import Foundation
import UIKit

extension ChatDetailViewModel {

    // MARK: - Send Image / Video

    func sendImage(_ image: UIImage) {
        guard !isBlocked, !shouldShowBlockView else {
            handleError(.userBlockedError, context: "sendImage.blocked")
            return
        }
        mediaManager.sendImage(image)
    }

    func sendVideo(_ url: URL, cropAspect: CGFloat? = nil) {
        guard !isBlocked, !shouldShowBlockView else {
            handleError(.userBlockedError, context: "sendVideo.blocked")
            return
        }
        mediaManager.sendVideo(url, cropAspect: cropAspect)
    }

    func sendMediaAlbum(_ items: [MediaPickerResult]) {
        guard !isBlocked, !shouldShowBlockView else {
            handleError(.userBlockedError, context: "sendMediaAlbum.blocked")
            return
        }
        mediaManager.sendMediaAlbum(items)
    }

    func getCachedMediaData(for messageId: String) -> Data? {
        mediaManager.getCachedMediaData(for: messageId)
    }

    func mediaCacheFirstMatch(forKeyLike key: String) -> Data? {
        mediaManager.mediaCacheFirstMatch(forKeyLike: key)
    }

    func setCachedMediaData(for messageId: String, data: Data) {
        mediaManager.setCachedMediaData(for: messageId, data: data)
    }

    func transferCachedMedia(from oldKey: String, to newKey: String) {
        mediaManager.transferCachedMedia(from: oldKey, to: newKey)
    }

    func removeCachedMediaData(for messageId: String) {
        mediaManager.removeCachedMediaData(for: messageId)
    }

    func updateExistingMessagesWithFreshMedia(_ freshMessages: [ConversationMessage]) {
        mediaManager.updateExistingMessagesWithFreshMedia(freshMessages)
    }

    func autoDownloadMediaIfNeeded(_ message: ConversationMessage) {
        mediaManager.autoDownloadMediaIfNeeded(message)
    }

    func upgradeMediaContentIfNeeded(_ message: ConversationMessage) {
        mediaManager.upgradeMediaContentIfNeeded(message)
    }

    func getFileSize(for url: URL) -> String {
        mediaManager.getFileSize(for: url)
    }

    func saveMediaToGallery(messageId: String, type: MediaStorageType, completion: @escaping (Bool, String?) -> Void) {
        mediaManager.saveMediaToGallery(messageId: messageId, type: type, completion: completion)
    }

}
