//
//  ChatImagePicker.swift
//  FlirttimeNew
//
//  Created by Awais on 05/08/25.
//

import SwiftUI
import UIKit
import PhotosUI
import Photos
import UniformTypeIdentifiers

enum MediaPickerResult {
    case image(UIImage)
    case video(URL)
}

struct ChatImagePicker: UIViewControllerRepresentable {
    let isCamera: Bool
    var imagesOnly: Bool = false
    var allowsEditing: Bool = false
    let completion: (Result<MediaPickerResult, Error>) -> Void
    
    @Environment(\.presentationMode) var presentationMode

    /// Present picker directly via UIKit — avoids the white flash from SwiftUI `fullScreenCover`.
    /// - Parameter delay: Short delay so confirmation dialogs can finish dismissing first.
    static func present(
        isCamera: Bool,
        imagesOnly: Bool = true,
        allowsEditing: Bool = true,
        delay: TimeInterval = 0.35,
        from source: UIViewController? = nil,
        completion: @escaping (Result<MediaPickerResult, Error>) -> Void
    ) {
        let presentBlock = {
            guard let presenter = source ?? UIApplication.shared.topViewController() else {
                completion(.failure(ImagePickerError.cancelled))
                return
            }
            // Avoid presenting over a VC that is still dismissing (confirmation dialog).
            if presenter.isBeingDismissed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    present(
                        isCamera: isCamera,
                        imagesOnly: imagesOnly,
                        allowsEditing: allowsEditing,
                        delay: 0,
                        from: source,
                        completion: completion
                    )
                }
                return
            }
            if isCamera, !UIImagePickerController.isSourceTypeAvailable(.camera) {
                completion(.failure(ImagePickerError.cancelled))
                return
            }
            if !isCamera, !UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
                completion(.failure(ImagePickerError.cancelled))
                return
            }

            let picker = UIImagePickerController()
            picker.sourceType = isCamera ? .camera : .photoLibrary
            picker.mediaTypes = imagesOnly ? ["public.image"] : ["public.image", "public.movie"]
            picker.allowsEditing = allowsEditing
            picker.modalPresentationStyle = .fullScreen
            if isCamera {
                picker.videoQuality = .typeHigh
                let screen = UIScreen.main.bounds
                let previewHeight = screen.width * (4.0 / 3.0)
                if previewHeight < screen.height {
                    let scale = screen.height / previewHeight
                    picker.cameraViewTransform = CGAffineTransform(scaleX: scale, y: scale)
                }
            }

            let coordinator = PresenterCoordinator(
                isCamera: isCamera,
                allowsEditing: allowsEditing,
                completion: completion
            )
            PresenterCoordinator.retain(coordinator)
            picker.delegate = coordinator
            presenter.present(picker, animated: true)
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: presentBlock)
        } else if Thread.isMainThread {
            presentBlock()
        } else {
            DispatchQueue.main.async(execute: presentBlock)
        }
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = isCamera ? .camera : .photoLibrary
        picker.mediaTypes = imagesOnly ? ["public.image"] : ["public.image", "public.movie"]
        picker.allowsEditing = allowsEditing
        picker.delegate = context.coordinator
        if isCamera {
            picker.modalPresentationStyle = .fullScreen
            picker.videoQuality = .typeHigh

            let screen = UIScreen.main.bounds
            let previewHeight = screen.width * (4.0 / 3.0)
            if previewHeight < screen.height {
                let scale = screen.height / previewHeight
                picker.cameraViewTransform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ChatImagePicker
        
        init(_ parent: ChatImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            
            let image = (parent.allowsEditing ? info[.editedImage] : info[.originalImage]) as? UIImage
                     ?? info[.originalImage] as? UIImage
            if let image {
                let finalImage = parent.isCamera ? ChatImagePicker.cropToScreenAspect(image) : image
                parent.completion(.success(.image(finalImage)))
            } else if let videoURL = info[.mediaURL] as? URL {
                parent.completion(.success(.video(videoURL)))
            } else {
                parent.completion(.failure(ImagePickerError.noMediaSelected))
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.completion(.failure(ImagePickerError.cancelled))
            parent.presentationMode.wrappedValue.dismiss()
        }
    }

    /// Retained while a UIKit-presented picker is on screen.
    private final class PresenterCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private static var active: PresenterCoordinator?

        let isCamera: Bool
        let allowsEditing: Bool
        let completion: (Result<MediaPickerResult, Error>) -> Void

        init(
            isCamera: Bool,
            allowsEditing: Bool,
            completion: @escaping (Result<MediaPickerResult, Error>) -> Void
        ) {
            self.isCamera = isCamera
            self.allowsEditing = allowsEditing
            self.completion = completion
        }

        static func retain(_ coordinator: PresenterCoordinator) {
            active = coordinator
        }

        private func finish(_ result: Result<MediaPickerResult, Error>, picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.completion(result)
                PresenterCoordinator.active = nil
            }
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (allowsEditing ? info[.editedImage] : info[.originalImage]) as? UIImage
                ?? info[.originalImage] as? UIImage
            if let image {
                let finalImage = isCamera ? ChatImagePicker.cropToScreenAspect(image) : image
                finish(.success(.image(finalImage)), picker: picker)
            } else if let videoURL = info[.mediaURL] as? URL {
                finish(.success(.video(videoURL)), picker: picker)
            } else {
                finish(.failure(ImagePickerError.noMediaSelected), picker: picker)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(.failure(ImagePickerError.cancelled), picker: picker)
        }
    }

    fileprivate static func cropToScreenAspect(_ image: UIImage) -> UIImage {
        let screen = UIScreen.main.bounds
        let screenAspect = screen.width / screen.height
        let imgAspect = image.size.width / image.size.height

        guard imgAspect > screenAspect else { return image }

        let cropWidth = image.size.height * screenAspect
        let xOffset = (image.size.width - cropWidth) / 2.0
        let cropRect = CGRect(x: xOffset, y: 0, width: cropWidth, height: image.size.height)

        let scale = image.scale
        let pixelRect = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.size.width * scale,
            height: cropRect.size.height * scale
        )

        guard let cgImage = image.cgImage?.cropping(to: pixelRect) else { return image }
        return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
    }
}

