//
//  ImageCollectionViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 09/05/24.
//

import UIKit

class ImageCollectionViewCell: UICollectionViewCell {

    static let identifier = "ImageCollectionViewCell"
    @IBOutlet weak var backgroundImage: UIImageView!
    @IBOutlet weak var userProfileImage: UIImageView!
    @IBOutlet weak var editImage1View: UIView!
    @IBOutlet weak var editOtherImagesView: UIView!
    @IBOutlet weak var deleteButton: UIButton!
    @IBOutlet weak var imageDeleButton: UIButton!
    @IBOutlet weak var imgProfile: UIImageView!
    var completion:((Int?)->())?
    var imageID:Int?
    var deleteAction:(()-> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
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
        self.imageDeleButton.isHidden = image != nil ? (index == 0) : true
       // self.editOtherImagesView.isHidden = image != nil ? index == 0 : true
        if let image = image {
            self.imageID = image.id
            self.backgroundImage.image = image.image
            self.userProfileImage.image = image.image
            self.userProfileImage.contentMode = .scaleAspectFit
        }else{
            let placeHolderImage = UIImage(named: "imageSelectPlaceHolder")
            [self.userProfileImage,self.backgroundImage].forEach { image in
                image.image = placeHolderImage
                image.contentMode = .scaleToFill
                image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
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
    
//    func setAddInterestPlaceholderImageUI(){
//        let placeHolderImage = UIImage(named: "addInterestPlaceHolderImage")
//        self.userProfileImage.image = placeHolderImage
////        self.userProfileImage.image = placeHolderImage?.resizePlaceHolderImage(width: width, height: height,noOfitemsInRow: noOfitemsInRow)
//        self.userProfileImage.contentMode = .scaleAspectFit
//    }

    @IBAction func edit1stImageButtonTapped(_ sender: UIButton) {
        guard let action = completion else { return }
        action(imageID)
    }

    @IBAction func editRestImagesButtonTapped(_ sender: UIButton) {
        guard let action = completion else { return }
        action(imageID)
    }
    
    @IBAction func deleteImageButtonTapped(_ sender: UIButton) {
        guard let action = completion else { return }
        action(imageID)
    }

    
}
