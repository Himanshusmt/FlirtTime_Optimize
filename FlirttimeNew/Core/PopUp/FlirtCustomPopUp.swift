//
//  FlirtCustomPopUp.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 01/05/24.
//

import Foundation
import UIKit

enum PopUpType{
    case birthdayDate
    case gender
    case pictureUploading
    case picUploadingFailed
    case spiceUpMatch
    case betterMatch
    case exploreApp
    case unauthenticated
}

let screen = UIScreen.main.bounds

class FlirtCustomPopUp: UIView,UIGestureRecognizerDelegate {

    @IBOutlet weak var mainView: UIView!
    @IBOutlet var contentView: UIView!
    @IBOutlet weak var button1: UIButton!
    @IBOutlet weak var button2: UIButton!
    @IBOutlet weak var verticalButton1: UIButton!
    @IBOutlet weak var verticalButton2: UIButton!
    @IBOutlet weak var textLabel: UILabel!

    @IBOutlet weak var monthTextField: UITextField!
    @IBOutlet weak var dayTextField: UITextField!
    @IBOutlet weak var yearTextField: UITextField!
    @IBOutlet weak var birthdateView: UIView!
    @IBOutlet weak var ageLimitLabel: UILabel!
    @IBOutlet weak var saveDOBButton: UIButton!

    @IBOutlet weak var genderView: UIView!
    @IBOutlet weak var femaleImageView: UIView!
    @IBOutlet weak var maleImageView: UIView!
    @IBOutlet weak var otherImageView: UIView!
    @IBOutlet weak var betterMatchView: UIView!
    @IBOutlet weak var spiceUpMatchView: UIView!
    @IBOutlet weak var exploreAppView: UIView!
    @IBOutlet weak var genderImageViewHeight: NSLayoutConstraint!
    @IBOutlet weak var picUploadFailedView: UIView!
    @IBOutlet weak var picUploadingView: UIView!
    @IBOutlet weak var uploadingProgressView: CircularProgressView!
    @IBOutlet weak var uploadingImage: UIImageView!
    @IBOutlet weak var horzontalButtonStack: UIStackView!
    @IBOutlet weak var VerticalButtonStack: UIStackView!
    @IBOutlet weak var calenderContentView: UIView!
    @IBOutlet weak var mainCalenderView: UIView!
    @IBOutlet weak var calenderView: UIView!
    
    @IBOutlet weak var imgVWCross: UIImageView!
    @IBOutlet weak var btnCross: UIButton!

    var callBackAction:((String)->())?
    var dOBcallBackAction:((Date)->())?
    var genericCallBack:((PopUpType)->())?
    var popUpType:PopUpType?
    var restrictPopUpShowMultipleTimes:Bool? = false
    var datePicker: UIDatePicker?
    var selectedGender:String? = nil
    var userUploadingImage:UIImage?
    var progressAnimationWorkItem: DispatchWorkItem?
    var selectedDOB:Date?
    var selectedDateCompoent:DateComponents?
    
