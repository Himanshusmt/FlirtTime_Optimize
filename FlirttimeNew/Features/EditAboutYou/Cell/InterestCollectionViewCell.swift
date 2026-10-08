//
//  InterestCollectionViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 08/05/24.
//

import UIKit

class InterestCollectionViewCell: UICollectionViewCell {

    static let identifier = "InterestCollectionViewCell"

    @IBOutlet weak var mainView: UIView!
    @IBOutlet weak var interestIcon: UIImageView!
    @IBOutlet weak var interestTitleLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    //InterestOption
    func setUI(data:attOptions?, userInfo: UserDetailsData?){
        self.interestTitleLabel.text = data?.title
        let imgUrl = ApiName.imgBaseURL + (data?.photo ?? "")
        if let imageUrl = URL(string: imgUrl) {
            DispatchQueue.main.async {
                self.interestIcon.loadImage(with: imageUrl)
            }
        }
        self.interestTitleLabel.textColor = data?.isSelected ?? false ? AppColor.AppWhite : AppColor.AppBlack
        self.mainView.layer.borderColor = data?.isSelected ?? false ? AppColor.Punch.cgColor : AppColor.Iron.cgColor
        self.mainView.backgroundColor = data?.isSelected ?? false ? AppColor.Punch : AppColor.AppWhite
        self.mainView.addShadow(color: AppColor.Amaranth, opacity: data?.isSelected ?? false ?  0.2 : 0.0, offset: CGSize(width: 0, height: 8.0))
    }
}
