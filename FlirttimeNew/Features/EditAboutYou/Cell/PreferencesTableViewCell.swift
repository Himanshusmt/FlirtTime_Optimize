//
//  PreferencesTableViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabht on 07/05/24.
//

import UIKit

class PreferencesTableViewCell: UITableViewCell {
    
    static let identifier = "PreferencesTableViewCell"

    @IBOutlet weak var mainView: UIStackView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var selectionIcon: UIImageView!
    @IBOutlet weak var imageIcon: UIImageView!


    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

    //GeneralOption
//    func setAboutYouUI(data1:[attOptions],data2:AboutYouModel? = nil){
//           self.titleLabel.text = data1[].title
//           self.titleLabel.textColor = data1?.isSelected ?? false ? AppColor.Punch : AppColor.AppBlack
//           self.titleLabel.font = data1?.isSelected ?? false ? UIFont.fredoka(.medium,size: 16) : UIFont.fredoka(.regular,size: 16)
//           self.selectionIcon.image = data1?.isSelected ?? false ? UIImage(named: "redCircleSelection") : UIImage(named: "whiteCircleSelection")
//           self.mainView.layer.borderWidth = data1?.isSelected ?? false ? 2 : 1
//           self.mainView.layer.borderColor = data1?.isSelected ?? false ? AppColor.Punch.cgColor : AppColor.Iron.cgColor
//           self.imageIcon.isHidden = data2 == nil
//           self.imageIcon.image = UIImage(named: data2?.image ?? "")
//       }
    
    func setAboutYouUI(data1:attOptions, userInfo: UserDetailsData?){
           self.titleLabel.text = data1.title
           self.titleLabel.textColor = data1.isSelected ?? false ? AppColor.Punch : AppColor.AppBlack
           self.titleLabel.font = data1.isSelected ?? false ? UIFont.fredoka(.medium,size: 16) : UIFont.fredoka(.regular,size: 16)
           self.selectionIcon.image = data1.isSelected ?? false ? UIImage(named: "redCircleSelection") : UIImage(named: "whiteCircleSelection")
           self.mainView.layer.borderWidth = data1.isSelected ?? false ? 2 : 1
           self.mainView.layer.borderColor = data1.isSelected ?? false ? AppColor.Punch.cgColor : AppColor.Iron.cgColor
//           self.imageIcon.isHidden = data2 == nil
//           self.imageIcon.image = UIImage(named: data2?.image ?? "")
       }

    func setEditprofileMoreAboutUI(data:MoreAboutOption?){
        self.titleLabel.text = data?.name
        self.titleLabel.textColor = data?.isSelected ?? false ? AppColor.Punch : AppColor.AppBlack
        self.titleLabel.font = data?.isSelected ?? false ? UIFont.fredoka(.medium,size: 16) : UIFont.fredoka(.regular,size: 16)
        self.selectionIcon.image = data?.isSelected ?? false ? UIImage(named: "redCircleSelection") : UIImage(named: "whiteCircleSelection")
        self.mainView.layer.borderWidth = data?.isSelected ?? false ? 2 : 1
        self.mainView.layer.borderColor = data?.isSelected ?? false ? AppColor.Punch.cgColor : AppColor.Iron.cgColor
        self.imageIcon.isHidden = true
    }
}
