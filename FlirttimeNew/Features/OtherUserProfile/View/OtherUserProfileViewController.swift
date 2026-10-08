//
//  OtherUserProfileViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 16/05/24.
//

import UIKit
import Combine

class OtherUserProfileViewController: BaseViewController, Instantiable,UIGestureRecognizerDelegate {

//    @IBOutlet weak var collectionViewMoment: UICollectionViewCell!
//    @IBOutlet weak var momentCollectionView: UICollectionView!
    @IBOutlet weak var interestCollectionView: UICollectionView!
    @IBOutlet weak var imageCollectionView: UICollectionView!
    @IBOutlet weak var aboutMeTableView: UITableView!
    @IBOutlet weak var moreAboutMeView: UIView!
//    @IBOutlet weak var momentView: UIView!
//    @IBOutlet weak var noMomentAvailableView: UIView!
    @IBOutlet weak var blockReportView: UIView!
    @IBOutlet weak var deleteButtonView: UIView!
//    @IBOutlet weak var noMomentBackImage: UIImageView!
    @IBOutlet weak var interestViewHeight: NSLayoutConstraint!
//    @IBOutlet weak var momentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var moreAboutMeViewHeight: NSLayoutConstraint!
    @IBOutlet weak var moreAboutTblHeight: NSLayoutConstraint!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var seeAllButton: UIButton!
    @IBOutlet weak var dotButton: UIButton!
    @IBOutlet weak var phonecallAndMessageStackView: UIStackView!
    @IBOutlet weak var imgVWUserProfile: UIImageView!
    @IBOutlet weak var imgVWBanner: UIImageView!
    @IBOutlet weak var userAboutLabel: UILabel!
    @IBOutlet weak var lblDisplayName: UILabel!
    @IBOutlet weak var btnVWLikeDislike: UIStackView!
    
    @IBOutlet weak var imgVWProfile: UIImageView!
    @IBOutlet weak var imgVWMoments: UIImageView!
    @IBOutlet weak var lblProfile: UILabel!
    @IBOutlet weak var lblMoments: UILabel!
    @IBOutlet weak var vwStackImages: UIStackView!
    @IBOutlet weak var vwInterest: UIView!
    @IBOutlet weak var lblInterest: UILabel!
    @IBOutlet weak var lblMoreAboutMe: UILabel!
    @IBOutlet weak var vwStackMoment: UIStackView!
    @IBOutlet weak var collVWMoment: UICollectionView!
    @IBOutlet weak var vwHeightConst: NSLayoutConstraint!
    @IBOutlet weak var vwInScroll: UIView!
    //collectionViewHeightConstraint
    @IBOutlet weak var collectionViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var collvwImageHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var btnBack: UIButton!
    
    @IBOutlet weak var vwDistanceColl: NSLayoutConstraint!
    @IBOutlet weak var imgVWVerifyIcon: UIImageView!
    @IBOutlet weak var vwNoMoments: UIView!
    @IBOutlet weak var vwChat: UIView!
    @IBOutlet weak var vvDislike: UIView!
    @IBOutlet weak var vvLike: UIView!
    @IBOutlet weak var vwSuperLike: UIView!
    
    var fromExploreScreen:Bool? = false
    var fromExploreMatches:Bool? = false
    var fromChatScreen:Bool? = false
    var fromExploreYouLike: Bool? = false
    var textDescription: String?
    let layout = UICollectionViewFlowLayout()

    let aOtherUserProfileViewModel = OtherUserProfileViewModel()
    static var storyboardName: StringConvertible {
        return StoryboardName.moments
    }
    var isMyProfile:Bool = false
    var userData:UserHome?
    var userDetails:UserDetailsData?
    var userMatchesData:MatchedUser?
    var machedUserId: Int?
    var arrAttribQuestions:[AttributesData] = []
    var arrIntrestData:[AttributesData] = []
    var arrImagesData:[Images] = []
    var arrUserImages:[UserImage] = []
    var arrProfileShow:[UIView] = []
    var momentImgs:[MomentImages] = []
    var userDetailInfo:UserDetailInfo?
    var isShowSuperLikeView: Bool = false
    private var desposeBag:Set<AnyCancellable> = []
    
    var viewHeight = 0
    

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUI()
        self.setUpBinding()
        self.arrProfileShow = [vwStackImages,moreAboutMeView,vwInterest,lblInterest,lblMoreAboutMe]
        self.isUserSubscribed()
        //self.viewHeight = Int(self.view.frame.height)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.btnBack.isUserInteractionEnabled = true
        self.viewHeight = 0
        self.setProfileTapped()
        //applyGradientToButton()
//        applyBlurBehindButton()
//        applyShadowToButton()
        self.checkHideCustomButton(hide: true)
        
        self.vwStackMoment.isHidden = true
        
        if UserDataManager.shared.userID == self.userDetailInfo?.userID || self.isMyProfile == true {
            self.dotButton.isHidden = true
        }
        
        if isMyProfile == true {
            self.btnVWLikeDislike.isHidden = true
            if self.userDetails?.user_images != nil {
                self.arrUserImages = self.filterAndReorderFiles(files: self.userDetails?.user_images ?? [])
                self.arrUserImages = self.arrUserImages.prefix(6).map { values in
                    
                    return values
                    
                }
                //self.aOtherUserProfileViewModel.getMomentUserImages(user_ID: self.userDetails?.userInfo?.userID ?? 0)
            }
            
        } else if self.fromExploreScreen == true {
            
            //self.aOtherUserProfileViewModel.getMomentUserImages(user_ID: self.userDetailInfo?.userID ?? 0)
            if self.fromExploreMatches == true { //Likes Else
                vwChat.isHidden = false
                vwSuperLike.isHidden = true
                vvDislike.isHidden = true
                vvLike.isHidden = true
                vwSuperLike.isHidden = true
                //self.btnVWLikeDislike.isHidden = false
                if self.userMatchesData?.images != nil {
                    let filteredFiles = self.filterAndReorderImages(files: self.userMatchesData?.images ?? [])
                    self.arrImagesData = filteredFiles.prefix(6).map { values in
                        
                        return values
                        
                    }
                    
                }
            } else {
                if isShowSuperLikeView == true {
                    vwChat.isHidden = true
                    vvLike.isHidden = true
                    vvDislike.isHidden = true
                    vwSuperLike.isHidden = false
                } else {
                    vwChat.isHidden = false
                    vwSuperLike.isHidden = false
                    vvDislike.isHidden = true
                    vvLike.isHidden = true
                    vwSuperLike.isHidden = true
                    //self.btnVWLikeDislike.isHidden = false
                }
                if self.userDetailInfo?.images != nil {
                    let filteredFiles = self.filterAndReorderImages(files: self.userDetailInfo?.images ?? [])
                    self.arrImagesData = filteredFiles.prefix(6).map { values in
                        
                        return values
                        
                    }
                }
            }
            
        }else if fromChatScreen == true {
            
         if  UserDataManager.shared.userID == self.userDetailInfo?.userID ?? 0 {
             self.btnVWLikeDislike.isHidden = true
            }
            if self.userDetailInfo?.images != nil {
                let filteredFiles = self.filterAndReorderImages(files: self.userDetailInfo?.images ?? [])
                self.arrImagesData = filteredFiles.prefix(6).map { values in
                    
                    return values
                    
                }
                
            }
            
        } else {
            self.btnVWLikeDislike.isHidden = false
            if self.userData?.images != nil {
                let filteredFiles = self.filterAndReorderImages(files: self.userData?.images ?? [])
                self.arrImagesData = filteredFiles.prefix(6).map { values in
                    
                    return values
                    
                }
                
            }
            //self.aOtherUserProfileViewModel.getMomentUserImages(user_ID: self.userData?.userId ?? 0)
        }
        
