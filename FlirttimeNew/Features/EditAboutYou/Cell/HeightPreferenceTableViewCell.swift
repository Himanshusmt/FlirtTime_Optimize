//
//  HeightPreferenceTableViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 30/05/24.
//

import UIKit

class HeightPreferenceTableViewCell: UITableViewCell {
    
    static let identifier = "HeightPreferenceTableViewCell"
    
    @IBOutlet weak var heightView: UIView!
    @IBOutlet weak var heightTextLabel: UILabel!
    @IBOutlet weak var cellHeight: NSLayoutConstraint!
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    func setUI(data:MoreAboutOption?){
        self.heightView.borderWidth = data?.isSelected ?? false ? 1.0 : 0.0
        self.heightTextLabel.text = data?.name
        self.heightTextLabel.textColor = data?.isSelected ?? false ? AppColor.Punch : AppColor.AppBlack
        cellHeight.constant = data?.isSelected ?? false ? 54.0 : 21.0
    }
    
}