enum ImagePickerError: Error, LocalizedError {
    case noMediaSelected
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .noMediaSelected:
            return "No media was selected"
        case .cancelled:
            return "Media selection was cancelled"
        }
    }
}

struct ChatMultiMediaPicker: UIViewControllerRepresentable {

    var selectionLimit: Int = 10
    let completion: ([MediaPickerResult]) -> Void

    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: Coordinator

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ChatMultiMediaPicker

        init(_ parent: ChatMultiMediaPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let completion = parent.completion
            AppLogger.debug("[ChatMultiMediaPicker] didFinishPicking: \(results.count) item(s)")

            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                AppLogger.debug("[ChatMultiMediaPicker] No results, returning")
                return
            }

            let group = DispatchGroup()
            var ordered: [Int: MediaPickerResult] = [:]
            let lock = NSLock()

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                AppLogger.debug("[ChatMultiMediaPicker] Loading item \(index): hasMovie=\(provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)) canLoadImage=\(provider.canLoadObject(ofClass: UIImage.self))")

                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    // ── Video ──
                    group.enter()
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                        defer { group.leave() }
                        if let error = error {
                            AppLogger.debug("[ChatMultiMediaPicker] Video load error at index \(index): \(error)")
                            return
                        }
                        guard let url = url else {
                            AppLogger.debug("[ChatMultiMediaPicker] Video URL nil at index \(index)")
                            return
                        }
                        // Copy to a stable temp location; the provided URL is only valid inside this block
                        let dest = FileManager.default.temporaryDirectory
                            .appendingPathComponent("\(UUID().uuidString).mp4")
                        do {
                            try FileManager.default.copyItem(at: url, to: dest)
                            AppLogger.debug("[ChatMultiMediaPicker] Video copied to temp at index \(index)")
                            lock.lock(); ordered[index] = .video(dest); lock.unlock()
                        } catch {
                            AppLogger.debug("[ChatMultiMediaPicker] Video copy failed at index \(index): \(error)")
                        }
                    }
                } else if provider.canLoadObject(ofClass: UIImage.self) {
                    // ── Image ──
                    group.enter()
                    provider.loadObject(ofClass: UIImage.self) { object, error in
                        defer { group.leave() }
                        if let error = error {
                            AppLogger.debug("[ChatMultiMediaPicker] Image load error at index \(index): \(error)")
                            return
                        }
                        guard let image = object as? UIImage else {
                            AppLogger.debug("[ChatMultiMediaPicker] Image cast failed at index \(index)")
                            return
                        }
                        AppLogger.debug("[ChatMultiMediaPicker] Image loaded at index \(index), size=\(image.size)")
                        lock.lock(); ordered[index] = .image(image); lock.unlock()
                    }
                } else {
                    AppLogger.debug("[ChatMultiMediaPicker] Item \(index) has unknown type – skipping")
                }
            }

            group.notify(queue: .main) {
                let sorted = ordered.sorted { $0.key < $1.key }.map { $0.value }
                AppLogger.debug("[ChatMultiMediaPicker] All items loaded: \(sorted.count) ready, calling completion")
                completion(sorted)
            }
        }
    }
}

