//
//  String.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import UIKit

extension String {
    func attributedStringWithColor(_ strings: [String],
                                   color: UIColor,
                                   characterSpacing: UInt? = nil) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: self)
        for string in strings {
            let range = (self as NSString).range(of: string)
            attributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: range)
        }
        guard let characterSpacing = characterSpacing else {return attributedString}
        attributedString.addAttribute(NSAttributedString.Key.kern, value: characterSpacing, range: NSRange(location: 0, length: attributedString.length))
        return attributedString
    }
    
    func addingPhoneDashes() -> String {
        var result = ""
        let numbers = String(self.filter { self.contains($0) })
        var count = 0
        for (offset, character) in numbers.enumerated() {
            if offset != 0 && offset % 3 == 0 && count < 2{
                result.append("-")
                count += 1
            }
            result.append(character)
        }
        return result
    }
    
    func isValidEmail() -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: self)
    }
    var utfData: Data {
        return Data(utf8)
    }
    
    var attributedHtmlString: NSAttributedString? {
        do {
            return try NSAttributedString(data: utfData, options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
                                          documentAttributes: nil)
        } catch {
            print("Error:", error)
            return nil
        }
    }
    
    func trimmText() -> String{
        let trimmText = self.trimmingCharacters(in: .whitespaces)
        return trimmText
    }

    func urlExists() -> Bool? {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector.matches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))

        for match in matches {
            guard let range = Range(match.range, in: self) else { continue }
            let url = self[range]
            print(url)
            return true
        }
        return false
    }

    func extractLink() -> String? {
        let pattern = "(https?://[a-zA-Z0-9./?=_-]+)"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = self as NSString
            let results = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
            if let match = results.first {
                let range = match.range
                return nsString.substring(with: range)
            }
        } catch let error {
            print("Invalid regex: \(error.localizedDescription)")
        }
        return nil
    }

    // Function to set underlined text for a UILabel
    func underlineLink() -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: self)

        if let link = self.extractLink(),
           let linkRange = self.range(of: link) {
            let nsRange = NSRange(linkRange, in: self)
            attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
            attributedString.addAttribute(.foregroundColor, value: UIColor.blue, range: nsRange)
        }

        return attributedString
    }
}
extension UILabel {
    func setAttributedHtmlText(_ html: String) {
        if let attributedText = html.attributedHtmlString {
            self.attributedText = attributedText
        }
    }
    
    func setAttriibutText(text1:String,text2:String,pattern:Bool? = true,color:UIColor,multipleLine:Bool? = false){
        let colorString:String = text2
        var text:String = ""
        if pattern ?? false {
            text = multipleLine ?? false ? "\(text1)\n\(colorString)" : "\(text1) \(colorString)"
        }else{
            text = multipleLine ?? false ? "\(colorString)\n\(text1)" : "\(colorString) \(text1)"
        }
        let attributedString = NSMutableAttributedString(string: text)
        // Find the range of the text you want to color differently
        if let range = text.range(of: colorString) {
            let nsRange = NSRange(range, in: text)
            // Apply red color to the specified range
            attributedString.addAttribute(.foregroundColor, value: color, range: nsRange)
        }
        self.attributedText = attributedString
    }

    func validateEmail() -> Bool? {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,6}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with:self)
    }

    func numberOfVisibleLines() -> Int {
        guard let text = self.text else { return 0 }

        let maxSize = CGSize(width: screen.width - 34, height: CGFloat.greatestFiniteMagnitude)
        let textAttributes: [NSAttributedString.Key: Any] = [.font: self.font]

        let textRect = text.boundingRect(with: maxSize,
                                         options: [.usesLineFragmentOrigin, .usesFontLeading],
                                         attributes: textAttributes,
                                         context: nil)
        let lines = Int(ceil(textRect.height / self.font.lineHeight))

        return lines
    }
}

