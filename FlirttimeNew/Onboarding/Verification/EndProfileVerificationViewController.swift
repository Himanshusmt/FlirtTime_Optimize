//
//  EndProfileVerificationViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 03/05/24.
//

import UIKit

class EndProfileVerificationViewController: BaseViewController,Instantiable {
    
    @IBOutlet weak var labelPicturePerfect: UILabel!
    @IBOutlet weak var labelPrivacyPolicy: UILabel!
    @IBOutlet weak var userProfileImage: UIImageView!
    var userImage:UIImage?
    static var storyboardName: StringConvertible {
        return StoryboardName.signUp
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let userImage = userImage {
            self.userProfileImage.image = userImage
        }
        self.labelPicturePerfect.setAttriibutText(text1: "Picture perfect!\nYour ", text2: "profile shines", color: AppColor.Punch, multipleLine: false)
        
//        self.labelPrivacyPolicy.setAttriibutText(text1: "For more info on how we use, retain and protect your personal date please read our ", text2: "Privacy Policy", color: AppColor.Punch, multipleLine: false)
        
        self.labelPrivacyPolicy.setAttributedTextWithLink(
            text1: "For more info on how we use, retain and protect your personal data please read our ",
            text2: "Privacy Policy",
            color: AppColor.Punch,
            multipleLine: true
        ) {
            print("Privacy Policy tapped!")
            self.loadPrivacyPolicy()
        }
    }
    
    @IBAction func backButton(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
    
    @IBAction func retakeButtonTapped(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }


    @IBAction func continueButton(_ sender: UIButton) {
        let aGestureVerificationViewController = GestureVerificationViewController.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aGestureVerificationViewController, animated: true)
    }
}

extension UILabel {
    
    func setAttributedTextWithLink(text1: String, text2: String, color: UIColor, multipleLine: Bool, tapHandler: @escaping () -> Void) {
        self.numberOfLines = multipleLine ? 0 : 1
        self.isUserInteractionEnabled = true
        
        let fullText = text1 + text2
        let attributedString = NSMutableAttributedString(string: fullText)
        
        // Apply color and underline to text2
        let linkRange = (fullText as NSString).range(of: text2)
        attributedString.addAttribute(.foregroundColor, value: color, range: linkRange)
        attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: linkRange)
        
        self.attributedText = attributedString
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapOnLabel(_:)))
        self.addGestureRecognizer(tapGesture)
        
        // Store the callback
        objc_setAssociatedObject(self, &AssociatedKeys.tapHandlerKey, tapHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &AssociatedKeys.linkRangeKey, NSValue(range: linkRange), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    @objc private func handleTapOnLabel(_ gesture: UITapGestureRecognizer) {
        guard let text = self.attributedText?.string,
              let tapHandler = objc_getAssociatedObject(self, &AssociatedKeys.tapHandlerKey) as? () -> Void,
              let rangeValue = objc_getAssociatedObject(self, &AssociatedKeys.linkRangeKey) as? NSValue else { return }

        let nsRange = rangeValue.rangeValue

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: self.bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = self.numberOfLines
        textContainer.lineBreakMode = self.lineBreakMode

        let textStorage = NSTextStorage(attributedString: self.attributedText!)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let location = gesture.location(in: self)
        let index = layoutManager.characterIndex(for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)

        if NSLocationInRange(index, nsRange) {
            tapHandler()
        }
    }
}

private struct AssociatedKeys {
    static var tapHandlerKey = "tapHandlerKey"
    static var linkRangeKey = "linkRangeKey"
}

