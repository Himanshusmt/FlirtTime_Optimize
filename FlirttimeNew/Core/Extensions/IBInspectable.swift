//
//  IBInspectable.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import UIKit

extension UIView {
    
    @IBInspectable
    var cornerRadius: CGFloat {
        get {
            return layer.cornerRadius
        }
        set {
            layer.cornerRadius = newValue
        }
    }
    
    @IBInspectable
    var borderWidth: CGFloat {
        get {
            return layer.borderWidth
        }
        set {
            layer.borderWidth = newValue
        }
    }
    
    @IBInspectable
    var borderColor: UIColor? {
        get {
            if let color = layer.borderColor {
                return UIColor(cgColor: color)
            }
            return nil
        }
        set {
            if let color = newValue {
                layer.borderColor = color.cgColor
            } else {
                layer.borderColor = nil
            }
        }
    }
    
    @IBInspectable
    var shadowRadius: CGFloat {
        get {
            return layer.shadowRadius
        }
        set {
            layer.shadowRadius = newValue
        }
    }
    
    @IBInspectable
    var shadowOpacity: Float {
        get {
            return layer.shadowOpacity
        }
        set {
            layer.shadowOpacity = newValue
        }
    }
    
    @IBInspectable
    var shadowOffset: CGSize {
        get {
            return layer.shadowOffset
        }
        set {
            layer.shadowOffset = newValue
        }
    }
    
    @IBInspectable
    var shadowColor: UIColor? {
        get {
            if let color = layer.shadowColor {
                return UIColor(cgColor: color)
            }
            return nil
        }
        set {
            if let color = newValue {
                layer.shadowColor = color.cgColor
            } else {
                layer.shadowColor = nil
            }
        }
    }
    
    func cornerRadius(corners: CACornerMask, radius: CGFloat) {
        self.clipsToBounds = true
        self.layer.cornerRadius = radius
        self.layer.maskedCorners = corners
    }
}

extension UITextField {
    
    func setLeftPaddingPoints(_ amount:CGFloat){
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: amount, height: self.frame.size.height))
        self.leftView = paddingView
        self.leftViewMode = .always
    }
    func setRightPaddingPoints(_ amount:CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: amount, height: self.frame.size.height))
        self.rightView = paddingView
        self.rightViewMode = .always
    }
    
    /// Runtime key
    private struct AssociatedKeys {
        /// max lenght key
        static var maxlength: UInt8 = 0
        /// temp string key
        static var tempString: UInt8 = 0
    }
    
    /// Limit the maximum input length of the textfiled
    @IBInspectable var maxLength: Int {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.maxlength) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.maxlength, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            addTarget(self, action: #selector(handleEditingChanged(textField:)), for: .editingChanged)
        }
    }
    
    /// temp string
    private var tempString: String? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.tempString) as? String
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.tempString, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// When the text changes, process the amount of text in the input box so that its length is within the controllable range.
    @objc private func handleEditingChanged(textField: UITextField) {
        
        /// Special Processing for Chinese Input Method
        guard markedTextRange == nil else { return }
        
        if textField.text?.count == maxLength {
            
            /// SET lastQualifiedString where text length == max lenght
            tempString = textField.text
        } else if textField.text?.count ?? 0 < maxLength {
            
            /// clear lastQualifiedString when text lengeht > maxlength
            tempString = nil
        }
        
        /// keep current text range in arcgives
        let archivesEditRange: UITextRange?
        
        if textField.text?.count ?? 0 > maxLength {
            
            /// if text length > maxlength,remove last range,to move to -1 postion.
            let position = textField.position(from: safeTextPosition(selectedTextRange?.start), offset: -1) ?? textField.endOfDocument
            archivesEditRange = textField.textRange(from: safeTextPosition(position), to: safeTextPosition(position))
        } else {
            
            /// just set current select text range
            archivesEditRange = selectedTextRange
        }
        
        /// main handle string max length
        textField.text = tempString ?? String((textField.text ?? "").prefix(maxLength))
        
        /// last config edit text range
        textField.selectedTextRange = archivesEditRange
    }
    
    /// get safe textPosition
    private func safeTextPosition(_ optionlTextPosition: UITextPosition?) -> UITextPosition {
        
        /* beginningOfDocument -> The end of the the text document. */
        return optionlTextPosition ?? endOfDocument
    }
    
    @IBInspectable var placeHolderColor: UIColor? {
        get {
            guard let placeholder = attributedPlaceholder, placeholder.length > 0 else { return nil }
            return placeholder.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        }
        set {
            guard let newValue = newValue else { return }
            setPlaceholderColor(newValue)
        }
    }

    func setPlaceholderColor(_ color: UIColor) {
        guard let placeholder = placeholder else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color
        ]
        attributedPlaceholder = NSAttributedString(string: placeholder, attributes: attributes)
    }
    
    func removeWhitespace() -> String {
        guard let text = self.text else { return "" }
        self.text = text.trimmingCharacters(in: .whitespaces)
        return text
    }
    
}
