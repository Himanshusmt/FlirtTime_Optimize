//
//  ImageCollectionViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 09/05/24.
//

import UIKit

class ImageCollectionViewCell: UICollectionViewCell, UIGestureRecognizerDelegate {

    static let identifier = "ImageCollectionViewCell"
    @IBOutlet weak var backgroundImage: UIImageView!
    @IBOutlet weak var userProfileImage: UIImageView!
    @IBOutlet weak var editImage1View: UIView!
    @IBOutlet weak var editOtherImagesView: UIView!
    @IBOutlet weak var deleteButton: UIButton!
    @IBOutlet weak var imageDeleButton: UIButton!
    @IBOutlet weak var imgProfile: UIImageView!
    var completion:((Int?)->())?
    var editAction:(()-> Void)?
    var imageID:Int?
    var deleteAction:(()-> Void)?
    private var slotTapRecognizer: UITapGestureRecognizer?

    override func awakeFromNib() {
        super.awakeFromNib()
        userProfileImage.clipsToBounds = true
        backgroundImage.clipsToBounds = true
        disableDecorativeTouches()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSlotTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        contentView.addGestureRecognizer(tap)
        slotTapRecognizer = tap
        contentView.bringSubviewToFront(imageDeleButton)
        if let editImage1View {
            contentView.bringSubviewToFront(editImage1View)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        completion = nil
        editAction = nil
        deleteAction = nil
        imageID = nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        if view is UIButton { return false }
        if let imageDeleButton, view.isDescendant(of: imageDeleButton) { return false }
        if let editImage1View, view.isDescendant(of: editImage1View) { return false }
        if let editOtherImagesView, view.isDescendant(of: editOtherImagesView) { return false }
        return true
    }

    @objc private func handleSlotTap() {
        editAction?()
    }

    private func disableDecorativeTouches() {
        backgroundImage?.isUserInteractionEnabled = false
        userProfileImage?.isUserInteractionEnabled = false
        imgProfile?.isUserInteractionEnabled = false
        contentView.subviews.forEach { subview in
            if subview is UIButton { return }
            if subview === editImage1View || subview === editOtherImagesView { return }
            subview.isUserInteractionEnabled = false
        }
        imageDeleButton?.isUserInteractionEnabled = true
        editImage1View?.isUserInteractionEnabled = true
        editOtherImagesView?.isUserInteractionEnabled = true
    }

    func setAboutYouUI(image:AboutYouImageModel?,width:CGFloat,noOfitemsInRow:CGFloat){
        self.imageDeleButton.isHidden = true
        if let image = image {
            self.backgroundImage.image = image.image
            self.userProfileImage.image = image.image
            self.userProfileImage.layer.borderWidth = image.isSelected ?? false ? 2 : 0
            self.userProfileImage.contentMode = .scaleAspectFit
        }else{
            self.userProfileImage.layer.borderWidth = 0
            let placeHolderImage = UIImage(named: "imageSelectPlaceHolder")
            [self.userProfileImage,self.backgroundImage].forEach { image in
                image.image = placeHolderImage
                image.contentMode = .scaleToFill
                image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
        }
        self.userProfileImage.layer.borderColor = AppColor.Punch.cgColor
    }

    func setAddImageUI(image:EditProfileImageModel?,index:Int?){
        self.editImage1View.isHidden = image != nil ? !(index == 0) : true
        self.imageDeleButton.isHidden = image == nil || index == 0
        if let image = image {
            self.imageID = image.id
            [self.userProfileImage, self.backgroundImage].forEach { imageView in
                imageView?.contentMode = .scaleAspectFill
                imageView?.clipsToBounds = true
                if imageView?.image !== image.image {
                    imageView?.image = image.image
                }
            }
        }else{
            self.imageID = nil
            let placeHolderImage = UIImage(named: "imageSelectPlaceHolder")
            [self.userProfileImage,self.backgroundImage].forEach { image in
                image.image = placeHolderImage
                image.contentMode = .scaleToFill
                image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
        }
        disableDecorativeTouches()
        contentView.bringSubviewToFront(imageDeleButton)
        if let editImage1View {
            contentView.bringSubviewToFront(editImage1View)
        }
    }

    func setAddInterestPlaceholderImageUI(width:CGFloat,height:CGFloat,noOfitemsInRow:CGFloat){
        let placeHolderImage = UIImage(named: "addInterestPlaceHolderImage")
        self.userProfileImage.image = placeHolderImage?.resizePlaceHolderImage(width: width, height: height,noOfitemsInRow: noOfitemsInRow)
        self.userProfileImage.contentMode = .scaleAspectFit
    }
    
    func setOtherUserImageUI(image:String){
        self.editImage1View.isHidden = true
        self.editOtherImagesView.isHidden = true
        if image != "" {
            self.userProfileImage.loadImage(with: URL(string: image))
            self.userProfileImage.contentMode = .scaleAspectFill
        }else{
            [self.userProfileImage,self.backgroundImage].forEach { image in
                image?.isHidden = true
            }
        }
    }

    @IBAction func edit1stImageButtonTapped(_ sender: UIButton) {
        if let editAction {
            editAction()
            return
        }
        guard let action = completion else { return }
        action(imageID)
    }

    @IBAction func editRestImagesButtonTapped(_ sender: UIButton) {
        if let editAction {
            editAction()
            return
        }
        guard let action = completion else { return }
        action(imageID)
    }
    
    @IBAction func deleteImageButtonTapped(_ sender: UIButton) {
        if let deleteAction {
            deleteAction()
            return
        }
        guard let action = completion else { return }
        action(imageID)
    }

    
}
