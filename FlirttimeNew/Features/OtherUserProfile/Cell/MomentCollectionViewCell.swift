//
//  MomentCollectionViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 17/05/24.
//

import UIKit

enum screenType{
    case otherUserProfile
    case profile
    case addMoments
}

class MomentCollectionViewCell: UICollectionViewCell {
    static let identifier = "MomentCollectionViewCell"
    @IBOutlet weak var imageViewMoment: UIImageView!
    @IBOutlet weak var deleteMomentButton: UIButton!
    @IBOutlet weak var imageWidth: NSLayoutConstraint!
    @IBOutlet weak var imageHeight: NSLayoutConstraint!
    var deleteMomentCallBack:(()->())?

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        let totalSpacing: CGFloat = 40 + 10 // Leading + Trailing + Interitem
        let cellWidth = (screen.width - totalSpacing) / 2.01
        self.imageWidth.constant = cellWidth
        self.imageHeight.constant = cellWidth * 1.3048
    }

    func setUI(data:UIImage?,width:CGFloat,fromScreen:screenType?){
        switch fromScreen {
        case .otherUserProfile:
            self.imageViewMoment.image = data?.resizeImage(targetSize: CGSize(width: width, height: width * 1.3))
            self.imageViewMoment.contentMode = .scaleToFill
        case .profile:
            break
        case .addMoments:
            self.imageWidth.constant = 187
            self.imageHeight.constant = 187
            self.imageViewMoment.image = data?.resizeImage(targetSize: CGSize(width: width, height: width))
            self.imageViewMoment.contentMode = .scaleAspectFit
            self.imageViewMoment.layer.cornerRadius = 12
            self.deleteMomentButton.isHidden = false
        default:
            break
        }
    }
    
    func setMyMomnetsData(data: [String]?) {
        if data?.count ?? 0 > 0 {
            let imageUrl = "\(ApiName.imgBaseURL)" + "\(data?[0] ?? "")"
            if let imageUrl = URL(string:imageUrl) {
                self.imageViewMoment.loadImage(with: imageUrl,placeholder: UIImage(named: "failed-image-placeholder"))
            }
        }else{
            self.imageViewMoment.image = UIImage(named: "failed-image-placeholder")
        }
        self.imageViewMoment.contentMode = .scaleAspectFill
        self.imageViewMoment.clipsToBounds = true // Prevent overflow
    }
    
    func setUIMomentImg(data:String?){
        let urlImg = ApiName.imgBaseURL + (data ?? "")
        self.imageViewMoment.loadImage(with:URL(string: urlImg))
        self.imageViewMoment.contentMode = .scaleToFill
    }


    @IBAction func deleteMomentButtonTapped(_ sender: UIButton) {
        guard let action = self.deleteMomentCallBack else {return}
        action()
    }

}
