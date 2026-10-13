//
//  MomentsUploadViewModel.swift
//  FlirttimeNew
//
//  Background moment upload started from Add Moment, mirroring FlirtTime's
//  `AddMomentViewModel.shared`: each photo is uploaded in turn, then the moment is created,
//  while `uploadProgress` drives the uploading bar on the feed.
//

import UIKit
import Combine

// TODO: replace MockMomentsStore with one multipart image upload per photo (like
// ApiName.momentImageUpload) followed by POST vibes/ { caption, media, location }.
final class MomentsUploadViewModel {

    static let shared = MomentsUploadViewModel()
    private init() {}

    /// `nil` while idle, otherwise the displayed progress from 0 to 1.
    @Published private(set) var uploadProgress: Float?

    /// Emits once per upload, after the bar has reached 100% (or immediately on failure).
    let uploadFinished = PassthroughSubject<Result<MomentsPost, MomentsError>, Never>()

    var isUploading: Bool { uploadProgress != nil }

    private let store = MockMomentsStore.shared
    private let simulatedRequestDelay: TimeInterval = 0.6

    private var uploadID = UUID()
    private var timer: Timer?
    private var displayProgress: Float = 0
    private var targetProgress: Float = 0
    private var createdVibe: MomentsPost?

    private struct Draft {
        let images: [UIImage]
        let caption: String
        let location: String?
    }

    /// Returns `false` if another moment is still uploading.
    @discardableResult
    func startUpload(images: [UIImage], caption: String, location: String? = nil) -> Bool {
        guard !isUploading, !images.isEmpty else { return false }
        let id = UUID()
        uploadID = id
        displayProgress = 0
        targetProgress = 0
        createdVibe = nil
        uploadProgress = 0
        let draft = Draft(images: images, caption: caption, location: location)
        uploadImage(at: 0, of: draft, uploadedPaths: [], id: id)
        return true
    }

    func cancel() {
        uploadID = UUID()
        stopTimer()
        createdVibe = nil
        uploadProgress = nil
    }

    // MARK: - Steps

    /// One step per photo plus a final step for creating the moment.
    private func uploadImage(at index: Int, of draft: Draft, uploadedPaths: [String], id: UUID) {
        guard id == uploadID else { return }
        guard index < draft.images.count else {
            createVibe(from: draft, imagePaths: uploadedPaths, id: id)
            return
        }
        animateProgress(to: Float(index + 1) / Float(draft.images.count + 1))

        let image = draft.images[index]
        DispatchQueue.global(qos: .userInitiated).async { [store, simulatedRequestDelay] in
            let path = store.uploadImage(image)
            DispatchQueue.main.asyncAfter(deadline: .now() + simulatedRequestDelay) { [weak self] in
                // A failed photo is skipped; the upload only fails if none of them made it.
                let paths = uploadedPaths + [path].compactMap { $0 }
                self?.uploadImage(at: index + 1, of: draft, uploadedPaths: paths, id: id)
            }
        }
    }

    private func createVibe(from draft: Draft, imagePaths: [String], id: UUID) {
        guard !imagePaths.isEmpty else {
            fail(with: "Image uploads failed.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + simulatedRequestDelay) { [weak self] in
            guard let self, id == self.uploadID else { return }
            let response = self.store.createVibe(caption: draft.caption, imagePaths: imagePaths, location: draft.location)
            guard response.success == true, let vibe = response.data else {
                self.fail(with: response.message ?? "Unable to post your moment")
                return
            }
            self.createdVibe = vibe
            self.animateProgress(to: 1)
        }
    }

    private func fail(with message: String) {
        stopTimer()
        uploadProgress = nil
        uploadFinished.send(.failure(MomentsError(message: message)))
    }

    private func finish(with vibe: MomentsPost) {
        stopTimer()
        createdVibe = nil
        uploadFinished.send(.success(vibe))
        uploadProgress = nil
    }

    // MARK: - Smooth progress

    private func animateProgress(to target: Float) {
        targetProgress = max(targetProgress, min(target, 1))
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        if displayProgress < targetProgress {
            displayProgress = min(displayProgress + 0.01, targetProgress)
            uploadProgress = displayProgress
        } else if displayProgress >= 1, let vibe = createdVibe {
            finish(with: vibe)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
