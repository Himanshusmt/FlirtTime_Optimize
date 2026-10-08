//
//  DeleteCustomPopUp.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 21/05/24.
//

import Foundation
import UIKit

enum DeleteOperation{
    case logout
}


class DeleteCustomPopUp: UIView {

    @IBOutlet weak var lblmessage: UILabel!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var button2: UIButton!
    @IBOutlet weak var button1: UIButton!

    var callBackAction:(()->())?
    var deleteType:DeleteOperation?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func show(message: String,button1Text:String,button2Text:String,deleteType:DeleteOperation? = nil,completion:(()->Void)? = nil, hideButton2: Bool = false) {
        if let window = UIApplication.shared.windows.first {
            window.addSubview(self)
        }
        DispatchQueue.main.async {
            self.callBackAction = completion
            Bundle.main.loadNibNamed("DeleteCustomPopUp", owner: self, options: nil)
            self.contentView.frame = self.bounds
            self.contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
            self.addSubview(self.contentView)
            self.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            self.lblmessage.text = message
            self.button2.setTitle(button2Text, for: .normal)
            self.button1.setTitle(button1Text, for: .normal)
            self.button2.isHidden = hideButton2
            self.deleteType = deleteType
            self.contentView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            UIView.animate(withDuration: 0.25) {
                self.contentView.transform = CGAffineTransform(scaleX: 1, y: 1)
                self.contentView.alpha = 1.0
            }
        }
    }

    private func hide() {
        if self.contentView == nil {return}
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25) {
                self.contentView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                self.contentView.alpha = 0.0
            } completion: { _ in
                self.removeFromSuperview()
            }
        }
    }

    @IBAction func button1Action(_ sender: UIButton) {
        self.hide()
        if deleteType == .logout {
            guard let action = self.callBackAction else { return }
            action()
        }
    }

    @IBAction func button2Action(_ sender: UIButton) {
        self.hide()
        if deleteType != .logout {
            guard let action = self.callBackAction else { return }
            action()
        }
    }
}
