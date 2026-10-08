//
//  FontManager.swift
//  PTEMaster
//
//  Created by mac on 17/08/20.
//  Copyright © 2020 CTIMac. All rights reserved.
//

import Foundation
import UIKit

let FontRegular = "Fredoka-Regular"
let FontMedium = "Fredoka-Medium"
let FontSemiBold = "Fredoka-SemiBold"
let FontBold = "Montserrat-Bold"



enum Fonts : Int {
    
    case regular = 1
    case medium = 2
    case semibold = 3
    case bold = 4
    
    public func font(WithSize size : CGFloat) -> UIFont {
        switch self {
        case .regular:
           return UIFont.regularFont(size: size)
        case.medium:
        return UIFont.mediumFont(size: size)
        case.semibold:
        return UIFont.semiBoldFont(size: size)
        case .bold:
            return UIFont.boldFont(size: size)

        }
    }
}

extension UIFont {
    
    static func regularFont( size:CGFloat ) -> UIFont{
        return  UIFont(name: FontRegular , size: size)!
    }
    
    static func boldFont( size:CGFloat ) -> UIFont{
        return  UIFont(name: FontBold , size: size)!
    }
    
    static func mediumFont( size:CGFloat ) -> UIFont{
        return  UIFont(name: FontMedium , size: size)!
    }
    static func semiBoldFont( size:CGFloat ) -> UIFont{
        return  UIFont(name: FontSemiBold , size: size)!
    }
    
}

//--------------

extension UILabel {
    @IBInspectable  var CustomFont: Int  {
        get {
            return self.CustomFont
        }
        set {
            self.font = Fonts.init(rawValue: newValue)?.font(WithSize: self.font.pointSize)
        }
    }
    
    @IBInspectable
    var letterSpace: CGFloat {
        set {
            let attributedString: NSMutableAttributedString!
            if let currentAttrString = attributedText {
                attributedString = NSMutableAttributedString(attributedString: currentAttrString)
            } else {
                attributedString = NSMutableAttributedString(string: text ?? "")
                text = nil
            }
            attributedString.addAttribute(NSAttributedString.Key.kern,
                                          value: newValue,
                                          range: NSRange(location: 0, length: attributedString.length))
            attributedText = attributedString
        }
        
        get {
            if let currentLetterSpace = attributedText?.attribute(NSAttributedString.Key.kern, at: 0, effectiveRange: .none) as? CGFloat {
                return currentLetterSpace
            } else {
                return 0
            }
        }
    }
}

extension UITextField {
    @IBInspectable  var CustomFont: Int  {
            get {
                return self.CustomFont
            }
        set {
            self.font = Fonts.init(rawValue: newValue)?.font(WithSize: self.font?.pointSize ?? 0)
        }
    }
}
extension UITextView {
    @IBInspectable  var CustomFont: Int  {
            get {
                return self.CustomFont
            }
        set {
            self.font = Fonts.init(rawValue: newValue)?.font(WithSize: self.font?.pointSize ?? 0)
        }
    }
}


extension UIButton {
    @IBInspectable  var CustomFont: Int  {
        get {
            return self.CustomFont
        }
        set {
            self.titleLabel?.font = Fonts.init(rawValue:  newValue)?.font(WithSize: self.titleLabel?.font?.pointSize ?? 1)
        }
    }
    
    func addPressEffect() {
           self.addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
           self.addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchCancel, .touchDragExit])
       }

       @objc private func pressDown() {
           UIView.animate(withDuration: 0.1, animations: {
               self.transform = CGAffineTransform(scaleX: 0.7, y: 0.7) // smaller
           })
       }

       @objc func pressUp() {
           UIView.animate(withDuration: 0.2, animations: {
               self.transform = .identity // back to normal quickly
           })
       }
    
}

extension UIView {
    func addPressEffect1() {
        let tapDown = UILongPressGestureRecognizer(target: self, action: #selector(handlePressEffect(_:)))
        tapDown.minimumPressDuration = 0
        self.isUserInteractionEnabled = true
        self.addGestureRecognizer(tapDown)
    }

    // 👇 Reusable function to trigger press effect programmatically
    func performPressEffect() {
        UIView.animate(withDuration: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        }) { _ in
            UIView.animate(withDuration: 0.2) {
                self.transform = .identity
            }
        }
    }

    @objc private func handlePressEffect(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            UIView.animate(withDuration: 0.1) {
                self.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            }
        case .ended, .cancelled, .failed:
            UIView.animate(withDuration: 0.2) {
                self.transform = .identity
            }
        default:
            break
        }
    }
}
