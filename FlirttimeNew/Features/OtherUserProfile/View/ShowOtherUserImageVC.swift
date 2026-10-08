//
//  ShowOtherUserImageVC.swift
//  FlirtTime
//
//  Created by Smt MacMini on 03/01/25.
//

import UIKit
import Combine
import IQKeyboardManagerSwift

class ShowOtherUserImageVC: BaseViewController, Instantiable {
    
    let aOtherUserProfileViewModel = OtherUserProfileViewModel()
    private var desposeBag:Set<AnyCancellable> = []
    
    @IBOutlet weak var imgCollecVW: UICollectionView!
    @IBOutlet weak var txtMessage: UITextField!
    @IBOutlet weak var textViewMessage: UITextView!
    @IBOutlet weak var textViewheight: NSLayoutConstraint!
    @IBOutlet weak var vwMSGheightConstraint: NSLayoutConstraint!
    @IBOutlet weak var vwMSG: UIView!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var lblUserName: UILabel!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var messageCountLbl: UILabel!
    @IBOutlet weak var stackViewTopConstraints: NSLayoutConstraint!
    @IBOutlet weak var imgCollecVWHeightConstraints: NSLayoutConstraint!
    
    var imgUsers:[Images] = []
    var arrUserImg:[UserImage] = []
    var userID:Int = 0
    var userName: String = ""
    var isMyProfile:Bool = false
    var itemIndex:Int = 0
    var callBack:((Bool)->())?
    var textViewMaxHeight:Double = 45.0
    var iskeyboardOpened:Bool? = false
    var textCount : Int = 0
    
