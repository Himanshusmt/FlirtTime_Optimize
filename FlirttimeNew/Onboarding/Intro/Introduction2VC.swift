//
//  Introduction2VC.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import UIKit

class Introduction2VC: BaseViewController,Instantiable {

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
        self.descLabel.setAttriibutText(text1: "Be with whom you feel", text2: "comfortable", color: AppColor.Punch,multipleLine: true)
        self.acceptPrivacyLabel.setAttriibutText(text1: Constants.LoginOption.acceptenceText, text2: Constants.LoginOption.privacyPolicy, color: AppColor.AppBlack)
    }

    
    @IBAction func continueAction(_ sender: UIButton) {
        self.navigateToNextScreen()
    }

    func navigateToNextScreen(){
        let aIntroduction3VC = Introduction3VC.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aIntroduction3VC, animated: true)
    }
    @IBAction func actionPrivacyPolicy(_ sender: UIButton) {
        self.loadPrivacyPolicy()
    }
    
    
}
