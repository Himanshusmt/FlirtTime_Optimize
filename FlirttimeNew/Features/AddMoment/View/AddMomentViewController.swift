//
//  AddMomentViewController.swift
//  FlirttimeNew
//
//  FlirtTime's "Add Moment" screen, used by the Home tab to post a moment. Share hands the
//  photos to `MomentsUploadViewModel` and pops right away; the feed shows the upload progress.
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
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var replaceButtonStack: UIStackView!
    @IBOutlet weak var selectedMomentsView: UIView!
    @IBOutlet weak var selectedMomentsCollection: UICollectionView!
    @IBOutlet weak var discardButton: UIButton!
    @IBOutlet weak var textViewheight: NSLayoutConstraint!
    @IBOutlet weak var captionBottomConstraint: NSLayoutConstraint!
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
    @IBOutlet weak var optionsStackView: UIStackView!

    static var storyboardName: StringConvertible {
        return StoryboardName.moments
    }

    /// Called after Share, once the upload has been handed to `MomentsUploadViewModel`.
    var callBackAction: (() -> Void)?

    private let uploadViewModel = MomentsUploadViewModel.shared
    private var addMomentArray: [UIImage] = []
    private let maxImages = 5
    private let maxCaptionLength = 500
//    private var selectedPlace: MomentPlace?
    private var selectedPlace: MomentPlace?

    private lazy var photoPlaceholderView = AddMomentPhotoPlaceholderView(maxPhotos: maxImages)
    private let captionCountLabel = UILabel()
    private var isShowingCaptionPlaceholder = true
    private let photosBar = AddMomentPhotosBar()
    private let locationSection = AddMomentLocationSection()

    override func viewDidLoad() {
        super.viewDidLoad()
        setUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizeCaption()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
    }

    private func setUI() {
        selectedMomentsView.isHidden = true
        addMoreButtonImage.isHidden = false
        profileImageView.layer.cornerRadius = profileImageView.frame.height / 2
        let author = MomentsAuthor.currentUser
        nameLabel.text = author.displayName
        profileImageView.loadImage(path: author.profilePicture, placeholder: UIImage(named: "dummy_Profile"))
        setUpCaptionTextView()
        view3HeighConstraints.constant = 0
        shareButtonValidation(isHide: true)
        setUpCaptionCounter()
        setUpPhotoPlaceholder()
        setUpPhotosBar()
        setUpLocationSection()
    }

    private func setUpPhotosBar() {
        photosBar.onAddMore = { [weak self] in
            guard let self, self.addMomentArray.count < self.maxImages else { return }
            self.openImageSelectionMethodPopUp()
        }
        photosBar.isHidden = true
        optionsStackView.insertArrangedSubview(photosBar, at: 0)
        optionsStackView.setCustomSpacing(8, after: photosBar)
    }

    private func setUpCaptionTextView() {
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.font = .fredoka(.regular, size: 15)
        textView.tintColor = AppColor.Punch
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        showCaptionPlaceholder()
    }

    private func showCaptionPlaceholder() {
        isShowingCaptionPlaceholder = true
        textView.text = Constants.AddMoment.placeholder
        textView.textColor = AppColor.Bombay
    }

    private func setUpCaptionCounter() {
        captionCountLabel.font = .fredoka(.regular, size: 12)
        captionCountLabel.textAlignment = .right
        captionCountLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.superview?.addSubview(captionCountLabel)
        NSLayoutConstraint.activate([
            captionCountLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 2),
            captionCountLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor)
        ])
        updateCaptionCount()
    }

    private func updateCaptionCount() {
        let count = isShowingCaptionPlaceholder ? 0 : textView.text.count
        captionCountLabel.text = "\(count)/\(maxCaptionLength)"
        captionCountLabel.textColor = count >= maxCaptionLength ? AppColor.Punch : AppColor.SilverChalice
        captionCountLabel.accessibilityLabel = "\(count) of \(maxCaptionLength) characters"
    }

    private func setUpPhotoPlaceholder() {
        photoPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        addMoreButtonImage.addSubview(photoPlaceholderView)
        NSLayoutConstraint.activate([
            photoPlaceholderView.topAnchor.constraint(equalTo: addMoreButtonImage.topAnchor, constant: 4),
            photoPlaceholderView.bottomAnchor.constraint(equalTo: addMoreButtonImage.bottomAnchor, constant: -4),
            photoPlaceholderView.leadingAnchor.constraint(equalTo: addMoreButtonImage.leadingAnchor, constant: 16),
            photoPlaceholderView.trailingAnchor.constraint(equalTo: addMoreButtonImage.trailingAnchor, constant: -16)
        ])
        addMoreButtonImage.accessibilityLabel = "Add photos"
        addMoreButtonImage.addTarget(self, action: #selector(placeholderTouchDown), for: [.touchDown, .touchDragEnter])
        addMoreButtonImage.addTarget(self, action: #selector(placeholderTouchUp),
                                     for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    private func setUpLocationSection() {
        locationSection.onAddTapped = { [weak self] in
            self?.openLocationPicker()
        }
        locationSection.onClear = { [weak self] in
            self?.setSelectedPlace(nil)
        }
        guard let captionContainer = textView.superview else { return }
        locationSection.translatesAutoresizingMaskIntoConstraints = false
        captionContainer.addSubview(locationSection)
        captionBottomConstraint.isActive = false
        NSLayoutConstraint.activate([
            locationSection.topAnchor.constraint(equalTo: captionCountLabel.bottomAnchor, constant: 8),
            locationSection.leadingAnchor.constraint(equalTo: captionContainer.leadingAnchor),
            locationSection.trailingAnchor.constraint(equalTo: captionContainer.trailingAnchor),
            locationSection.bottomAnchor.constraint(equalTo: captionContainer.bottomAnchor)
        ])
        setSelectedPlace(nil)
    }

    private func setSelectedPlace(_ place: MomentPlace?) {
        selectedPlace = place
        UIView.performWithoutAnimation {
            locationSection.configure(selected: place)
        }
    }

    private func prepareImages(imageArr: [UIImage]) {
        let count = imageArr.count
        replaceButtonStack.isHidden = count <= 0
        addMoreButtonImage.isHidden = count > 0
        photosBar.isHidden = count == 0
        photosBar.configure(count: count, max: maxImages)
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

    @IBAction func addMomentButtonTappe(_ sender: UIButton) {
        openImageSelectionMethodPopUp()
    }

    @objc private func placeholderTouchDown() {
        photoPlaceholderView.setPressed(true)
    }

    @objc private func placeholderTouchUp() {
        photoPlaceholderView.setPressed(false)
    }

    private func openLocationPicker() {
        view.endEditing(true)
        MomentLocationPickerViewController.present(from: self) { [weak self] place in
            self?.setSelectedPlace(place)
        }
    }

    @IBAction func discardButtonTapped(_ sender: UIButton) {
        if addMomentArray.count > 0 || selectedPlace != nil {
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
        let body = isShowingCaptionPlaceholder ? "" : (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard uploadViewModel.startUpload(images: addMomentArray, caption: body, location: selectedPlace?.displayText) else {
            aCustomToastView.show(message: "Please wait, your last moment is still uploading")
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
        aImageSelectionMethodVC.modalPresentationStyle = .overFullScreen
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

    /// `PHPickerViewController` runs out of process and needs no photo-library permission.
    private func requestPhotoLibraryAccess() {
        openMultipleSelectionLibrary()
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
                self?.cropPickedImages([MomentImageProcessing.prepare(image)])
            }
        }
        aFaceVerificationViewController.modalPresentationStyle = .overFullScreen
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
        guard !results.isEmpty else {
            dismiss(animated: true)
            return
        }
        var pickedImages: [UIImage] = []
        let group = DispatchGroup()
        group.enter()
        dismiss(animated: true) { group.leave() }
        group.enter()
        MomentImageProcessing.loadImages(from: results) { images in
            pickedImages = images
            group.leave()
        }
        group.notify(queue: .main) { [weak self] in
            self?.cropPickedImages(pickedImages)
        }
    }
}

extension AddMomentViewController {

    /// Camera and gallery photos are cropped (resizable window) before being added.
    private func cropPickedImages(_ images: [UIImage]) {
        let room = maxImages - addMomentArray.count
        guard room > 0, !images.isEmpty else { return }
        MomentImageCropViewController.present(images: Array(images.prefix(room)), from: self) { [weak self] cropped in
            self?.addSelectedMomentImages(cropped)
        }
    }
}

// MARK: - Caption
extension AddMomentViewController: UITextViewDelegate {

    /// Pasted text is trimmed to whatever still fits.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let current = textView.text, let swiftRange = Range(range, in: current) else { return true }
        let remaining = maxCaptionLength - (current.count - current[swiftRange].count)
        guard text.count > remaining else { return true }
        guard remaining > 0 else { return false }
        let inserted = String(text.prefix(remaining))
        textView.text = (current as NSString).replacingCharacters(in: range, with: inserted)
        textView.selectedRange = NSRange(location: range.location + (inserted as NSString).length, length: 0)
        textViewDidChange(textView)
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        if textView.text.count > maxCaptionLength {
            textView.text = String(textView.text.prefix(maxCaptionLength))
        }
        updateCaptionCount()
        resizeCaption()
        scrollCaretIntoView()
    }

    /// The caption grows with its text; the page scrolls instead of the text view.
    private func resizeCaption() {
        let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let height = max(35, ceil(fitting.height))
        guard textViewheight.constant != height else { return }
        textViewheight.constant = height
        view.layoutIfNeeded()
    }

    private func scrollCaretIntoView() {
        guard let caret = textView.selectedTextRange?.end,
              let pageScrollView = sequence(first: textView.superview, next: { $0?.superview })
                .compactMap({ $0 as? UIScrollView }).first else { return }
        let caretRect = textView.caretRect(for: caret).insetBy(dx: 0, dy: -12)
        pageScrollView.scrollRectToVisible(textView.convert(caretRect, to: pageScrollView), animated: false)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        guard isShowingCaptionPlaceholder else { return }
        isShowingCaptionPlaceholder = false
        textView.text = nil
        textView.textColor = AppColor.MineShaft
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showCaptionPlaceholder()
            resizeCaption()
        }
        updateCaptionCount()
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
