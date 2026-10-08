//
//  AddMomentViewController.swift
//  FlirttimeNew
//
//  FlirtTime's "Add Moment" screen, used by the Home tab to post a vibe. Share hands the
//  photos to `VibeUploadViewModel` and pops right away; the feed shows the upload progress.
//

import UIKit
import AVFoundation
import Photos
import PhotosUI

class AddMomentCell: UITableViewCell {
    @IBOutlet weak var labelName: UILabel!
    static let identifier = "AddMomentCell"
}

class AddMomentViewController: BaseViewController, Instantiable {
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var threeDotButton: UIButton!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var addMoreButton: UIButton!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var replaceButtonStack: UIStackView!
    @IBOutlet weak var selectedMomentsView: UIView!
    @IBOutlet weak var selectedMomentsCollection: UICollectionView!
    @IBOutlet weak var discardButton: UIButton!
    @IBOutlet weak var textViewheight: NSLayoutConstraint!
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var tagTextView: UITextView!
    @IBOutlet weak var tagTextViewHeight: NSLayoutConstraint!

    @IBOutlet weak var view1: UIView!
    @IBOutlet weak var img11: UIImageView!
    @IBOutlet weak var img12: UIImageView!

    @IBOutlet weak var view2: UIView!
    @IBOutlet weak var img21: UIImageView!
    @IBOutlet weak var img22: UIImageView!
    @IBOutlet weak var img23: UIImageView!
    @IBOutlet weak var img24: UIImageView!

    @IBOutlet weak var view3: UIView!
    @IBOutlet weak var img31: UIImageView!
    @IBOutlet weak var img32: UIImageView!
    @IBOutlet weak var img33: UIImageView!
    @IBOutlet weak var img34: UIImageView!
    @IBOutlet weak var img35: UIImageView!

    @IBOutlet weak var view3HeighConstraints: NSLayoutConstraint!
    @IBOutlet weak var addMoreButtonImage: UIButton!

    static var storyboardName: StringConvertible {
        return StoryboardName.moments
    }

    /// Called after Share, once the upload has been handed to `VibeUploadViewModel`.
    var callBackAction: (() -> Void)?

    private let uploadViewModel = VibeUploadViewModel.shared
    private var addMomentArray: [UIImage] = []
    private let maxImages = MockVibeStore.maxImagesPerVibe
    private let maxCaptionLength = 500

    override func viewDidLoad() {
        super.viewDidLoad()
        setUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
    }

    private func setUI() {
        addMoreButton.isHidden = true
        selectedMomentsView.isHidden = true
        addMoreButtonImage.isHidden = false
        profileImageView.layer.cornerRadius = profileImageView.frame.height / 2
        let author = MockVibeStore.shared.currentUserAuthor
        nameLabel.text = author.displayName
        profileImageView.loadImage(path: author.profilePicture, placeholder: UIImage(named: "dummy_Profile"))
        textView.delegate = self
        textView.text = Constants.AddMoment.placeholder
        textView.textColor = UIColor.lightGray
        view3HeighConstraints.constant = 0
        shareButtonValidation(isHide: true)
    }

    private func prepareImages(imageArr: [UIImage]) {
        let count = imageArr.count
        replaceButtonStack.isHidden = count <= 0
        addMoreButtonImage.isHidden = count > 0
        addMoreButton.isHidden = count == 0 || count >= maxImages
        view1.isHidden = true
        view2.isHidden = true
        view3.isHidden = true
        view3HeighConstraints.constant = 0
        shareButtonValidation(isHide: count == 0)
        switch count {
        case 1:
            view1.isHidden = false
            img12.isHidden = true
            img11.image = imageArr[0]

        case 2:
            view1.isHidden = false
            img12.isHidden = false
            img11.image = imageArr[0]
            img12.image = imageArr[1]

        case 3...4:
            view2.isHidden = false
            img24.isHidden = count != 4
            img21.image = imageArr[0]
            img22.image = imageArr[1]
            img23.image = imageArr[2]
            if count == 4 {
                img24.image = imageArr[3]
            }

        case 5:
            view3.isHidden = false
            view3HeighConstraints.constant = 125.0
            img31.image = imageArr[0]
            img32.image = imageArr[1]
            img33.image = imageArr[2]
            img34.image = imageArr[3]
            img35.image = imageArr[4]

        default:
            break
        }
    }

    private func shareButtonValidation(isHide: Bool) {
        shareButton.backgroundColor = isHide ? AppColor.Punch.withAlphaComponent(0.5) : AppColor.Punch
        shareButton.isUserInteractionEnabled = !isHide
    }

    // MARK: - Actions

    @IBAction func addMoreMomentButtonTapped(_ sender: UIButton) {
        guard addMomentArray.count < maxImages else { return }
        openImageSelectionMethodPopUp()
    }