        self.aOtherUserProfileViewModel.loadJSON()
        
    }
    
    func filterAndReorderFiles(files: [UserImage]) -> [UserImage] {
        // Filter where filetype == "gallery"
        let filteredFiles = files.filter { $0.filefor == "gallery" }
        
        // Separate the primary file from the rest
        if let primaryIndex = filteredFiles.firstIndex(where: { $0.isPrimary == true }) {
            var reorderedFiles = filteredFiles
            let primaryFile = reorderedFiles.remove(at: primaryIndex)
            return [primaryFile] + reorderedFiles
        }
        
        // If no primary file, return filtered files as is
        return filteredFiles
    }
    
    func filterAndReorderImages(files: [Images]) -> [Images] {
        // Filter where filetype == "gallery"
        //let filteredFiles = files.filter { $0.type == "gallery" }
        var resultArray:[Images] = []
        
        // Separate the primary file from the rest
        if let primaryItem = files.first(where: { $0.is_primary == true }) {
            let otherItems = files.filter { $0.type == "gallery" && $0.is_primary != true }
            if files.count == 1 {
                resultArray = [primaryItem]
            } else {
                resultArray = [primaryItem] + otherItems
            }
        }else{
            if self.fromChatScreen == true {
                if let primaryItem = files.first(where: { $0.image == self.userDetailInfo?.avatar ?? "" }) {
                    
                    let filteredImages = files.filter { $0.type == "gallery" &&  $0.image != self.userDetailInfo?.avatar ?? "" }
                    let otherItems = filteredImages.filter { $0.type == "gallery" && $0.is_primary == nil }
                    if files.count == 1 {
                        resultArray = [primaryItem]
                    } else {
                        resultArray = [primaryItem] + otherItems
                    }
                }
            } else {
                if let primaryItem = files.first(where: { $0.image == self.userDetailInfo?.avatar ?? "" }) {
                    
                    let filteredImages = files.filter { $0.type == "gallery" &&  $0.image != self.userDetailInfo?.avatar ?? "" }
                    let otherItems = filteredImages.filter { $0.type == "gallery" && $0.is_primary == nil }
                    if files.count == 1 {
                        resultArray = [primaryItem]
                    } else {
                        resultArray = [primaryItem] + otherItems
                    }
                }
            }
        }
        // If no primary file, return filtered files as is
        return resultArray
    }

    func setUI(){
        self.regssterCell()
        scrollView.contentInsetAdjustmentBehavior = .never
//        self.momentViewHeight.constant = self.setMomentCollectionViewHeight() * 1.3
        self.setInterestCollectionViewHeight()
        //self.setMoreAboutTableViewHeight()
        
        self.moreAboutMeView.addShadow(color: AppColor.AppBlack.withAlphaComponent(0.2), opacity: 1.0, offset: CGSize(width: 0, height: 0.5))
//        self.noMomentBackImage.addShadow(color: AppColor.AppBlack.withAlphaComponent(0.2), opacity: 1.0, offset: CGSize(width: 0, height: 0.5))
        self.blockReportView.addShadow(color: AppColor.AppBlack.withAlphaComponent(0.2), opacity: 1.0, offset: CGSize(width: 0, height: 0.5))
        self.deleteButtonView.addShadow(color: AppColor.AppBlack.withAlphaComponent(0.2), opacity: 1.0, offset: CGSize(width: 0, height: 0.5))
//        self.momentView.isHidden = !(aOtherUserProfileViewModel.arrayMoments.count > 0)
//        self.noMomentAvailableView.isHidden = aOtherUserProfileViewModel.arrayMoments.count > 0
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        self.view.addGestureRecognizer(tapGesture)

//        MARK: - Add Gesture on AboutYou Label to implement ReadMoreLess action
        if self.isMyProfile == true {
            self.lblDisplayName.text = self.userDetails?.userInfo?.displayName ?? ""
            self.textDescription = self.userDetails?.userInfo?.aboutMe ?? ""
            if self.userDetails?.userInfo?.isActive == true {
                self.imgVWVerifyIcon.isHidden = false
            } else {
                self.imgVWVerifyIcon.isHidden = true
            }
        } else if fromExploreScreen == true {
            if self.fromExploreMatches == true {
                self.lblDisplayName.text = self.userMatchesData?.displayName ?? ""
                self.textDescription = self.userMatchesData?.aboutMe ?? ""
                
                if self.userMatchesData?.isActive == true {
                    self.imgVWVerifyIcon.isHidden = false
                } else {
                    self.imgVWVerifyIcon.isHidden = true
                }
            } else {
                
                self.lblDisplayName.text = self.userDetailInfo?.displayName ?? ""
                self.textDescription = self.userDetailInfo?.aboutMe ?? ""
                
                if self.userDetailInfo?.isActive == true {
                    self.imgVWVerifyIcon.isHidden = false
                } else {
                    self.imgVWVerifyIcon.isHidden = true
                }
            }
        } else if self.fromChatScreen == true {
            self.lblDisplayName.text = self.userDetailInfo?.displayName ?? ""
            self.textDescription = self.userDetailInfo?.aboutMe ?? ""
            
            if self.userDetailInfo?.isActive == true {
                self.imgVWVerifyIcon.isHidden = false
            } else {
                self.imgVWVerifyIcon.isHidden = true
            }
        }  else {
            self.lblDisplayName.text = self.userData?.displayName ?? ""
            self.textDescription = self.userData?.aboutMe ?? ""
            
            if self.userData?.isActive == true {
                self.imgVWVerifyIcon.isHidden = false
            } else {
                self.imgVWVerifyIcon.isHidden = true
            }
            
        }
        
        self.userAboutLabel.isUserInteractionEnabled = true
        self.userAboutLabel.text = textDescription
        self.userAboutLabel.appendReadmore(after: textDescription ?? "", trailingContent: .readmore)
        let labelTapGesture = UITapGestureRecognizer(target: self, action: #selector(self.handleLabelTap(_:)))
        labelTapGesture.cancelsTouchesInView = false
        labelTapGesture.delegate = self // Set the delegate
        self.userAboutLabel.addGestureRecognizer(labelTapGesture)

        //self.phonecallAndMessageStackView.isHidden = !(self.fromExploreScreen ?? false)
        
        if self.isMyProfile == true {
            
            if self.userDetails?.userInfo?.avatar != nil {
                let imgURL = ApiName.imgBaseURL + (self.userDetails?.userInfo?.avatar ?? "")
                self.imgVWUserProfile.loadImage(with: URL(string: imgURL))
            } else {
                self.imgVWUserProfile.image = UIImage(named: "delete-4")
            }
            
            if self.userDetails?.userInfo?.banner != nil {
                let imgURL = ApiName.imgBaseURL + (self.userDetails?.userInfo?.banner ?? "")
                self.imgVWBanner.loadImage(with: URL(string: imgURL))
            } else {
                self.imgVWBanner.image = UIImage(named: "addCoverPhoto")
            }
            
        } else if fromExploreScreen == true { // LIKES Else
            
            if self.fromExploreMatches == true {
                if self.userMatchesData != nil {
                    let imgURL = ApiName.imgBaseURL + (self.userMatchesData?.avatar ?? "")
                    self.imgVWUserProfile.loadImage(with: URL(string: imgURL))
                } else {
                    self.imgVWUserProfile.image = UIImage(named: "delete-4")
                }
                
                if self.userMatchesData?.banner != nil {
                    let imgURL = ApiName.imgBaseURL + (self.userMatchesData?.banner ?? "")
                    self.imgVWBanner.loadImage(with: URL(string: imgURL))
                } else {
                    self.imgVWBanner.image = UIImage(named: "addCoverPhoto")
                }

            } else {
                if self.userDetailInfo != nil {
                    let imgURL = ApiName.imgBaseURL + (self.userDetailInfo?.avatar ?? "")
                    self.imgVWUserProfile.loadImage(with: URL(string: imgURL))
                } else {
                    self.imgVWUserProfile.image = UIImage(named: "delete-4")
                }
                
                if self.userDetailInfo?.banner != nil {
                    let imgURL = ApiName.imgBaseURL + (self.userDetailInfo?.banner ?? "")
                    self.imgVWBanner.loadImage(with: URL(string: imgURL))
                } else {
                    self.imgVWBanner.image = UIImage(named: "addCoverPhoto")
                }

            }
            
            
        } else if self.fromChatScreen == true {
            
            if self.userDetailInfo != nil {
                let imgURL = ApiName.imgBaseURL + (self.userDetailInfo?.avatar ?? "")
                self.imgVWUserProfile.loadImage(with: URL(string: imgURL))
            } else {
                self.imgVWUserProfile.image = UIImage(named: "delete-4")
            }
            
            if self.userDetailInfo?.banner != nil {
                let imgURL = ApiName.imgBaseURL + (self.userDetailInfo?.banner ?? "")
                self.imgVWBanner.loadImage(with: URL(string: imgURL))
            } else {
                self.imgVWBanner.image = UIImage(named: "addCoverPhoto")
            }
            
        } else {
            if self.userData?.avatar != nil {
                let imgURL = ApiName.imgBaseURL + (self.userData?.avatar ?? "")
                self.imgVWUserProfile.loadImage(with: URL(string: imgURL))
            } else {
                self.imgVWUserProfile.image = UIImage(named: "delete-4")
            }
            
            if self.userData?.banner != nil {
                let imgURL = ApiName.imgBaseURL + (self.userData?.banner ?? "")
                self.imgVWBanner.loadImage(with: URL(string: imgURL))
            } else {
                self.imgVWBanner.image = UIImage(named: "addCoverPhoto")
            }
            
        }
        
        
        
    }
    
    func setUpBinding(){
  
        self.aOtherUserProfileViewModel.$aAttributesModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                
                
                if self.isMyProfile == true {
                    
                    self.arrAttribQuestions = self.filterAttributesBasedOnUserData(attributes: model?.data ?? [], userInfo: self.userDetails?.userInfo)
                    
                    print("Atrributes.......",self.arrAttribQuestions)
                    
                    self.aboutMeTableView.reloadData()
                    self.setMoreAboutTableViewHeight(count: self.arrAttribQuestions.count)
                    
                    
                    
                    self.arrIntrestData = self.filterUserDataIntrestInfo(attributes: model?.data ?? [], userInfo: self.userDetails?.userInfo)
                    
                    self.arrIntrestData = self.arrIntrestData.map{ attOpt in
                        let atOption = attOpt.aOptions?.filter{ $0.isSelected == true}
                        var aOption = attOpt
                        aOption.aOptions = atOption
                        return aOption
                    }
                    self.interestCollectionView.reloadData()
                    self.setInterestCollectionViewHeight()
                    
                    
                    self.imageCollectionView.reloadData()
                    self.updateCollVwImageHeight()
                    
                } else if self.fromExploreScreen == true {
                    
                    if self.fromExploreMatches == true {
                        
                        self.arrAttribQuestions = self.filterAttributesBasedOnMatches(attributes: model?.data ?? [], userInfo: self.userMatchesData)
                        
                        print("Atrributes.......",self.arrAttribQuestions)
                        
                        self.aboutMeTableView.reloadData()
                        self.setMoreAboutTableViewHeight(count: self.arrAttribQuestions.count)
                        
                        self.arrIntrestData = self.filterUserMatchesIntrestInfo(attributes: model?.data ?? [], userInfo: self.userMatchesData)
                        
                        self.arrIntrestData = self.arrIntrestData.map{ attOpt in
                            let atOption = attOpt.aOptions?.filter{ $0.isSelected == true}
                            var aOption = attOpt
                            aOption.aOptions = atOption
                            return aOption
                        }
                        self.interestCollectionView.reloadData()
                        self.setInterestCollectionViewHeight()
                        
                        
                        self.imageCollectionView.reloadData()
                        self.updateCollVwImageHeight()

                    } else {
                        
                        self.arrAttribQuestions = self.filterAttributesBasedOnUserData(attributes: model?.data ?? [], userInfo: self.userDetailInfo)
                        
                        print("Atrributes.......",self.arrAttribQuestions)
                        
                        self.aboutMeTableView.reloadData()
                        self.setMoreAboutTableViewHeight(count: self.arrAttribQuestions.count)
                        
                        self.arrIntrestData = self.filterUserDataIntrestInfo(attributes: model?.data ?? [], userInfo: self.userDetailInfo)
                        
                        self.arrIntrestData = self.arrIntrestData.map{ attOpt in
                            let atOption = attOpt.aOptions?.filter{ $0.isSelected == true}
                            var aOption = attOpt
                            aOption.aOptions = atOption
                            return aOption
                        }
                        self.interestCollectionView.reloadData()
                        self.setInterestCollectionViewHeight()
                        
                        
                        self.imageCollectionView.reloadData()
                        self.updateCollVwImageHeight()

                    }
                    
                                        
                } else if self.fromChatScreen == true {
                    
                    self.arrAttribQuestions = self.filterAttributesBasedOnUserData(attributes: model?.data ?? [], userInfo: self.userDetailInfo)
                    
                    print("Atrributes.......",self.arrAttribQuestions)
                    
                    self.aboutMeTableView.reloadData()
                    self.setMoreAboutTableViewHeight(count: self.arrAttribQuestions.count)
                    
                    self.arrIntrestData = self.filterUserDataIntrestInfo(attributes: model?.data ?? [], userInfo: self.userDetailInfo)
                    
                    self.arrIntrestData = self.arrIntrestData.map{ attOpt in
                        let atOption = attOpt.aOptions?.filter{ $0.isSelected == true}
                        var aOption = attOpt
                        aOption.aOptions = atOption
                        return aOption
                    }
                    self.interestCollectionView.reloadData()
                    self.setInterestCollectionViewHeight()
                    
                    
                    self.imageCollectionView.reloadData()
                    self.updateCollVwImageHeight()

                } else {
                    
                    self.arrAttribQuestions = self.filterAttributesBasedOnUserInfo(attributes: model?.data ?? [], userInfo: self.userData)
                    
                    print("Atrributes.......",self.arrAttribQuestions)
                    
                    self.aboutMeTableView.reloadData()
                    self.setMoreAboutTableViewHeight(count: self.arrAttribQuestions.count)
                    
                    self.arrIntrestData = self.filterIntrestInfo(attributes: model?.data ?? [], userInfo: self.userData)
                    
                    self.arrIntrestData = self.arrIntrestData.map{ attOpt in
                        let atOption = attOpt.aOptions?.filter{ $0.isSelected == true}
                        var aOption = attOpt
                        aOption.aOptions = atOption
                        return aOption
                    }
                    self.interestCollectionView.reloadData()
                    self.setInterestCollectionViewHeight()
                    
                    
                    self.imageCollectionView.reloadData()
                    self.updateCollVwImageHeight()
                }
                
                
                
            }
        }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$errorMessage.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                self.showNewAlertPopUp(Title: "Error", Msg: "Error while fetching data.", isSuccess: false, CompletionHandler: {(success) -> Void in
    
                })
                //self.navigationController?.popViewController(animated: true)
            }
        }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$aUserActionModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                if model?.status == true {
                    self.aCustomToastView.show(message: model?.message ?? "")
                    self.navigationController?.popViewController(animated: true)
                } else {
                    if UserDataManager.shared.isUserSubscriptionDone == true {
                        //self.aDeleteCustomPopUp.button2.isHidden = true
                        self.aDeleteCustomPopUp.show(message: model?.message ?? "",button1Text:Constants.AlertButtons.ok, button2Text: "", hideButton2: true)
                    } else {
                        self.showSubscriptionPopUp(subscriptionPopUpType: .superLike)
                    }
                }
               
                //self.navigationController?.popViewController(animated: true)
                
