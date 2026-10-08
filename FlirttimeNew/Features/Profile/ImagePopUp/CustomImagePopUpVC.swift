//
//  CustomImagePopUpVC.swift
//  FlirtTime
//
//  Created by Smt MacMini on 16/01/25.
//

import UIKit

class CustomImagePopUpVC: UIView {
    
    @IBOutlet weak var lblMsg:UILabel!
    @IBOutlet weak var btnDiscard:UIButton!
    @IBOutlet weak var alertVW:UIView!
    
//    var btnStrTitle:String?
//    var strMsg:String?
    
    override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }
    
    private func commonInit() {
            // Load the .xib file
            let nib = UINib(nibName: "CustomImagePopUpVC", bundle: nil)
            guard let view = nib.instantiate(withOwner: self, options: nil).first as? UIView else { return }
            view.frame = self.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
            
        }
    
    func showMessage(btnTitle:String?, msg:String?) {
        
        //self.btnDiscard.setTitle(btnTitle, for: .normal)
        //self.btnDiscard.titleLabel?.font = UIFont(name: "Fredoka-Medium", size: 18.0)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Fredoka-Medium", size: 18)!,
            .foregroundColor: AppColor.AppWhite
        ]
        // Create an attributed string
        let attributedTitle = NSAttributedString(string: btnTitle ?? "", attributes: attributes)
        // Set the attributed title for the button's normal state
        self.btnDiscard.setAttributedTitle(attributedTitle, for: .normal)
        
        self.lblMsg.text = msg
        self.alertVW.cornerRadius = 10
        self.alertVW.clipsToBounds = true
        
        // Add shadow properties
        self.alertVW.layer.shadowColor = UIColor.black.cgColor // Shadow color
        self.alertVW.layer.shadowOpacity = 0.5                // Shadow transparency (0 to 1)
        self.alertVW.layer.shadowOffset = CGSize(width: 2, height: 2) // Shadow offset
        self.alertVW.layer.shadowRadius = 5                   // Blur radius of the shadow
        
        // Optional: Set corner radius if needed
        self.alertVW.layer.cornerRadius = 10
        
        // Add shadow path (for better performance)
        self.alertVW.layer.shadowPath = UIBezierPath(roundedRect: self.bounds, cornerRadius: 10).cgPath
        
    }
    
    @IBAction func btnCrossTapped(_ sender:Any){
        self.removeFromSuperview()
    }
    
    @IBAction func btnDiscard(_ sender:Any){
        self.removeFromSuperview()
    }
}
