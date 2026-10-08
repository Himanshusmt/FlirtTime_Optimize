//
//  EditMovementViewController.swift
//  FlirttimeNew
//
//  FlirtTime's "Edit image" screen: replace, remove or add photos before sharing.
//

import UIKit
import AVFoundation
import Photos
import PhotosUI

class EditMovementViewController: BaseViewController, Instantiable {
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var doneButton: UIButton!
    @IBOutlet weak var addMoreButton: UIButton!
    @IBOutlet weak var editImageCollectionView: UICollectionView!

    static var storyboardName: StringConvertible {
        return StoryboardName.moments
    }

    var images: [UIImage] = []
    var maxImages = 5
    var onImagesUpdated: (([UIImage]) -> Void)?

    private var selectedIndexToReplace: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        editImageCollectionView.reloadData()
        updateAddMoreButtonVisibility()
    }

    private func updateAddMoreButtonVisibility() {
        addMoreButton.isHidden = images.count >= maxImages
    }

    @IBAction func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction func doneButtonTapped(_ sender: UIButton) {
        onImagesUpdated?(images)
        navigationController?.popViewController(animated: true)
    }

    @IBAction func addMoreButtonTapped(_ sender: UIButton) {
        selectedIndexToReplace = nil
        guard images.count < maxImages else { return }
        openImageSelectionMethodPopUp()
    }

    private func openImageSelectionMethodPopUp() {
        let aImageSelectionMethodVC: ImageSelectionMethodVC = ImageSelectionMethodVC.instantiateFromStoryboard()
        aImageSelectionMethodVC.callBack = { [weak self] isCamera in
            DispatchQueue.main.async {
                if isCamera {
                    self?.checkCameraAuthorization()
                } else {
                    self?.requestPhotoLibraryAccess()
                }
            }
        }
        aImageSelectionMethodVC.modalPresentationStyle = .overCurrentContext
        navigationController?.present(aImageSelectionMethodVC, animated: true, completion: nil)
    }

    private func apply(_ image: UIImage) {
        if let index = selectedIndexToReplace, images.indices.contains(index) {
            images[index] = image
            editImageCollectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        } else if images.count < maxImages {
            images.append(image)
            editImageCollectionView.reloadData()
            let last = IndexPath(item: images.count - 1, section: 0)
            editImageCollectionView.scrollToItem(at: last, at: .centeredVertically, animated: true)
        }
        selectedIndexToReplace = nil
        updateAddMoreButtonVisibility()
    }
}

extension EditMovementViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        images.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EditImageCollCell.identifier, for: indexPath) as? EditImageCollCell else {
            return UICollectionViewCell()
        }
        cell.editImageView.image = images[indexPath.item]
        cell.onDeleteTapped = { [weak self, weak cell] in
            guard let self, let cell,
                  let indexPath = self.editImageCollectionView.indexPath(for: cell) else { return }
            self.images.remove(at: indexPath.item)
            self.editImageCollectionView.deleteItems(at: [indexPath])
            if self.images.isEmpty {
                self.onImagesUpdated?(self.images)
                self.navigationController?.popViewController(animated: true)
            }
            self.updateAddMoreButtonVisibility()
        }
        cell.onReplaceTapped = { [weak self, weak cell] in
            guard let self, let cell,
                  let indexPath = self.editImageCollectionView.indexPath(for: cell) else { return }
            self.selectedIndexToReplace = indexPath.item
            self.openImageSelectionMethodPopUp()
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        return CGSize(width: width, height: width * 375 / 393)
    }
}

// MARK: - Camera / photo library
extension EditMovementViewController {

    private func requestPhotoLibraryAccess() {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    self?.openSingleSelectionLibrary()
                } else {
                    self?.showPhotoLibraryAccessAlert()
                }
            }
        }
    }

    private func checkCameraAuthorization() {
        let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
            showCameraAccessAlert()
            return
        }
        let aFaceVerificationViewController: FaceVerificationViewController = FaceVerificationViewController.instantiateFromStoryboard()
        aFaceVerificationViewController.headerText = Constants.ProfileVerification.clickPhoto
        aFaceVerificationViewController.isHideScanningImage = true
        aFaceVerificationViewController.callBackAction = { [weak self] image in
            guard let image else { return }
            DispatchQueue.main.async {
                self?.apply(MomentImageProcessing.prepare(image))
            }
        }
        aFaceVerificationViewController.modalPresentationStyle = .overCurrentContext
        navigationController?.present(aFaceVerificationViewController, animated: true, completion: nil)
    }
}

extension EditMovementViewController: PHPickerViewControllerDelegate {

    private func openSingleSelectionLibrary() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let phPicker = PHPickerViewController(configuration: config)
        phPicker.delegate = self
        present(phPicker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard !results.isEmpty else {
            selectedIndexToReplace = nil
            return
        }
        MomentImageProcessing.loadImages(from: results) { [weak self] images in
            guard let image = images.first else { return }
            self?.apply(image)
        }
    }
}