//                self.showNewAlertPopUp(Title: "Message", Msg: model?.message ?? "", isSuccess: true, CompletionHandler: {(success) -> Void in
//    
//                })
            }
        }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$errorAction.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
                
                self.showNewAlertPopUp(Title: "Error", Msg: error ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in

                })
            }
        }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$agetMomentImages.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                print("Success", model!)
                self.momentImgs = model?.data.data ?? []
                self.collVWMoment.reloadData()
                self.updateCollectionViewMomentsHeight()
                
                if self.momentImgs.count == 0 {
                    self.vwNoMoments.isHidden = false
                } else {
                    self.vwNoMoments.isHidden = true
                }
                
                
            }
        }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$errorMomentImages.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
                //self.vwHeightConst.constant =  361
                //self.view.layoutIfNeeded()
                self.vwNoMoments.isHidden = false
                self.showNewAlertPopUp(Title: "Error", Msg: error ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
    
                })
            }
        }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$aCheckUserSubscribe.receive(on: DispatchQueue.main).sink { model in
           if model != nil {
               print("Model",model!)
              // self.redirectToChatScreen()
               //himanshu uncomment this code
               if model?.data?.isActive == false {
                  // self.userNotSubscribed()
                   UserDataManager.shared.isUserSubscriptionDone = false
               } else {
                   UserDataManager.shared.isUserSubscriptionDone = true
//                   self.redirectToChatScreen()
               }
              // self.redirectToChatScreen()
           }
       }.store(in: &desposeBag)
        
        self.aOtherUserProfileViewModel.$errorCheckUserSubscribe.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
               
                self.showNewAlertPopUp(Title: "Error", Msg: error ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
                    
                })
           }
       }.store(in: &desposeBag)
        
        
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        self.blockReportView.isHidden = true
        self.deleteButtonView.isHidden = true
    }

    @objc func handleLabelTap(_ sender: UITapGestureRecognizer) {
        guard let text = self.userAboutLabel.text else { return }

        let readmore = (text as NSString).range(of: TrailingContent.readmore.text)
        let readless = (text as NSString).range(of: TrailingContent.readless.text)
        
        if readmore.length > 0 {
            self.userAboutLabel.appendReadLess(after: textDescription ?? "", trailingContent: .readless)
        } else if readless.length > 0 {
            self.userAboutLabel.appendReadmore(after: textDescription ?? "", trailingContent: .readmore)
        } else { return }
        
        
//        if sender.didTapAttributedTextInLabel(label: self.userAboutLabel, inRange: readmore) {
//            self.userAboutLabel.appendReadLess(after: textDescription ?? "", trailingContent: .readless)
//        } else if  sender.didTapAttributedTextInLabel(label: self.userAboutLabel, inRange: readless) {
//            self.userAboutLabel.appendReadmore(after: textDescription ?? "", trailingContent: .readmore)
//        } else { return }
    }
    
    @IBAction func momentsBtnTapped(_ sender: UIButton) {
        
        self.imgVWProfile.image = UIImage(named: Constants.OtherUserProfileImages.unselectedProfile)
        self.imgVWMoments.image = UIImage(named: Constants.OtherUserProfileImages.selectedMoments)
        self.lblMoments.backgroundColor = AppColor.Punch
        self.lblProfile.backgroundColor = UIColor.clear
        
        for val in arrProfileShow {
            val.isHidden = true
        }
        self.vwStackMoment.isHidden = false
        
        if isMyProfile == true {
            self.aOtherUserProfileViewModel.getMomentUserImages(user_ID: self.userDetails?.userInfo?.userID ?? 0)
            
        } else if fromExploreScreen == true {
           
            if self.fromExploreMatches == true {
                self.aOtherUserProfileViewModel.getMomentUserImages(user_ID: self.userMatchesData?.userID ?? 0)
            } else {
                
                self.aOtherUserProfileViewModel.getMomentUserImages(user_ID: self.userDetailInfo?.userID ?? 0)
            }
            
            
        } else if self.fromChatScreen == true {
            
            self.aOtherUserProfileViewModel.getMomentUserImages(user_ID: self.userDetailInfo?.userID ?? 0)
            
        } else {
            
            self.aOtherUserProfileViewModel.getMomentUserImages(user_ID: self.userData?.userId ?? 0)
        }
        
        

    }
    
    @IBAction func profileBtnTapped(_ sender: UIButton) {
        
        self.imgVWProfile.image = UIImage(named: Constants.OtherUserProfileImages.selectedProfile)
        self.imgVWMoments.image = UIImage(named: Constants.OtherUserProfileImages.unselectedMoments)
        self.lblMoments.backgroundColor = UIColor.clear
        self.lblProfile.backgroundColor = AppColor.Punch
        
        for val in arrProfileShow {
            val.isHidden = false
        }
        self.vwStackMoment.isHidden = true
        if self.viewHeight > 0 {
            vwHeightConst.constant = CGFloat(self.viewHeight)
            view.layoutIfNeeded()
        }
    }
    
    func setProfileTapped() {
        
        self.imgVWProfile.image = UIImage(named: Constants.OtherUserProfileImages.selectedProfile)
        self.imgVWMoments.image = UIImage(named: Constants.OtherUserProfileImages.unselectedMoments)
        self.lblMoments.backgroundColor = UIColor.clear
        self.lblProfile.backgroundColor = AppColor.Punch
        
        for val in arrProfileShow {
            val.isHidden = false
        }
        self.vwStackMoment.isHidden = true
        if self.viewHeight > 0 {
            vwHeightConst.constant = CGFloat(self.viewHeight)
            view.layoutIfNeeded()
        }
        
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view, view == self.dotButton {
            return false
        }
        return true
    }

    @IBAction func actionOnBack(_ sender: Any) {
        self.btnBack.isUserInteractionEnabled = false
        self.navigationController?.popViewController(animated: true)
    }
    
    @IBAction func likeTapped(_ sender: Any) {
        
        if isMyProfile == true {
            
            self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.like, user_ID: self.userDetails?.userInfo?.userID ?? 0)
            
            
        } else if self.fromExploreScreen == true {
            
            if self.fromExploreMatches == true {
                self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.like, user_ID: self.userMatchesData?.userID ?? 0)
            } else {
                self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.like, user_ID: self.userDetailInfo?.userID ?? 0)
            }
            
            
        } else if fromChatScreen == true {
            
            self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.like, user_ID: self.userDetailInfo?.userID ?? 0)
            
            
        } else {
            self.btnVWLikeDislike.isHidden = false
            self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.like, user_ID: self.userData?.userId ?? 0)
        }
        
        
    }
    
    @IBAction func disLikeTapped(_ sender: Any) {
        
        if isMyProfile == true {
            
            self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.dislike, user_ID: self.userDetails?.userInfo?.userID ?? 0)
            
            
        } else if self.fromExploreScreen == true {
            
            if self.fromExploreMatches == true {
                self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.dislike, user_ID: self.userMatchesData?.userID ?? 0)
            } else {
                self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.dislike, user_ID: self.userDetailInfo?.userID ?? 0)
            }
            
            
        } else if fromChatScreen == true {
            
            self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.dislike, user_ID: self.userDetailInfo?.userID ?? 0)
            
            
        } else {
            self.btnVWLikeDislike.isHidden = false
            self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.dislike, user_ID: self.userData?.userId ?? 0)
        }
        
    }
    
    @IBAction func superLikeButtonTapped(_ sender: Any) {
        //SuperLike apicall
        self.aOtherUserProfileViewModel.clickActionAPI(interaction_type: Constants.ActionType.favorite, user_ID: self.userDetailInfo?.userID ?? 0)
    }
    
    @IBAction func chatTapped(_ sender: Any) {
        
       // self.isUserSubscribed()
        self.redirectToChatScreen()
    }
    
    func redirectToChatScreen() {
        // TODO: push ChatViewController (userID from userDetails / userMatchesData / userDetailInfo) once Chat is ported.
        let isMatched = userMatchesData?.matchedUserID != nil || self.machedUserId != nil
        if isMyProfile == true || UserDataManager.shared.isUserSubscriptionDone == true || isMatched {
            self.showComingSoon("Chat")
        } else {
            self.showSubscriptionPopUp(subscriptionPopUpType: .chat)
        }
    }
    
    func isUserSubscribed() {
        
//        SubscriptionManager.shared.isUserSubscribed { isSubscribed in
//                    DispatchQueue.main.async {
//                        if isSubscribed {
//                            print("User is subscribed")
//                            // Update UI accordingly
//                            self.redirectToChatScreen()
//                        } else {
//                            
//                        }
//                    }
//                }
        
        self.aOtherUserProfileViewModel.getCheckUserSubscribedAPI()
    }
    
    func userNotSubscribed() {
        
        print("User is NOT subscribed")
        var chatUserId:Int = 0
        
        if self.isMyProfile == true {
            
            chatUserId = self.userDetails?.userInfo?.userID ?? 0
            
            
        } else if self.fromExploreScreen == true {
            
            if self.fromExploreMatches == true {
                chatUserId = self.userMatchesData?.userID ?? 0
            } else {
                chatUserId = self.userDetailInfo?.userID ?? 0
            }
            
            
            
            
        } else if self.fromChatScreen == true {
            
            chatUserId = self.userDetailInfo?.userID ?? 0
            
        } else {
            
            chatUserId = self.userData?.userId ?? 0
        }
        
        
        self.showSubscriptionPopUp(isToChatView: true, chatUserID: chatUserId, subscriptionPopUpType: .chat)
        // Show subscription screen

        
    }

    func regssterCell(){
        //self.interestCollectionView.collectionViewLayout = createInterestCollectionLayout()
        self.interestCollectionView.register(UINib(nibName: UserInterestCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: UserInterestCollectionViewCell.identifier)
        self.interestCollectionView.delegate = self
        self.interestCollectionView.dataSource = self
        self.interestCollectionView.reloadData()

        self.collVWMoment.register(UINib(nibName: MomentCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: MomentCollectionViewCell.identifier)
        self.collVWMoment.delegate = self
        self.collVWMoment.dataSource = self
        self.collVWMoment.reloadData()

        self.aboutMeTableView.register(UINib(nibName: MoreAboutMeTableViewCell.identifier, bundle: nil), forCellReuseIdentifier: MoreAboutMeTableViewCell.identifier)
        self.aboutMeTableView.delegate = self
        self.aboutMeTableView.dataSource = self
        
        self.imageCollectionView.collectionViewLayout = createAddImageCollectionLayout()
        self.imageCollectionView.register(UINib(nibName: ImageCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: ImageCollectionViewCell.identifier)
        self.interestCollectionView.reloadData()
        
        
        layout.itemSize = CGSize(width: 165, height: 226) // Adjust size as needed
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        self.collVWMoment.collectionViewLayout = layout
    }
    
    func updateCollectionViewMomentsHeight() {
        
        let myMomentCellWidth: CGFloat = (screen.width - 50)/2
        guard let layout = collVWMoment.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        
        let itemHeight = 144 //layout.itemSize.height
        let itemSpacing = layout.minimumLineSpacing
        let numberOfItems = collVWMoment.numberOfItems(inSection: 0)
        
        let count = numberOfItems % 2 == 0 ? numberOfItems : (numberOfItems + 1)
        
        // Calculate total height
        let totalHeight = CGFloat(count/2) * (myMomentCellWidth * 1.3048 + 12)
        //(CGFloat(itemHeight) * CGFloat(numberOfItems)) + (itemSpacing * CGFloat(numberOfItems))
        
        // Update collection view height constraint
        collectionViewHeightConstraint.constant = totalHeight
        if self.momentImgs.count > 0 {
            if isMyProfile == true {
                self.vwHeightConst.constant = totalHeight + 550
            } else {
                self.vwHeightConst.constant = totalHeight + 610
            }
            
            //self.collVWMoment.frame.height
        } else {
            self.vwHeightConst.constant =  totalHeight + 410
        }
        
        view.layoutIfNeeded()
        
    }
    
    func updateCollVwImageHeight() {
//        guard let layout = imageCollectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
//        
//        let itemHeight = layout.itemSize.height
//        let itemSpacing = layout.minimumLineSpacing
//        let numberOfItems = imageCollectionView.numberOfItems(inSection: 0)
//        
//        // Calculate total height
//        let totalHeight = (itemHeight * CGFloat(numberOfItems)) + (itemSpacing * CGFloat(numberOfItems - 1))
        
        //imageCollectionView.collectionViewLayout = UICollectionViewFlowLayout()
        
        imageCollectionView.layoutIfNeeded() // Ensure the layout is up-to-date

        
        
        var totalHeight = imageCollectionView.frame.height
        
        //self.imageCollectionView.frame.height
        
        if isMyProfile == true {
            if self.arrUserImages.count < 4 && self.arrUserImages.count > 0 {
                //totalHeight = (totalHeight / 3) * 2
                //(self.imageCollectionView.frame.height / 3) * 2
                self.vwDistanceColl.constant = -100
                
                collvwImageHeightConstraint.constant = totalHeight
                
                
                    self.viewHeight = self.viewHeight + Int(totalHeight - 100 + 20)
                    self.vwHeightConst.constant = CGFloat(self.viewHeight)
                
                
            } else if self.arrUserImages.count == 0 {
                self.vwDistanceColl.constant = 10
                
                collvwImageHeightConstraint.constant = 0
                
                
                    self.viewHeight = (self.viewHeight + Int(self.vwDistanceColl.constant))
                    self.vwHeightConst.constant = CGFloat(self.viewHeight)
               
                
            } else {
                collvwImageHeightConstraint.constant = totalHeight
                
                
                    self.viewHeight = self.viewHeight + Int(totalHeight + 20)
                    self.vwHeightConst.constant = CGFloat(self.viewHeight)
                
            }
            
        } else {
            if self.arrImagesData.count < 4 && self.arrImagesData.count > 0  {
                //totalHeight = (totalHeight / 3) * 2
                //(self.imageCollectionView.frame.height / 3) * 2
                self.vwDistanceColl.constant =  -100
                
                collvwImageHeightConstraint.constant = totalHeight
                
                
                    self.viewHeight = self.viewHeight + Int(totalHeight - 100 + 20)
                    self.vwHeightConst.constant = CGFloat(self.viewHeight)
                
                
            } else if self.arrImagesData.count == 0 {
                self.vwDistanceColl.constant = 10
                
                collvwImageHeightConstraint.constant = 0
                
                
                    self.viewHeight = (self.viewHeight + Int(self.vwDistanceColl.constant))
                    self.vwHeightConst.constant = CGFloat(self.viewHeight)
                
                
            } else {
                collvwImageHeightConstraint.constant = totalHeight
                
                
                    self.viewHeight = self.viewHeight + Int(totalHeight + 20)
                    self.vwHeightConst.constant = CGFloat(self.viewHeight)
                
            }
        }

        
        // Update collection view height constraint
        
        
        view.layoutIfNeeded()
    }

    func createInterestCollectionLayout() -> UICollectionViewLayout {

        let otherItemSize1 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1.0))
        let otherItem1 = NSCollectionLayoutItem(layoutSize: otherItemSize1)
        otherItem1.contentInsets = NSDirectionalEdgeInsets(top:4, leading: 4.5, bottom:8, trailing: 7)

        let otherItemSize2 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1.0))
        let otherItem2 = NSCollectionLayoutItem(layoutSize: otherItemSize2)
        otherItem2.contentInsets = NSDirectionalEdgeInsets(top:4, leading: 4.5, bottom:8, trailing: 7)

        let otherItemSize3 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1.0))
        let otherItem3 = NSCollectionLayoutItem(layoutSize: otherItemSize3)
        otherItem3.contentInsets = NSDirectionalEdgeInsets(top:4, leading:4.5, bottom: 8, trailing:7)

        let itemCount = Double(self.aOtherUserProfileViewModel.arrayInterest.count + 1)
        let numberOfRow = ceil(Double(itemCount/4))
        let fraction = 1.0/numberOfRow

        let mainGroupSize1 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(fraction))
        let mainGroup1 = NSCollectionLayoutGroup.horizontal(layoutSize: mainGroupSize1, subitems: [otherItem1,otherItem2,otherItem2, otherItem3])

        let section = NSCollectionLayoutSection(group: mainGroup1)

        return UICollectionViewCompositionalLayout(section: section)
    }
    
    func createAddImageCollectionLayout() -> UICollectionViewLayout {
        let firstItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.7), heightDimension: .fractionalHeight(1.0))
        let firstItem = NSCollectionLayoutItem(layoutSize: firstItemSize)
        firstItem.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 7.5, trailing: 15)

        let otherItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.5))
        let otherItem = NSCollectionLayoutItem(layoutSize: otherItemSize)
        otherItem.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 7.5, trailing: 0)

        let other1ItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.5))
        let other1Item = NSCollectionLayoutItem(layoutSize: other1ItemSize)
        other1Item.contentInsets = NSDirectionalEdgeInsets(top: 2.5, leading: 0, bottom:7.5, trailing: 0)

        let otherGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.3), heightDimension: .fractionalHeight(1.0))
        let otherGroup = NSCollectionLayoutGroup.vertical(layoutSize: otherGroupSize, subitems: [otherItem,other1Item])


        let otherItemSize1 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1.0))
        let otherItem1 = NSCollectionLayoutItem(layoutSize: otherItemSize1)
        otherItem1.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 15)

        let otherItemSize2 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1.0))
        let otherItem2 = NSCollectionLayoutItem(layoutSize: otherItemSize2)
        otherItem2.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 15)

        let otherItemSize3 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.3), heightDimension: .fractionalHeight(1.0))
        let otherItem3 = NSCollectionLayoutItem(layoutSize: otherItemSize3)
        otherItem3.contentInsets = NSDirectionalEdgeInsets(top: 5, leading:0, bottom: 5, trailing:0)

        let otherGroupSize12 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.7), heightDimension: .fractionalHeight(1))
        let otherGroup12 = NSCollectionLayoutGroup.horizontal(layoutSize: otherGroupSize12, subitems: [otherItem1,otherItem2])

        let otherGroupSize3 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.33))
        let otherGroup3 = NSCollectionLayoutGroup.horizontal(layoutSize: otherGroupSize3, subitems: [otherGroup12,otherItem3])


        let mainGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.67))
        let mainGroup = NSCollectionLayoutGroup.horizontal(layoutSize: mainGroupSize, subitems: [firstItem, otherGroup])

        let mainGroupSize1 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
        let mainGroup1 = NSCollectionLayoutGroup.vertical(layoutSize: mainGroupSize1, subitems: [mainGroup, otherGroup3])

        let section = NSCollectionLayoutSection(group: mainGroup1)

        return UICollectionViewCompositionalLayout(section: section)
    }

    func setMomentCollectionViewHeight() -> CGFloat{
        let availableWidth = screen.width - 40
        let itemWidth = availableWidth / 2
        return itemWidth
    }

    func setInterestCollectionViewHeight(){
        let availableWidth = screen.width - 94
        let itemInEachRow = 4.0
        let itemWidth = availableWidth/itemInEachRow
        var itemCount = 0.0
        if self.arrIntrestData.count > 0 {
            itemCount = Double(self.arrIntrestData[0].aOptions?.count ?? 0)
        }
        let numberOfRow = ceil(Double(itemCount/itemInEachRow))
        self.interestViewHeight.constant = ((numberOfRow * itemWidth * 0.83) + ((numberOfRow) * 12) + (numberOfRow * 10))
        
            self.viewHeight = self.viewHeight + Int(self.interestViewHeight.constant)
            self.vwHeightConst.constant = CGFloat(self.viewHeight)
        
    }
    
    private func applyGradientToButton() {
            let gradient = CAGradientLayer()
            gradient.colors = [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = btnBack.bounds
            gradient.cornerRadius = btnBack.layer.cornerRadius

            // Add gradient behind button text
        btnBack.layer.insertSublayer(gradient, at: 0)

            // Fix gradient on rotation
        btnBack.layoutIfNeeded()
        }

    private func applyBlurBehindButton() {
        let blurEffect = UIBlurEffect(style: .light)
        let blurView = UIVisualEffectView(effect: blurEffect)
        
        blurView.frame = btnBack.bounds
        blurView.layer.cornerRadius = btnBack.layer.cornerRadius
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        
        btnBack.insertSubview(blurView, at: 0)
    }
    
    private func applyShadowToButton() {
//        btnBack.layer.shadowColor = AppColor.AthensGray.cgColor
        btnBack.layer.shadowColor = UIColor.black.cgColor
        btnBack.layer.shadowOpacity = 1
        btnBack.layer.shadowOffset = CGSize(width: 0, height: 0)
        btnBack.layer.shadowRadius = 4
        btnBack.layer.masksToBounds = false
    }

    
    func setMoreAboutTableViewHeight(count:Int){
        //let count = aOtherUserProfileViewModel.arrayMoreAboutMe.count
        self.aboutMeTableView.layoutIfNeeded()
        self.moreAboutMeViewHeight.constant = CGFloat(count * 42)
        self.moreAboutTblHeight.constant = CGFloat(count * 42)
        if self.isMyProfile == true {
            
                self.viewHeight = self.viewHeight + Int(self.moreAboutMeViewHeight.constant) + 550
                self.vwHeightConst.constant = CGFloat(self.viewHeight)
            
        } else {
            
                self.viewHeight = self.viewHeight + 610 + Int(self.moreAboutMeViewHeight.constant)
                self.vwHeightConst.constant = CGFloat(self.viewHeight)
           
            
        }

    }

    @IBAction func sellAllActionButtonTapped(_ sender: UIButton) {
        let aOtherUserPhotoGridViewController = OtherUserPhotoGridViewController.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aOtherUserPhotoGridViewController, animated: true)
    }

    @IBAction func deleteButtonTapped(_ sender: UIButton) {
        //
    }
    
    @IBAction func messageButtonTapped(_ sender: UIButton) {
        self.showComingSoon("Chat")
    }

    @IBAction func voiceCallButtonTapped(_ sender: UIButton) {
        self.showComingSoon("Voice call")
    }

    @IBAction func DotButtonTapped(_ sender: UIButton) {
        if UserDataManager.shared.userID == self.userDetailInfo?.userID || self.isMyProfile == true {
            //
        } else {
            self.blockReportView.isHidden = !(self.blockReportView.isHidden)
        }
//        if UserDataManager.shared.userID == self.userDetailInfo?.userID || self.isMyProfile == true {
//            self.blockReportView.isHidden = true
//            self.deleteButtonView.isHidden = !(self.deleteButtonView.isHidden)
//        } else {
//            self.deleteButtonView.isHidden =  true
//            self.blockReportView.isHidden = !(self.blockReportView.isHidden)
//        }
       
    }
    
    func filterAttributesBasedOnUserInfo(attributes: [AttributesData], userInfo: UserHome?, forNilKeys:Bool = false) -> [AttributesData] {
        
        let nilKeys = extractNilKeys(from: userInfo, forNilKeys: forNilKeys)
        
        var filteredAttributes = attributes.filter { attribute in
            if let alias = attribute.alias {
                return (nilKeys.index(forKey: alias) != nil)
            }
            return false
        }
        //contains(alias)
        
        if forNilKeys == false {
            
            filteredAttributes = filteredAttributes.map { attributes in
                var updatedAttributes = attributes
                for (key, value) in nilKeys {
                    if key == updatedAttributes.alias {
                        if var options = updatedAttributes.aOptions {
                            options = options.map { option in
                                var updatedOption = option
                                if updatedOption.id == value as? Int {
                                    updatedOption.isSelected = true
                                }
                                return updatedOption
                            }
                            updatedAttributes.aOptions = options
                        }
                    }
                }
                return updatedAttributes
            }
            
            print("new.........",filteredAttributes)
        }
        
        print("questions........",filteredAttributes)
        return filteredAttributes
    }
    
    func extractNilKeys(from userInfo: UserHome?, forNilKeys:Bool = false) -> [String:Any] {
        guard let userInfo = userInfo else { return [:] }
        
        var nilKeys: [String:Any] = [:]
        
        let properties: [(String, Any?)] = [
            
            
            ("sexuality", userInfo.sexuality),
            ("height", userInfo.height),
            ("weight", userInfo.weight),
            ("eyecolor", userInfo.eyeColour),
            ("haircolor", userInfo.hairColour),
            ("living", userInfo.living),
            ("children", userInfo.children),
            ("smoking", userInfo.smoking),
            ("drinking", userInfo.drinking),
            ("motherTongue", userInfo.motherTongue),
            ("marital_status", userInfo.maritalStatus),
            ("relationship", userInfo.relationship),
            ("religion", userInfo.religion),
            ("education", userInfo.education),
            ("employedIn", userInfo.employedIn)
        ]
        
        //("interest",userInfo.interests),
//        ("dob", userInfo.dob),
//        ("gender", userInfo.gender),
        
        for (key, value) in properties {
            nilKeys.updateValue(value ?? "", forKey: key)
        }
        
        return nilKeys
    }
    
    
    func extractKeysIntrest(from userInfo: UserHome?) -> [String:[Int]] {
        guard let userInfo = userInfo else { return [:] }
        
        var nilKeys: [String:[Int]] = [:]
        
        let properties: [(String, Any?)] = [("interest",userInfo.interests)]
        
        //("interest",userInfo.interests),
//        ("dob", userInfo.dob),
//        ("gender", userInfo.gender),
        
        for (key, value) in properties {
            if value != nil {
                nilKeys.updateValue(value as! [Int], forKey: key)
          }
        }
        
        return nilKeys
    }
    
    func filterIntrestInfo(attributes: [AttributesData], userInfo: UserHome?) -> [AttributesData] {
        
        let nilKeys = extractKeysIntrest(from: userInfo)
        
        var filteredAttributes = attributes.filter { attribute in
            if let alias = attribute.alias {
                return (nilKeys.index(forKey: alias) != nil)
            }
            return false
        }
        
        filteredAttributes = filteredAttributes.map { attributes in
            var updatedAttributes = attributes
            for (key, value) in nilKeys {
                if key == updatedAttributes.alias {
                    for val in value {
                        if var options = updatedAttributes.aOptions {
                            options = options.map { option in
                                var updatedOption = option
                                if updatedOption.id == val {
                                    updatedOption.isSelected = true
                                }
                                return updatedOption
                            }
                            updatedAttributes.aOptions = options
                        }
                        
                    }

                }
            }
            return updatedAttributes
        }
        return filteredAttributes
    }
    
    
    func filterAttributesBasedOnUserData(attributes: [AttributesData], userInfo: UserDetailInfo?, forNilKeys:Bool = false) -> [AttributesData] {
        
        let nilKeys = extractNilKeysUserData(from: userInfo, forNilKeys: forNilKeys)
        
        var filteredAttributes = attributes.filter { attribute in
            if let alias = attribute.alias {
                return (nilKeys.index(forKey: alias) != nil)
            }
            return false
        }
        //contains(alias)
        
        if forNilKeys == false {
            
            filteredAttributes = filteredAttributes.map { attributes in
                var updatedAttributes = attributes
                for (key, value) in nilKeys {
                    if key == updatedAttributes.alias {
                        if var options = updatedAttributes.aOptions {
                            options = options.map { option in
                                var updatedOption = option
                                if updatedOption.id == value as? Int {
                                    updatedOption.isSelected = true
                                }
                                return updatedOption
                            }
                            updatedAttributes.aOptions = options
                        }
                    }
                }
                return updatedAttributes
            }
            
            print("new.........",filteredAttributes)
        }
        
        print("questions........",filteredAttributes)
        return filteredAttributes
    }
    
    func extractNilKeysUserData(from userInfo: UserDetailInfo?, forNilKeys:Bool = false) -> [String:Any] {
        guard let userInfo = userInfo else { return [:] }
        
        var nilKeys: [String:Any] = [:]
        
        let properties: [(String, Any?)] = [
            
            
            ("sexuality", userInfo.sexuality),
            ("height", userInfo.height),
            ("weight", userInfo.weight),
            ("eyecolor", userInfo.eyeColour),
            ("haircolor", userInfo.hairColour),
            ("living", userInfo.living),
            ("children", userInfo.children),
            ("smoking", userInfo.smoking),
            ("drinking", userInfo.drinking),
            ("motherTongue", userInfo.motherTongue),
            ("marital_status", userInfo.maritalStatus),
            ("relationship", userInfo.relationship),
            ("religion", userInfo.religion),
            ("education", userInfo.education),
            ("employedIn", userInfo.employedIn)
        ]
        
        //("interest",userInfo.interests),
//        ("dob", userInfo.dob),
//        ("gender", userInfo.gender),
        
        for (key, value) in properties {
            nilKeys.updateValue(value ?? "", forKey: key)
        }
        
        return nilKeys
    }
    
    func filterUserDataIntrestInfo(attributes: [AttributesData], userInfo: UserDetailInfo?) -> [AttributesData] {
        
        let nilKeys = extractKeysUserDataIntrest(from: userInfo)
        
        var filteredAttributes = attributes.filter { attribute in
            if let alias = attribute.alias {
                return (nilKeys.index(forKey: alias) != nil)
            }
            return false
        }
        
        filteredAttributes = filteredAttributes.map { attributes in
            var updatedAttributes = attributes
            for (key, value) in nilKeys {
                if key == updatedAttributes.alias {
                    for val in value {
                        if var options = updatedAttributes.aOptions {
                            options = options.map { option in
                                var updatedOption = option
                                if updatedOption.id == val {
                                    updatedOption.isSelected = true
                                }
                                return updatedOption
                            }
                            updatedAttributes.aOptions = options
                        }
                        
                    }

                }
            }
            return updatedAttributes
        }
        return filteredAttributes
    }
    
    func extractKeysUserDataIntrest(from userInfo: UserDetailInfo?) -> [String:[Int]] {
        guard let userInfo = userInfo else { return [:] }
        
        var nilKeys: [String:[Int]] = [:]
        
        let properties: [(String, Any?)] = [("interest",userInfo.interests)]
        
        //("interest",userInfo.interests),
//        ("dob", userInfo.dob),
//        ("gender", userInfo.gender),
        
        for (key, value) in properties {
            if value != nil {
                nilKeys.updateValue(value as! [Int], forKey: key)
          }
        }
        
        return nilKeys
    }
    
    
    func filterUserMatchesIntrestInfo(attributes: [AttributesData], userInfo: MatchedUser?) -> [AttributesData] {
        
        let nilKeys = extractKeysUserMatchesIntrest(from: userInfo)
        
        var filteredAttributes = attributes.filter { attribute in
            if let alias = attribute.alias {
                return (nilKeys.index(forKey: alias) != nil)
            }
            return false
        }
        
        filteredAttributes = filteredAttributes.map { attributes in
            var updatedAttributes = attributes
            for (key, value) in nilKeys {
                if key == updatedAttributes.alias {
                    for val in value {
                        if var options = updatedAttributes.aOptions {
                            options = options.map { option in
                                var updatedOption = option
                                if updatedOption.id == val {
                                    updatedOption.isSelected = true
                                }
                                return updatedOption
                            }
                            updatedAttributes.aOptions = options
                        }
                        
                    }

                }
            }
            return updatedAttributes
        }
        return filteredAttributes
    }
    
    func extractKeysUserMatchesIntrest(from userInfo: MatchedUser?) -> [String:[Int]] {
        guard let userInfo = userInfo else { return [:] }
        
        var nilKeys: [String:[Int]] = [:]
        
        let properties: [(String, Any?)] = [("interest",userInfo.interests)]
        
        //("interest",userInfo.interests),
//        ("dob", userInfo.dob),
//        ("gender", userInfo.gender),
        
        for (key, value) in properties {
            if value != nil {
                nilKeys.updateValue(value as! [Int], forKey: key)
          }
        }
        
        return nilKeys
    }
    
    func filterAttributesBasedOnMatches(attributes: [AttributesData], userInfo: MatchedUser?, forNilKeys:Bool = false) -> [AttributesData] {
        
        let nilKeys = extractNilKeysMatches(from: userInfo, forNilKeys: forNilKeys)
        
        var filteredAttributes = attributes.filter { attribute in
            if let alias = attribute.alias {
                return (nilKeys.index(forKey: alias) != nil)
            }
            return false
        }
        //contains(alias)
        
        if forNilKeys == false {
            
            filteredAttributes = filteredAttributes.map { attributes in
                var updatedAttributes = attributes
                for (key, value) in nilKeys {
                    if key == updatedAttributes.alias {
                        if var options = updatedAttributes.aOptions {
                            options = options.map { option in
                                var updatedOption = option
                                if updatedOption.id == value as? Int {
                                    updatedOption.isSelected = true
                                }
                                return updatedOption
                            }
                            updatedAttributes.aOptions = options
                        }
                    }
                }
                return updatedAttributes
            }
            
            print("new.........",filteredAttributes)
        }
        
        print("questions........",filteredAttributes)
        return filteredAttributes
    }
    
    func extractNilKeysMatches(from userInfo: MatchedUser?, forNilKeys:Bool = false) -> [String:Any] {
        guard let userInfo = userInfo else { return [:] }
        
        var nilKeys: [String:Any] = [:]
        
        let properties: [(String, Any?)] = [
            
            
            ("sexuality", userInfo.sexuality),
            ("height", userInfo.height),
            ("weight", userInfo.weight),
            ("eyecolor", userInfo.eyeColour),
            ("haircolor", userInfo.hairColour),
            ("living", userInfo.living),
            ("children", userInfo.children),
            ("smoking", userInfo.smoking),
            ("drinking", userInfo.drinking),
            ("motherTongue", userInfo.motherTongue),
            ("marital_status", userInfo.maritalStatus),
            ("relationship", userInfo.relationship),
            ("religion", userInfo.religion),
            ("education", userInfo.education),
            ("employedIn", userInfo.employedIn)
        ]
        
        //("interest",userInfo.interests),
//        ("dob", userInfo.dob),
//        ("gender", userInfo.gender),
        
        for (key, value) in properties {
            nilKeys.updateValue(value ?? "", forKey: key)
        }
        
        return nilKeys
    }
}