    static var storyboardName: StringConvertible {
        return StoryboardName.moments
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.registerCell()
        self.setUIBinding()
        self.view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
        containerView.addGestureRecognizer(tapGesture)
        tapGesture.cancelsTouchesInView = false
        lblUserName.text = userName
       // imgCollecVWHeightConstraints.constant = 480
        self.vwMSG.alpha = 0
        self.vwMSG.transform = CGAffineTransform(translationX: 0, y: -30)
        self.textViewMessage.delegate = self
        self.textViewMessage.text = Constants.Compliment.placeholder
        self.textViewMessage.textColor = UIColor.lightGray
        self.messageCountLbl.isHidden = true
        self.sendButtonEnable(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut], animations: {
                self.vwMSG.transform = .identity
                self.vwMSG.alpha = 1
            }, completion: nil)
        }
        setupKeyboardHandling()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        IQKeyboardManager.shared.enableAutoToolbar = false
        IQKeyboardManager.shared.isEnabled = false
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IQKeyboardManager.shared.isEnabled = true
        IQKeyboardManager.shared.enableAutoToolbar = true
    }

    @objc func viewTapped() {
        if textViewMessage.isFirstResponder {
            self.lblUserName.isHidden = false
                textViewMessage.resignFirstResponder()
            } else {
                // Otherwise, dismiss the whole view
                dismiss(animated: true, completion: nil)
            }
       // dismiss(animated: true, completion: nil)
      }
    
    deinit {
           NotificationCenter.default.removeObserver(self)
       }
    
    @objc func keyboardWillShow(notification: Notification) {
        if let keyboardFrame: NSValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardRectangle = keyboardFrame.cgRectValue
            let keyboardHeight = keyboardRectangle.height
            self.imgCollecVWHeightConstraints.constant = 420.0
            self.lblUserName.isHidden = true
            self.stackViewTopConstraints.constant = keyboardHeight
            self.view.layoutIfNeeded()
            self.imgCollecVW.reloadData()
        }
    }

    @objc func keyboardWillHide(notification: Notification) {
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            stackViewTopConstraints.constant = 150.0
            imgCollecVWHeightConstraints.constant = 520.0
            self.lblUserName.isHidden = false
            self.view.layoutIfNeeded()
            self.imgCollecVW.reloadData()
        }
    }

       // MARK: - Keyboard Handling
       private func setupKeyboardHandling() {
           NotificationCenter.default.addObserver(
               self,
               selector: #selector(keyboardWillShow),
               name: UIResponder.keyboardWillShowNotification,
               object: nil)

           NotificationCenter.default.addObserver(
               self,
               selector: #selector(keyboardWillHide),
               name: UIResponder.keyboardWillHideNotification,
               object: nil)
       }
    
    
    func setUIBinding() {
        
        self.aOtherUserProfileViewModel.$errorMessage.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                
                self.showNewAlertPopUp(Title: "Error", Msg: "Error while fetching data.", isSuccess: false, CompletionHandler: {(success) -> Void in
    
                })
                //self.navigationController?.popViewController(animated: true)
            }
        }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$aSendCompliment.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                self.showNewAlertPopUp(Title: "Message", Msg: model?.message ?? "", isSuccess: true, CompletionHandler: {(success) -> Void in
    
                })
                //self.navigationController?.popViewController(animated: true)
            }
        }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$errorSendCompliment.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
                
                self.showNewAlertPopUp(Title: "Alert", Msg: error ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
    
                })
                //self.navigationController?.popViewController(animated: true)
            }
        }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$errorState.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
                self.dismiss(animated: true, completion: {
                    
                    guard let action = self.callBack else {return}
                    action(self.aOtherUserProfileViewModel.errorState ?? true)
                })
                
            }
        }.store(in: &desposeBag)

    }
    
    @IBAction func backBtnAction(_ sender: Any) {
        //self.navigationController?.popViewController(animated: true)
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func sendMessageTapped(_ sender: Any) {
        
        let text = self.textViewMessage.text?.trimmingCharacters(in:.whitespacesAndNewlines)
        
        self.aOtherUserProfileViewModel.sendCompliments(userID: userID, msg: text ?? "")
        dismiss(animated: true, completion: nil)
        
        
//        let text = textView.text.trimmingCharacters(in:.whitespacesAndNewlines)
        
//        if messageData?.chatID != nil {
//            let param = ["chat_id":messageData?.chatID ?? 0,"content": text,"attachment":""] as [String : Any]
//            print(param)
//            aChatViewModel.sendMessagesAPI(param: param, completion: {
//                //
//            })
//            
//        }
//        
//        
//        self.textView.text = ""
//        self.sendButtonEnable(false)
////        self.sendButttonHideShow(isHide: textView.text.isEmpty)
//        self.setTextViewPlaceholder(emptyText:textView.text.isEmpty)
        
        
    }
    
    func registerCell() {
        
        if isMyProfile == true {
            vwMSG.isHidden = true
        } else {
            vwMSG.isHidden = false
        }
        
        let layout = self.imgCollecVW.collectionViewLayout as! UICollectionViewFlowLayout
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        
        self.imgCollecVW.register(UINib(nibName: ShowOtherUserImageCVC.identifier, bundle: nil), forCellWithReuseIdentifier: ShowOtherUserImageCVC.identifier)
        self.imgCollecVW.delegate = self
        self.imgCollecVW.dataSource = self
        self.imgCollecVW.reloadData()
        
        self.imgCollecVW.layoutIfNeeded()
        let indexPath = IndexPath(item: itemIndex, section: 0) // Change to your desired index
        self.imgCollecVW.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
    }

    

}
extension ShowOtherUserImageVC : UICollectionViewDelegate , UICollectionViewDataSource,UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isMyProfile == true {
            return self.arrUserImg.count
        } else {
            
            return self.imgUsers.count
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ShowOtherUserImageCVC.identifier, for: indexPath) as? ShowOtherUserImageCVC {
            cell.widthImgvwConstraint.constant = collectionView.bounds.width
            cell.hieghtImgvwConstraint.constant = collectionView.bounds.height
            var imgUrl = ""
            if isMyProfile == true {
                cell.stackImgVW.isHidden = true
                imgUrl = ApiName.imgBaseURL + (self.arrUserImg[indexPath.item].filename ?? "")
            } else {
                cell.stackImgVW.isHidden = false
                imgUrl = ApiName.imgBaseURL + (self.imgUsers[indexPath.item].image ?? "")
            }
            
            cell.imgVW.loadImage(with: URL(string: imgUrl))
            cell.imgVW.contentMode = .scaleAspectFill
            cell.imgVW.layer.cornerRadius = 15
            
            
            for i in 0..<6 {
                if i == indexPath.item {
                    cell.pageView[i].backgroundColor = AppColor.Punch
                } else {
                    cell.pageView[i].backgroundColor = AppColor.userViewBackground
                }
                
                if isMyProfile == true {
                    
                    if i > self.arrUserImg.count - 1 {
                        cell.pageView[i].isHidden = true
                    }
                    
                } else {
                    
                    if i > self.imgUsers.count - 1 {
                        cell.pageView[i].isHidden = true
                    }
                    
                }
                
            }
            
            return cell
        }
        
        return UICollectionViewCell()
        
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        
        let width = collectionView.bounds.width
        let height = collectionView.bounds.height
        return CGSize(width: width, height: height)
    }
}

