//
//  CustomToastView.swift
//  Bank 316
//
//  Created by Smt MacMini 3 on 14/02/24.
//

import Foundation
import UIKit

class CustomToastView: UIView {
    
    @IBOutlet var contentView: UIView!
    @IBOutlet weak var messageLabel: UILabel!
    private var shouldHide = false
    
    override init(frame: CGRect) {
        self.shouldHide = false
        super.init(frame: frame)
    }
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func show(message:String?) {
        if let window = UIApplication.shared.windows.first {
            window.addSubview(self)
        }
        DispatchQueue.main.async {
            self.shouldHide = true
            Bundle.main.loadNibNamed("CustomToastView", owner: self, options: nil)
            self.contentView.frame = self.bounds
            self.contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
            for view in self.subviews {
                view.removeFromSuperview()
            }
            self.addSubview(self.contentView)
            self.messageLabel.text = message
            self.contentView.backgroundColor = UIColor.clear
            self.contentView.alpha = 0.0
            self.contentView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            UIView.animate(withDuration: 0.25) {
                self.contentView.transform = CGAffineTransform(scaleX: 1, y: 1)
                self.contentView.alpha = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline:.now() + 1.0){
                self.hide()
            }
        }
    }

    func hide() {
        if self.shouldHide == false {
            return
        }
        DispatchQueue.main.async {
            self.contentView.alpha = 0.0
            self.removeFromSuperview()
        }
//        DispatchQueue.main.async {
//            UIView.animate(withDuration: 0.25) {
//                self.contentView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
//                self.contentView.alpha = 0.0
//            } completion: { _ in
//                self.removeFromSuperview()
//            }
//        }
    }
}