extension OtherUserProfileViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView,numberOfItemsInSection section: Int) -> Int {
        switch collectionView {
        case collVWMoment:
            return self.momentImgs.count
        case interestCollectionView:
            if self.arrIntrestData.count > 0
            {
                return self.arrIntrestData[0].aOptions?.count ?? 0
            }
            return 0
        case imageCollectionView:
            if isMyProfile == true {
                if self.arrUserImages.count > 0
                {
                    return self.arrUserImages.count
                }
            } else {
                if self.arrImagesData.count > 0
                {
                    return self.arrImagesData.count
                }
            }
           
            return 0
        default:
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView {
        case collVWMoment:
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MomentCollectionViewCell.identifier, for: indexPath) as? MomentCollectionViewCell {
                if !self.momentImgs[indexPath.row].images.isEmpty {
                    cell.setUIMomentImg(data: self.momentImgs[indexPath.row].images[0])
                } else {
                    cell.imageViewMoment.image = UIImage(named: "delete-9")
                    cell.imageViewMoment.contentMode = .scaleToFill
                }
                return cell
            }
        case interestCollectionView:
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UserInterestCollectionViewCell.identifier, for: indexPath) as? UserInterestCollectionViewCell {
                cell.labelName.text = self.arrIntrestData[0].aOptions?[indexPath.row].title
                let imgUrl = ApiName.imgBaseURL + (self.arrIntrestData[0].aOptions?[indexPath.row].photo ?? "")
                cell.interestIcon.loadImage(with: URL(string: imgUrl))
                return cell
            }
        case imageCollectionView:
            if isMyProfile == true {
                if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ImageCollectionViewCell.identifier, for: indexPath) as? ImageCollectionViewCell {
                    let imgUrl = ApiName.imgBaseURL + (self.arrUserImages[indexPath.row].filename ?? "")
                    cell.setOtherUserImageUI(image: imgUrl)
                    cell.imageDeleButton.isHidden = true
                    return cell
                }
                
            } else {
                if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ImageCollectionViewCell.identifier, for: indexPath) as? ImageCollectionViewCell {
                    let imgUrl = ApiName.imgBaseURL + (self.arrImagesData[indexPath.row].image ?? "")
                    cell.setOtherUserImageUI(image: imgUrl)
                    cell.imageDeleButton.isHidden = true
                    return cell
                }
            }

        default:
            return UICollectionViewCell()
        }
        return UICollectionViewCell()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        switch collectionView {
        case collVWMoment:
//            let availableWidth = screen.width - 30
//            let itemWidth = availableWidth / 2
//            return CGSize(width: itemWidth, height: itemWidth)
            
            let itemsPerRow: CGFloat = 2
            let paddingSpace = layout.sectionInset.left + layout.sectionInset.right + layout.minimumInteritemSpacing * (itemsPerRow - 1)
            let availableWidth = collectionView.bounds.width - paddingSpace
            let widthPerItem = availableWidth / itemsPerRow
            return CGSize(width: widthPerItem, height: 226)
        case interestCollectionView:
            
            let numberOfItemsPerRow: CGFloat = 4 // Adjust for desired layout
            let spacing: CGFloat = 2//10 // Spacing between cells
            
            // Calculate total spacing
            let totalSpacing = (numberOfItemsPerRow - 1) * spacing //-1
            
            // Get the collection view width
            let width = screen.width - 100
        
            //collectionView.bounds.width - 94
            
            // Calculate the cell width
            let itemWidth = (width) / numberOfItemsPerRow
            //(width - totalSpacing ) / numberOfItemsPerRow
            
            return CGSize(width: itemWidth, height: 94)
            
        default:
            return CGSize(width: 0, height: 0)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        switch collectionView {
        case collVWMoment:
            return 10
        case interestCollectionView:
            return 13
        default:
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        switch collectionView {
        case collVWMoment:
            return 10
        case interestCollectionView:
            return 18
        default:
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch collectionView {
//        case momentCollectionView:
//            let aUserMomentsViewController:UserMomentsViewController = UserMomentsViewController.instantiateFromStoryboard()
//            aUserMomentsViewController.fromExploreScreen = fromExploreScreen
//            aUserMomentsViewController.selectedIndex = indexPath.row
//            self.navigationController?.pushViewController(aUserMomentsViewController, animated: true)
//        case interestCollectionView:
//            self.momentView.isHidden = !(self.momentView.isHidden)
//            self.seeAllButton.isHidden = self.momentView.isHidden
//            self.noMomentAvailableView.isHidden = !(self.noMomentAvailableView.isHidden)
            
        case imageCollectionView:
            
            if isMyProfile == true {
                self.dotButton.isHidden = true
//                aOtherUserImageVC.isMyProfile = true
//                aOtherUserImageVC.arrUserImg = arrUserImages
            } else if fromChatScreen == true {
                if UserDataManager.shared.userID == self.userDetailInfo?.userID ?? 0 {
                    return
                }
                let aOtherUserImageVC:ShowOtherUserImageVC = ShowOtherUserImageVC.instantiateFromStoryboard()
                aOtherUserImageVC.isMyProfile = false
                aOtherUserImageVC.userID = self.userDetailInfo?.userID ?? 0
                aOtherUserImageVC.imgUsers = arrImagesData
                aOtherUserImageVC.itemIndex = indexPath.item
                aOtherUserImageVC.userName = self.userDetailInfo?.displayName ?? ""
                
                aOtherUserImageVC.callBack = { [weak self] data in
                    if UserDataManager.shared.isUserSubscriptionDone == true {
                        //
                    } else {
                        self?.showSubscriptionPopUp(subscriptionPopUpType: .compliment)
                    }
                   
                }
                
                aOtherUserImageVC.modalPresentationStyle = .overCurrentContext  // No sheet
                aOtherUserImageVC.modalTransitionStyle = .crossDissolve         // Fade in/out

                self.present(aOtherUserImageVC, animated: true, completion: nil)
//                self.navigationController?.modalPresentationStyle = .currentContext
//                self.navigationController?.modalTransitionStyle = .coverVertical
//                self.navigationController?.present(aOtherUserImageVC, animated: true, completion: nil)
                
            } else if fromExploreScreen == true {
                
                if UserDataManager.shared.userID == self.userDetailInfo?.userID ?? 0 {
                    return
                }
                
                let aOtherUserImageVC:ShowOtherUserImageVC = ShowOtherUserImageVC.instantiateFromStoryboard()
                aOtherUserImageVC.isMyProfile = false
                aOtherUserImageVC.userID = self.userDetailInfo?.userID ?? 0
                aOtherUserImageVC.imgUsers = arrImagesData
                aOtherUserImageVC.itemIndex = indexPath.item
                aOtherUserImageVC.userName = self.userDetailInfo?.displayName ?? ""
                
                aOtherUserImageVC.callBack = { [weak self] data in
                    if UserDataManager.shared.isUserSubscriptionDone == true {
                        //
                    } else {
                        self?.showSubscriptionPopUp(subscriptionPopUpType: .compliment)
                    }
                   
                }
                
                aOtherUserImageVC.modalPresentationStyle = .overCurrentContext  // No sheet
                aOtherUserImageVC.modalTransitionStyle = .crossDissolve         // Fade in/out

                self.present(aOtherUserImageVC, animated: true, completion: nil)
            } else {
                
                if UserDataManager.shared.userID == self.userDetailInfo?.userID ?? 0 {
                    return
                }
                
                let aOtherUserImageVC:ShowOtherUserImageVC = ShowOtherUserImageVC.instantiateFromStoryboard()
                
                aOtherUserImageVC.isMyProfile = false
                aOtherUserImageVC.userID = userData?.userId ?? 0
                aOtherUserImageVC.imgUsers = arrImagesData
                aOtherUserImageVC.itemIndex = indexPath.item
                aOtherUserImageVC.userName = self.userMatchesData?.displayName ?? ""
                
                aOtherUserImageVC.modalPresentationStyle = .overCurrentContext  // No sheet
                aOtherUserImageVC.modalTransitionStyle = .crossDissolve         // Fade in/out

                self.present(aOtherUserImageVC, animated: true, completion: nil)
            }
            
            
            
            //self.navigationController?.pushViewController(aOtherUserImageVC, animated: true)
            
        case collVWMoment:
            self.showComingSoon("Moments")
        default:
            break
        }
    }
}

extension OtherUserProfileViewController: UITableViewDelegate, UITableViewDataSource{

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.arrAttribQuestions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if self.isMyProfile == true {
            
            if let cell = tableView.dequeueReusableCell(withIdentifier: MoreAboutMeTableViewCell.identifier, for: indexPath)as? MoreAboutMeTableViewCell{
                cell.setOtherUserDataUI(data: self.arrAttribQuestions[indexPath.row])
                return cell
            }
            
        } else {
            if let cell = tableView.dequeueReusableCell(withIdentifier: MoreAboutMeTableViewCell.identifier, for: indexPath)as? MoreAboutMeTableViewCell{
                cell.setOtherUserDataUI(data: self.arrAttribQuestions[indexPath.row])
                return cell
            }
        }
        
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

    }
}