    @IBAction func addMomentButtonTappe(_ sender: UIButton) {
        openImageSelectionMethodPopUp()
    }

    @IBAction func discardButtonTapped(_ sender: UIButton) {
        if addMomentArray.count > 0 {
            aDeleteCustomPopUp.show(message: Constants.AddMoment.discard, button1Text: Constants.AlertButtons.cancel, button2Text: Constants.AlertButtons.yesDiscard) {
                self.navigationController?.popViewController(animated: true)
            }
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @IBAction func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction func shareButtonTapped(_ sender: UIButton) {
        guard !addMomentArray.isEmpty else { return }
        var body = textView.text ?? ""
        if body == Constants.AddMoment.placeholder {
            body = ""
        }
        guard uploadViewModel.startUpload(images: addMomentArray, caption: body) else {
            aCustomToastView.show(message: "Please wait, your last vibe is still uploading")
            return
        }
        textView.resignFirstResponder()
        callBackAction?()
        navigationController?.popViewController(animated: true)
    }

    @IBAction func editButtonTapped(_ sender: UIButton) {}

    @IBAction func replaceButtonTapped(_ sender: UIButton) {
        let editVC: EditMovementViewController = EditMovementViewController.instantiateFromStoryboard()
        editVC.images = addMomentArray
        editVC.maxImages = maxImages
        editVC.onImagesUpdated = { [weak self] updatedImages in
            guard let self else { return }
            self.addMomentArray = updatedImages
            self.prepareImages(imageArr: self.addMomentArray)
        }
        navigationController?.pushViewController(editVC, animated: true)
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

    private func addSelectedMomentImages(_ images: [UIImage]) {
        let room = maxImages - addMomentArray.count
        guard room > 0, !images.isEmpty else { return }
        addMomentArray.append(contentsOf: images.prefix(room))
        prepareImages(imageArr: addMomentArray)
    }
}

// MARK: - Camera / photo library
extension AddMomentViewController {

    private func requestPhotoLibraryAccess() {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    self?.openMultipleSelectionLibrary()
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
                self?.addSelectedMomentImages([MomentImageProcessing.prepare(image)])
            }
        }
        aFaceVerificationViewController.modalPresentationStyle = .overCurrentContext
        navigationController?.present(aFaceVerificationViewController, animated: true, completion: nil)
    }
}

extension AddMomentViewController: PHPickerViewControllerDelegate {

    private func openMultipleSelectionLibrary() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = max(maxImages - addMomentArray.count, 1)
        let phPicker = PHPickerViewController(configuration: config)
        phPicker.delegate = self
        present(phPicker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        MomentImageProcessing.loadImages(from: results) { [weak self] images in
            self?.addSelectedMomentImages(images)
        }
    }
}

// MARK: - Caption
extension AddMomentViewController: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        if textView.text.count > maxCaptionLength {
            textView.text = String(textView.text.prefix(maxCaptionLength))
        }
        guard let lineHeight = textView.font?.lineHeight, lineHeight > 0 else { return }
        let numberOfLines = textView.contentSize.height / lineHeight
        textViewheight.constant = Int(numberOfLines) > 5 ? 113.0 : textView.contentSize.height
        textView.layoutIfNeeded()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == UIColor.lightGray {
            textView.text = nil
            textView.textColor = UIColor.black
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty || textView.text == Constants.AddMoment.placeholder {
            textView.text = Constants.AddMoment.placeholder
            textView.textColor = UIColor.lightGray
            textViewheight.constant = 35
        }
    }
}

// The tag suggestions table is wired in the storyboard but the tags row is hidden.
extension AddMomentViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        UITableViewCell()
    }
}

/// Shared photo handling for Add Moment and Edit image.
enum MomentImageProcessing {

    static let maxDimension: CGFloat = 1600

    static func prepare(_ image: UIImage) -> UIImage {
        let fixed = image.fixedOrientation()
        let longest = max(fixed.size.width, fixed.size.height)
        guard longest > maxDimension else { return fixed }
        let scale = maxDimension / longest
        let size = CGSize(width: fixed.size.width * scale, height: fixed.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            fixed.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Loads picker results in selection order.
    static func loadImages(from results: [PHPickerResult], completion: @escaping ([UIImage]) -> Void) {
        var loaded = [UIImage?](repeating: nil, count: results.count)
        let group = DispatchGroup()
        for (index, result) in results.enumerated() {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    let prepared = prepare(image)
                    DispatchQueue.main.async { loaded[index] = prepared }
                }
                DispatchQueue.main.async { group.leave() }
            }
        }
        group.notify(queue: .main) {
            completion(loaded.compactMap { $0 })
        }
    }
}
