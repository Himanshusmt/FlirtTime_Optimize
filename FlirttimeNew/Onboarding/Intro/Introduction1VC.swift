//
//  Introduction1VC.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//


import UIKit

class Introduction1VC: BaseViewController,Instantiable {

    @IBOutlet weak var descLabel: UILabel!
    @IBOutlet weak var acceptPrivacyLabel: UILabel!
    static var storyboardName: StringConvertible {
        return StoryboardName.splash
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUI()
    }

    func setUI(){
        // Apply the attributed string to the label
        self.descLabel.setAttriibutText(text1: "Discover individuals you", text2: "meet along the way", color: AppColor.Punch,multipleLine: true)
        self.acceptPrivacyLabel.setAttriibutText(text1:Constants.LoginOption.acceptenceText, text2: Constants.LoginOption.privacyPolicy, color: AppColor.AppBlack)
    }
    
    @IBAction func continueAction(_ sender: UIButton) {
        self.navigateToNextScreen()
    }

    func navigateToNextScreen(){
        let aIntroduction2VC = Introduction2VC.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aIntroduction2VC, animated: true)
    }
    
    @IBAction func actionPrivacyPolicy(_ sender: UIButton) {
        self.loadPrivacyPolicy()
    }
}

