//
//  SubscriptionPopUp.swift
//  FlirtTime
//
//  Created by Smt MacMini on 06/02/25.
//

import UIKit

enum SubscriptionPopUpType {
    case chat, compliment, superLike, unlimitedSwipes
}

class SubscriptionPopUp: UIView {
    
    @IBOutlet weak var myView:UIView!
    @IBOutlet weak var chatView:UIView!
    @IBOutlet weak var complimentView:UIView!
    @IBOutlet weak var superLike: UIView!
    @IBOutlet weak var unlimitedSwipesView:UIView!
    
    @IBOutlet weak var chatImageView: UIImageView!
    @IBOutlet weak var complimentImageView: UIImageView!
    @IBOutlet weak var superLikeImageView: UIImageView!
    @IBOutlet weak var unlimitedSwipeImageView: UIImageView!
    


    var subsUpdateAction:(()->Void)?
    var subsBackAction:(()->Void)?
    var isToHome:Bool? = false
    
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
            let nib = UINib(nibName: "SubscriptionPopUp", bundle: nil)
            guard let view = nib.instantiate(withOwner: self, options: nil).first as? UIView else { return }
            view.frame = self.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
        myView.addGestureRecognizer(tapGesture)
        self.useBlurEffect()
        
        }
    
    func useBlurEffect() {
        
        let blurEffect = UIBlurEffect(style: UIBlurEffect.Style.light)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = myView.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        myView.addSubview(blurEffectView)
    }
    
    func configurePopupView(subcriptionType: SubscriptionPopUpType = .compliment) {
        switch subcriptionType {
        case .chat:
            complimentView.isHidden = true
            superLike.isHidden = true
            unlimitedSwipesView.isHidden = true
            chatView.isHidden = false
            
        case .compliment:
            chatView.isHidden = true
            superLike.isHidden = true
            unlimitedSwipesView.isHidden = true
            complimentView.isHidden = false
           
        case .superLike:
            chatView.isHidden = true
            unlimitedSwipesView.isHidden = true
            complimentView.isHidden = true
            superLike.isHidden = false
            
        case .unlimitedSwipes:
            chatView.isHidden = true
            complimentView.isHidden = true
            superLike.isHidden = true
            unlimitedSwipesView.isHidden = false
        }
    }
   
    
    @objc func viewTapped() {
        if isToHome == true {
            guard let action = self.subsBackAction else { return }
            action()
        }
        self.removeFromSuperview()
    }
    
    @IBAction func btnCrossTapped(_ sender:Any){
        if isToHome == true {
            guard let action = self.subsBackAction else { return }
            action()
        }
        self.removeFromSuperview()
    }
    
    @IBAction func btnSubscriptionTapped(_ sender:Any){
        
        guard let action = self.subsUpdateAction else { return }
        action()
        self.removeFromSuperview()
    }

}
