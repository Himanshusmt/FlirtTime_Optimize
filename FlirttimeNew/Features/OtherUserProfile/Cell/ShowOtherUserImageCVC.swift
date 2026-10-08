//
//  ShowOtherUserImageCVC.swift
//  FlirtTime
//
//  Created by Smt MacMini on 03/01/25.
//

import UIKit

class ShowOtherUserImageCVC: UICollectionViewCell {
    
    static let identifier = "ShowOtherUserImageCVC"
    
    @IBOutlet weak var imgVW: UIImageView!
    @IBOutlet var pageView:[UIView]!
    @IBOutlet weak var widthImgvwConstraint: NSLayoutConstraint!
    @IBOutlet weak var hieghtImgvwConstraint: NSLayoutConstraint!
    @IBOutlet weak var stackImgVW: UIStackView!
    
    var callBack:((Bool)-> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    @IBAction func btnTapAction(_ sender: Any) {
        guard let action = callBack else { return }
        action(true)
        
    }

}
