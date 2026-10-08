//
//  Strings.swift
//  ThirdRoc
//
//  Created by GOVIND KUMAR on 20/10/23.
//

import UIKit

class ActivityIndicator: UIView {
  
    @IBOutlet var contentView: UIView!
    private var shouldHide = false
    
    override init(frame: CGRect) {
        self.shouldHide = false
        super.init(frame: frame)
    }
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func show() {
        if let window = UIApplication.shared.windows.first {
            window.addSubview(self)
        }
        DispatchQueue.main.async {
            self.shouldHide = true
            Bundle.main.loadNibNamed("ActivityIndicator", owner: self, options: nil)
            self.contentView.frame = self.bounds
            self.contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
            for view in self.subviews {
                view.removeFromSuperview()
            }
            self.addSubview(self.contentView)
            self.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            self.contentView.alpha = 0.0
            self.contentView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            UIView.animate(withDuration: 0.25) {
                self.contentView.transform = CGAffineTransform(scaleX: 1, y: 1)
                self.contentView.alpha = 1.0
            }
        }
    }
    
    func hide() {
        if self.shouldHide == false {
            return
        }
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25) {
                self.contentView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                self.contentView.alpha = 0.0
            } completion: { _ in
                self.removeFromSuperview()
            }
        }
    }
}
