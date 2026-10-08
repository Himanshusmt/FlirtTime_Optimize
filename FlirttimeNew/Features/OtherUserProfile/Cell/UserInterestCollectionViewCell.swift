//
//  UserInterestCollectionViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 16/05/24.
//

import UIKit

class UserInterestCollectionViewCell: UICollectionViewCell {
    static let identifier = "UserInterestCollectionViewCell"
    @IBOutlet weak var labelName: UILabel!
    @IBOutlet weak var interestIcon: UIImageView!
    @IBOutlet weak var mainView: UIView!
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        self.mainView.addShadow(color: AppColor.AppBlack, opacity:0.2, offset: CGSize(width: 0, height: 0.1))
    }
//Interest
    func setData(data:attOptions?){
        self.labelName.text = data?.title
        let imgStr = ApiName.imgBaseURL + (data?.photo ?? "")
        if let imageUrl = URL(string: imgStr) {
            DispatchQueue.main.async {
                self.interestIcon.loadImage(with: imageUrl)
            }
        }
    }
}