    var callBackGenderAction:((String,Int)->())?
    var selectedGenderID:Int? = nil
    let genderOptions: [(id: Int, title: String)] = [(1, "Male"), (2, "Female"), (3, "other")]
    var isFromHome:Bool? = false

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func show(text: String,buttonTitle1:String? = nil,buttonTitle:[String],popUpType:PopUpType,image:UIImage? = nil,isVerticalButtonHide:Bool? = true,isFromHome:Bool? = false,completion1:((Any)->Void)? = nil,completion2:((PopUpType)->Void)? = nil,completion3:((String,Int)->Void)? = nil) {
        self.isFromHome = isFromHome
        if let window = UIApplication.shared.windows.first {
            window.addSubview(self)
        }

        guard !(restrictPopUpShowMultipleTimes ?? false) else {
            return // Popup is already showing, ignore this call
        }

        DispatchQueue.main.async {
            
            self.popUpType = popUpType
            self.callBackGenderAction = completion3
            self.dOBcallBackAction = completion1
            self.genericCallBack = completion2
            self.callBackAction = completion1
            Bundle.main.loadNibNamed("FlirtCustomPopUp", owner: self, options: nil)
            self.contentView.frame = self.bounds
            self.contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
            for view in self.subviews {
                view.removeFromSuperview()
            }
            self.addSubview(self.contentView)
            self.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            self.textLabel.text = text
            self.setButtonText(buttonTitle:buttonTitle)
            self.userUploadingImage = image != nil ? image : UIImage()
            self.VerticalButtonStack.isHidden = isVerticalButtonHide ?? false
            self.horzontalButtonStack.isHidden = !(isVerticalButtonHide ?? false)
            self.calenderContentView.isHidden = true
            self.showView()
            self.contentView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            UIView.animate(withDuration: 0.25) {
                self.contentView.transform = CGAffineTransform(scaleX: 1, y: 1)
                self.contentView.alpha = 1.0
            }
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:)))
            tapGesture.cancelsTouchesInView = false
            tapGesture.delegate = self // Set the delegate
            self.calenderContentView.addGestureRecognizer(tapGesture)
        }
        self.restrictPopUpShowMultipleTimes = true
    }

    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view, view.isDescendant(of: mainCalenderView) {
            return false
        }
        return true
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        self.hide()
    }

    func setButtonText(buttonTitle:[String]){
        self.button1.isHidden = !(buttonTitle.count > 1)
        self.verticalButton2.isHidden = !(buttonTitle.count > 1)

        self.button1.setTitle(buttonTitle.count > 1 ? buttonTitle[1] : "", for: .normal)
        self.verticalButton2.setTitle(buttonTitle.count > 1 ? buttonTitle[1] : "", for: .normal)

        self.button2.setTitle(buttonTitle[0], for: .normal)
        self.verticalButton1.setTitle(buttonTitle[0], for: .normal)
    }

    //    Code to hide popUp from superview
    func hide() {
        if self.contentView == nil {return}
        self.restrictPopUpShowMultipleTimes = false
        self.dismissAnimation()
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25) {
                self.contentView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                self.contentView.alpha = 0.0
            } completion: { _ in
                self.removeFromSuperview()
            }
        }
    }

    //    Show popup main content as per PopUpType
    func showView(){
        switch popUpType {
        case .birthdayDate:
            self.createCalender()
            self.calenderContentView.isHidden = false
            self.mainView.isHidden = true
        case .gender:
            self.genderView.isHidden = false
            self.genderImageViewHeight.constant = (self.contentView.frame.width - 108) * 0.331
        case .pictureUploading:
            self.uploadPhoto()
        case .picUploadingFailed:
            self.picUploadFailedView.isHidden = false
        case .spiceUpMatch:
            if isFromHome == true {
                self.btnCross.isHidden = true
                self.btnCross.isUserInteractionEnabled = false
                self.imgVWCross.isHidden = true
            } else {
                self.btnCross.isHidden = false
                self.btnCross.isUserInteractionEnabled = true
                self.imgVWCross.isHidden = false
            }
            self.button1.borderWidth = 2.0
            self.button1.borderColor = AppColor.Punch
            self.spiceUpMatchView.isHidden = false
            self.button2.isUserInteractionEnabled = true
            self.button2.backgroundColor = AppColor.Punch
        case .betterMatch:
            self.betterMatchView.isHidden = false
            self.button2.isUserInteractionEnabled = true
            self.button2.backgroundColor = AppColor.Punch
        case .exploreApp:
            self.exploreAppView.isHidden = false
            self.verticalButton1.isUserInteractionEnabled = true
            self.verticalButton1.backgroundColor = AppColor.Punch
        default:
            break
        }
    }


    @IBAction func button1ActionTapped(_ sender: UIButton) {
        if popUpType == .betterMatch {
            guard let action = self.callBackAction else { return }
            action("")
        }
        self.hide()
    }

    //    Button1 action
    @IBAction func button2ActionTapped(_ sender: UIButton) {
        self.hide()
        switch popUpType {
        case .birthdayDate:
            break
        case .gender:
            guard let action = self.callBackGenderAction else { return }
            action(selectedGender ?? "", selectedGenderID ?? 0)
        case.pictureUploading:
            break
        case .picUploadingFailed:
            guard let action = self.genericCallBack else { return }
            action(.picUploadingFailed)
            break
        case .spiceUpMatch:
            guard let action = self.genericCallBack else { return }
            action(.spiceUpMatch)
            break
        case .betterMatch :
            guard let action = self.genericCallBack else { return }
            action(.betterMatch)
        default:
            break
        }
    }


    @IBAction func verticalButton1Action(_ sender: UIButton) {
        switch popUpType {
        case .exploreApp:
            self.hide()
        default:
            break
        }
    }

    @IBAction func verticalButton2Action(_ sender: UIButton) {
        switch popUpType {
        case .exploreApp:
            self.hide()
        default:
            break
        }
    }

    //    Cross button to dismiss popup
    @IBAction func dismissButton(_ sender: UIButton) {
        if popUpType == .betterMatch {
            guard let action = self.callBackAction else { return }
            action("")
        }
        self.hide()
    }

    //   User Gender selection
    @IBAction func buttonFemale(_ sender: UIButton) {
        self.setFemaleSelectionUI()
    }

    @IBAction func buttonmale(_ sender: UIButton) {
        self.setMaleSelectionUI()
    }

    @IBAction func buttonOther(_ sender: UIButton) {
        self.setOtherSelectionUI()
    }
    //

    //     set Button2 UI as per validation
    func setSaveButtonUI(){
        self.button2.isUserInteractionEnabled = validation()
        self.button2.backgroundColor = validation() ? AppColor.Punch : AppColor.Punch.withAlphaComponent(0.5)
    }

    //     All Validation
    func validation() -> Bool{
        switch popUpType {
        case .birthdayDate:
            if self.monthTextField.text != "" && self.dayTextField.text != "" && self.yearTextField.text != "" {
                return true
            }else{
                return false
            }
        case .gender:
            if self.selectedGender != nil {
                return true
            }else{
                return false
            }
        default:
            return false
        }
    }

    //    DOB Buttons
    @IBAction func saveDOBButtonTapped(_ sender: UIButton) {
        self.hide()
        guard let action = self.dOBcallBackAction else { return }
        let selectedDate = self.selectedDOB ?? Date()
        action(selectedDate)

    }
}

