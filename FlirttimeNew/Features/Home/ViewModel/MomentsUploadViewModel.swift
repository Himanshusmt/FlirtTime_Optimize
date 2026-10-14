//
//  MomentsUploadViewModel.swift
//  FlirttimeNew
//
//  Background moment upload started from Add Moment: each photo goes straight to S3 through a
//  presigned URL, then `POST api/v1/moments` saves the URLs. `uploadProgress` drives the feed's bar.
//

import UIKit
import Combine
import RxSwift
import Swinject

final class MomentsUploadViewModel {

    static let shared = MomentsUploadViewModel()
    private init() {}

    /// `nil` while idle, otherwise the displayed progress from 0 to 1.
    @Published private(set) var uploadProgress: Float?

    /// Emits once per upload, after the bar has reached 100% (or immediately on failure).
    let uploadFinished = PassthroughSubject<Result<MomentsPost, MomentsError>, Never>()

    var isUploading: Bool { uploadProgress != nil }

    private lazy var sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()

    private static let maxImages = 5
    private static let maxImageBytes = 5 * 1024 * 1024
    private static let s3Folder = "moments"

    private var uploadID = UUID()
    private var timer: Timer?
    private var displayProgress: Float = 0
    private var targetProgress: Float = 0
    private var createdVibe: MomentsPost?

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
        animateProgress(to: 0.05)

        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let imageData = images.prefix(Self.maxImages).compactMap(Self.jpegData(for:))
            DispatchQueue.main.async {
                guard let self, id == self.uploadID else { return }
                guard !imageData.isEmpty else {
                    self.fail(with: "Couldn't prepare your photos.")
                    return
                }
                self.uploadImage(at: 0, of: imageData, caption: caption, location: location, uploaded: [], id: id)
            }
        }
        return true
    }

    func cancel() {
        uploadID = UUID()
        stopTimer()
        createdVibe = nil
        uploadProgress = nil
    }

    // MARK: - Steps

    /// One step per photo plus a final step for creating the moment. Any failed photo fails the upload.
    private func uploadImage(at index: Int, of images: [Data], caption: String, location: String?,
                             uploaded: [PresignedUpload], id: UUID) {
        guard id == uploadID else { return }
        guard index < images.count else {
            createMoment(caption: caption, location: location, uploaded: uploaded, id: id)
            return
        }
        animateProgress(to: Float(index + 1) / Float(images.count + 1))

        sessionManager.uploadImageToS3(images[index], folder: Self.s3Folder)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] upload in
                self?.uploadImage(at: index + 1, of: images, caption: caption, location: location,
                                 uploaded: uploaded + [upload], id: id)
            }, onFailure: { [weak self] error in
                guard let self, id == self.uploadID else { return }
                self.fail(with: parseError(error) ?? "Photo upload failed")
            })
            .disposed(by: disposeBag)
    }

    private func createMoment(caption: String, location: String?, uploaded: [PresignedUpload], id: UUID) {
        let imageKeys = uploaded.compactMap(\.resolvedKey)
        guard imageKeys.count == uploaded.count else {
            fail(with: "Photo upload failed")
            return
        }
        sessionManager.createMoment(caption: caption, location: location, imageKeys: imageKeys)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] vibe in
                guard let self, id == self.uploadID else { return }
                self.createdVibe = vibe ?? self.placeholderVibe(caption: caption)
                self.animateProgress(to: 1)
            }, onFailure: { [weak self] error in
                guard let self, id == self.uploadID else { return }
                self.fail(with: parseError(error) ?? "Unable to post your moment")
            })
            .disposed(by: disposeBag)
    }

    /// Used only when the backend doesn't return the created moment; image URLs come from the backend,
    /// so the feed refreshes to show it.
    private func placeholderVibe(caption: String) -> MomentsPost {
        let author = MomentsAuthor.currentUser
        return MomentsPost(id: UUID().uuidString,
             userId: author.userId,
             caption: caption,
             media: [],
             likesCount: 0,
             commentsCount: 0,
             giftCount: 0,
             hasLiked: false,
             createdAt: MomentsDate.string(from: Date()),
             author: author)
    }

    /// JPEG under the backend's 5 MB limit, lowering quality and then size until it fits.
    private static func jpegData(for image: UIImage) -> Data? {
        var current = image
        for _ in 0..<4 {
            for quality in [0.8, 0.6, 0.4] as [CGFloat] {
                if let data = current.jpegData(compressionQuality: quality), data.count <= maxImageBytes {
                    return data
                }
            }
            let size = CGSize(width: current.size.width * current.scale * 0.7,
                              height: current.size.height * current.scale * 0.7)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let source = current
            current = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        return nil
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
