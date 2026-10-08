//
//  MoreAboutMeTableViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 17/05/24.
//

import UIKit

class MoreAboutMeTableViewCell: UITableViewCell {
    static let identifier = "MoreAboutMeTableViewCell"
    @IBOutlet weak var icon: UIImageView!
    @IBOutlet weak var text1Label: UILabel!
    @IBOutlet weak var text2Label: UILabel!
    @IBOutlet weak var forwardImageView: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
// data:Detail 
//    func setUI(data:AttributesData?,hideForwardImage:Bool? = true){
//        let imgURL = ApiName.imgBaseURL + "\(data?.photo ?? "")"
//        if let imageUrl = URL(string: imgURL) {
//            DispatchQueue.main.async {
//                self.icon.loadImage(with: imageUrl)
//            }
//        }
//        self.text1Label.text = data?.alias?.firstLetterCapitalized
//        let strSel = data?.aOptions?.filter{ attrib in
//            if attrib.isSelected == true {
//                return (attrib.title != nil)
//            }
//            return false
//        }
//        print("arrr....",strSel!)
//        self.text2Label.text = strSel?.count ?? 0 > 0 ? "\(strSel?[0].title ?? "")" : "Add"
//        self.text2Label.textColor = strSel?.count ?? 0 > 0 ? AppColor.Bombay : AppColor.Punch
//        self.forwardImageView.isHidden = hideForwardImage ?? true
//    }

    
    func setUI(data: AttributesData?, hideForwardImage: Bool = true) {
          let imgURL = ApiName.imgBaseURL + "\(data?.photo ?? "")"
          
          if let imageUrl = URL(string: imgURL) {
              DispatchQueue.main.async {
                  self.icon.loadImage(with: imageUrl)
              }
          }

          self.text1Label.text = data?.alias?.firstLetterCapitalized
          
          let strSel = data?.aOptions?.filter { attrib in
              if attrib.isSelected == true {
                  return attrib.title != nil
              }
              return false
          }

          print("arrr....", strSel ?? [])
          
          self.text2Label.text = (strSel?.count ?? 0) > 0 ? (strSel?[0].title ?? "") : "Add"
          self.text2Label.textColor = (strSel?.count ?? 0) > 0 ? AppColor.Bombay : AppColor.Punch
          self.forwardImageView.isHidden = hideForwardImage
      }

    
    
    func setOtherUserDataUI(data:AttributesData,hideForwardImage:Bool? = true){
       
        let imgURL = ApiName.imgBaseURL + "\(data.photo ?? "")"
        if let imageUrl = URL(string: imgURL) {
            DispatchQueue.main.async {
                self.icon.loadImage(with: imageUrl)
            }
        }
        self.text1Label.text = data.alias?.firstLetterCapitalized
        let strSel = data.aOptions?.filter{ attrib in
            if attrib.isSelected == true {
                return (attrib.title != nil)
            }
            return false
        }
        print("arrr....",strSel!)
        self.text2Label.text = strSel?.count ?? 0 > 0 ? "\(strSel?[0].title ?? "")" : "N/A"
        self.forwardImageView.isHidden = hideForwardImage ?? true
    }

}
