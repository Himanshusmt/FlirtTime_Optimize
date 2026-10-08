//
//  UserInteractionCVC.swift
//  FlirtTime
//
//  Created by Smt MacMini on 13/01/25.
//

import UIKit

class UserInteractionCVC: UICollectionViewCell {
    
    static let identifier = "UserInteractionCVC"
    
    @IBOutlet weak var userImage: UIImageView!
    @IBOutlet weak var wdImg: NSLayoutConstraint!
    @IBOutlet weak var imgVerify: UIImageView!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var vwBack: UIView!
    @IBOutlet weak var superLikeImgView: UIImageView!
    
    var blurEffectView: UIVisualEffectView?
    
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        removeBlur()
        superLikeImgView.isHidden = true
    }
    
    func applyBlur() {
        // Prevent multiple blur layers
        if blurEffectView == nil {
            let blurEffect = UIBlurEffect(style: .regular)
            let blurView = UIVisualEffectView(effect: blurEffect)
            blurView.frame = contentView.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(blurView)
            blurEffectView = blurView
        }
    }
    
    func removeBlur() {
        blurEffectView?.removeFromSuperview()
        blurEffectView = nil
    }
}