extension UIView {
    func addShadow(color: UIColor = .darkGray, opacity: Float = 0.3, offset: CGSize) {
        layer.masksToBounds = false
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
    }

    func addShadows(color: UIColor = .darkGray, opacity: Float = 0.3, offset: CGSize, radius: CGFloat = 0) {
            layer.masksToBounds = false
            layer.shadowColor = color.cgColor
            layer.shadowOpacity = opacity
            layer.shadowOffset = offset
            layer.shadowRadius = radius
            layer.shadowPath = UIBezierPath(rect: self.bounds).cgPath
        }

    func addCustomShadow(color: UIColor = .darkGray, opacity: Float = 0.3, offset: CGSize = .zero, radius: CGFloat = 5.0, bottomOffset: CGFloat = 5.0) {
        layer.masksToBounds = false
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = opacity
        layer.shadowOffset = CGSize(width: offset.width, height: offset.height + bottomOffset)
        layer.shadowRadius = radius

        // Adjust the shadow path to ensure shadow appears on all sides, but more prominently at the bottom
        let shadowPath = UIBezierPath()
        shadowPath.move(to: CGPoint(x: 0, y: -radius))
        shadowPath.addLine(to: CGPoint(x: self.bounds.width, y: -radius))
        shadowPath.addLine(to: CGPoint(x: self.bounds.width, y: self.bounds.height + bottomOffset))
        shadowPath.addLine(to: CGPoint(x: 0, y: self.bounds.height + bottomOffset))
        shadowPath.close()
        layer.shadowPath = shadowPath.cgPath
    }
}

extension UITextView {
    func moveCursorToStart() {
        if let newPosition = self.position(from: self.beginningOfDocument, offset: 0) {
            self.selectedTextRange = self.textRange(from: newPosition, to: newPosition)
        }
    }
}


extension UILabel {

    private var minimumLines: Int { return 2 }
    private var highlightColor: UIColor { return AppColor.Punch }

    private var attributes: [NSAttributedString.Key: Any] {
        return [.font: self.font ?? .systemFont(ofSize: 18)]
    }

    public func requiredHeight(for text: String) -> CGFloat {
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: frame.width, height: CGFloat.greatestFiniteMagnitude))
            label.numberOfLines = minimumLines
            label.lineBreakMode = NSLineBreakMode.byTruncatingTail
            label.font = font
            label.text = text
            label.sizeToFit()
            return label.frame.height
          }


    func highlight(_ text: String, color: UIColor) {
        guard let labelText = self.text else { return }
        let range = (labelText as NSString).range(of: text)

        let mutableAttributedString = NSMutableAttributedString.init(string: labelText)
        mutableAttributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: range)
        self.attributedText = mutableAttributedString
    }

    func appendReadmore(after text: String, trailingContent: TrailingContent) {
        self.numberOfLines = minimumLines
        let twoLineText = "\n..."
        let twolineHeight = requiredHeight(for: twoLineText)
        let sentenceText = NSString(string: text)
        let sentenceRange = NSRange(location: 0, length: sentenceText.length)
        var truncatedSentence: NSString = sentenceText
        var endIndex: Int = sentenceRange.upperBound
        let size: CGSize = CGSize(width: self.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        while truncatedSentence.boundingRect(with: size, options: .usesLineFragmentOrigin, attributes: attributes, context: nil).size.height >= twolineHeight {
            if endIndex == 0 {
                break
            }
            endIndex -= 1

            truncatedSentence = NSString(string: sentenceText.substring(with: NSRange(location: 0, length: endIndex)))
            truncatedSentence = (String("\(truncatedSentence)...") + trailingContent.text) as NSString

        }
        self.text = truncatedSentence as String
        self.highlight(trailingContent.text, color: highlightColor)
    }

    func appendReadLess(after text: String, trailingContent: TrailingContent) {
        self.numberOfLines = 0
        self.text = text + trailingContent.text
        self.highlight(trailingContent.text, color: highlightColor)
    }
}
