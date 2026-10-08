//
//  RewardCollectionViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 19/05/24.
//

import UIKit

class RewardCollectionViewCell: UICollectionViewCell {

    static let identifier = "RewardCollectionViewCell"
    @IBOutlet weak var imageViewWidth: NSLayoutConstraint!
    @IBOutlet weak var imageView: UIImageView!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.imageView.addShadow(color: AppColor.AppBlack.withAlphaComponent(0.2), opacity: 1.0, offset: CGSize(width: 0, height: 0.5))
        self.imageViewWidth.constant = screen.width - 50
        // Initialization code
    }

}