extension ShowOtherUserImageVC: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText = textView.text ?? ""
        guard let stringRange = Range(range, in: currentText) else {
            return false
        }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: text)
       
        self.textCount = (updatedText.count)
        self.messageCountLbl.text = "\(self.textCount)/\(300)"
        return updatedText.count <= 300
    }

    func textViewDidChange(_ textView: UITextView) {
        let text = textView.text.trimmingCharacters(in:.whitespacesAndNewlines)
        self.sendButtonEnable(!text.isEmpty)
        
        let numberOfLines = textView.contentSize.height / (textView.font?.lineHeight ?? 1)
        if Int(numberOfLines) > 3 {
            self.textViewheight.constant = textViewMaxHeight
           // self.vwMSGheightConstraint.constant = 60.0
        } else {
            if Int(numberOfLines) == 3 {
                self.textViewMaxHeight = textView.contentSize.height
            }
            self.textViewheight.constant = textView.contentSize.height
        }
        textView.layoutIfNeeded()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder() // This hides the keyboard
        return true
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        self.iskeyboardOpened = true
        if textView.textColor == UIColor.lightGray {
            textView.text = nil
            textView.textColor = UIColor.black
            messageCountLbl.isHidden = true
        }
        self.sendButtonEnable(!textView.text.isEmpty)
        
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        self.iskeyboardOpened = false
        self.sendButtonEnable(!textView.text.isEmpty)
    }

    func sendButttonHideShow(isHide: Bool) {
        self.sendButton.isHidden = isHide
    }

    func sendButtonEnable(_ isEnable: Bool) {
        sendButton.isEnabled = isEnable
        sendButton.alpha = isEnable ? 1.0 : 0.6
        messageCountLbl.isHidden = isEnable ? false : true
    }

    func setTextViewPlaceholder(emptyText: Bool?) {
        if !(self.iskeyboardOpened ?? false) && (emptyText ?? false) {
            textViewMessage.text = Constants.Chat.placeholder
            textViewMessage.textColor = UIColor.lightGray
            self.textViewheight.constant = 35
           // self.vwMSGheightConstraint.constant = 50.0
        } else {
            if emptyText ?? false {
                self.textViewheight.constant = 35
//                self.vwMSGheightConstraint.constant = 50.0
            }
        }
    }
}



//extension ShowOtherUserImageVC: UITextViewDelegate {
//    func textViewDidChange(_ textView: UITextView) {
//        let text = textView.text.trimmingCharacters(in:.whitespacesAndNewlines)
////        self.sendButttonHideShow(isHide: text.isEmpty)
//        self.sendButtonEnable(!text.isEmpty)
//        let numberOfLines = textView.contentSize.height/(textView.font?.lineHeight)!
//        if Int(numberOfLines) > 5 {
//            self.textViewheight.constant = textViewMaxHeight
//        } else {
//            if Int(numberOfLines) == 5 {
//                self.textViewMaxHeight = textView.contentSize.height
//            }
//            self.textViewheight.constant = textView.contentSize.height
//        }
//        textView.layoutIfNeeded()
//       // self.mediaView.isHidden = true
//    }
//
//    func textViewDidBeginEditing(_ textView: UITextView) {
//        self.iskeyboardOpened = true
//        if textView.textColor == UIColor.lightGray {
//            textView.text = nil
//            textView.textColor = UIColor.black
//        }
//        self.sendButtonEnable(!textView.text.isEmpty)
////        self.sendButttonHideShow(isHide: textView.text.isEmpty)
//
//    }
//
//    func textViewDidEndEditing(_ textView: UITextView) {
//        self.iskeyboardOpened = false
//        self.sendButtonEnable(!textView.text.isEmpty)
////        self.setTextViewPlaceholder(emptyText:textView.text.isEmpty)
//    }
//
//    func sendButttonHideShow(isHide:Bool){
//        self.sendButton.isHidden = isHide
//    }
//    
//    func sendButtonEnable(_ isEnable: Bool) {
//        sendButton.isEnabled = isEnable ? true : false
//        sendButton.alpha = isEnable ? 1.0 : 0.6
//    }
//
//    func setTextViewPlaceholder(emptyText:Bool?){
//        if !(self.iskeyboardOpened ?? false) && emptyText ?? false{
//            textViewMessage.text = Constants.Chat.placeholder
//            textViewMessage.textColor = UIColor.lightGray
//            self.textViewheight.constant = 35
//        }else{
//            if emptyText ?? false {
//                self.textViewheight.constant = 35
//            }
//        }
//    }
//}
