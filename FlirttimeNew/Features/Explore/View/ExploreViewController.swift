//
//  ExploreViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 21/05/24.
//

import UIKit
import Combine

class ExploreViewController: BaseViewController {

    @IBOutlet weak var exploreCollectionView: UICollectionView!
    @IBOutlet weak var lblLike: UILabel!
    @IBOutlet weak var lblYouLiked: UILabel!
    @IBOutlet weak var lblMatches: UILabel!
    @IBOutlet weak var lblCompliment: UILabel!
    @IBOutlet weak var lblCountLike: UILabel!
    @IBOutlet weak var lblCountYouLiked: UILabel!
    @IBOutlet weak var lblCountMatches: UILabel!
    @IBOutlet weak var lblCountCompliment: UILabel!
    @IBOutlet weak var vwLike: UIView!
    @IBOutlet weak var vwYouLiked: UIView!
    @IBOutlet weak var vwMatches: UIView!
    @IBOutlet weak var vwCompliment: UIView!
    @IBOutlet weak var vwNoDataFound: UIView!
    @IBOutlet weak var lineViewLike : UIView!
    @IBOutlet weak var lineViewYouLike : UIView!
    @IBOutlet weak var lineViewMatch : UIView!
    @IBOutlet weak var lineViewCompliment : UIView!
    
    private var desposeBag:Set<AnyCancellable> = []
    var aUserInteraction:InteractionResponse?
    var aMyLikeResp:MyLikeInteractionResponse?
    var aMyMatches:MatchResponse?
    var aComplimentListResponse: ComplimentListResponse?
    var aReadComplimentResponse: ReadComplimentResponse?
    var strSelectedLike:String?
    
    var combinedData: [MyLikeInteractionResponse] = []
    var aExploreViewModel = ExploreViewModel()
    var exploreImageCellWidth = (screen.width - 44)/2
    let layout = UICollectionViewFlowLayout()
    var scrollTranslation: Double = 0.0
  
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setRegister()
        self.setUpBinding()
        self.strSelectedLike = Constants.UserInteractionTypes.likeYou
     //   self.aExploreViewModel.getUserIneractionAPI(interactioType: self.strSelectedLike ?? "")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.checkHideCustomButton(hide: false)
        self.aExploreViewModel.getStatucCountApi()
        if strSelectedLike == Constants.UserInteractionTypes.likeYou{
            self.likeButtonTapped(UIButton())
        }else if strSelectedLike == Constants.UserInteractionTypes.myLike{
            self.youLikedButtonTapped(UIButton())
        }else if strSelectedLike == Constants.UserInteractionTypes.matches{
            self.matchesButtonTapped(UIButton())
        }else if strSelectedLike == Constants.UserInteractionTypes.compliment{
            self.complimentButtonTapped(UIButton())
        }
        
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        AppTabBarController.buttonD.isHidden = false
       
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        AppTabBarController.buttonD.isHidden = true
    }
    
    func setUpBinding(){
        self.aExploreViewModel.$aUserInteraction.receive(on: DispatchQueue.main).sink(receiveValue: { model in
            if model != nil {
                if model?.status == true {
                    self.aUserInteraction = model
                    self.lblCountLike.text = "\(self.aUserInteraction?.data?.count ?? 0)"
                    if self.aUserInteraction?.data?.count ?? 0 > 0 {
                        self.lblCountLike.isHidden = false
                        self.vwLike.isHidden = false
                        self.vwNoDataFound.isHidden = true
                    } else {
                        self.lblCountLike.isHidden = true
                        self.vwLike.isHidden = true
                        self.vwNoDataFound.isHidden = false
                    }
                } else {
                    self.aUserInteraction = nil
                    self.lblCountLike.text = "0"
                    self.lblCountLike.isHidden = true
                    self.vwLike.isHidden = true
                    self.exploreCollectionView.reloadData()
                    self.vwNoDataFound.isHidden = false
                   // self.showNewAlertPopUp(Title: "Alert", Msg: model?.message ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
                        
                   // })
                }
               
                self.exploreCollectionView.reloadData()
            }
        }).store(in: &desposeBag)
        
        self.aExploreViewModel.$getStatusCount.receive(on: DispatchQueue.main).sink(receiveValue: { model in
            if model != nil {
                self.lblCountLike.text =  "\(model?.data?.like_count ?? 0)"
                self.lblCountCompliment.text = "\(model?.data?.compliment_count ?? 0)"
                self.lblCountYouLiked.text = "\((model?.data?.like_you_count ?? 0) + (model?.data?.favorite_count ?? 0))"
                self.lblCountMatches.text = "\(model?.data?.match_count ?? 0)"
            }
        }).store(in: &desposeBag)
        
        self.aExploreViewModel.$errorMessage.receive(on: DispatchQueue.main).sink(receiveValue: { error in
            if error != nil {
                
                self.aUserInteraction = nil
                self.lblCountLike.text = "0"
                self.lblCountLike.isHidden = true
                self.vwLike.isHidden = true
                self.exploreCollectionView.reloadData()
                self.vwNoDataFound.isHidden = false
                
            }
        }).store(in: &desposeBag)
        
        
        
        self.aExploreViewModel.$aMyLikeResponse.receive(on: DispatchQueue.main).sink(receiveValue: { model in
            if model != nil {
                
                self.aMyLikeResp = model
                self.lblCountYouLiked.text = "\(self.aMyLikeResp?.data.count ?? 0)"
                if self.aMyLikeResp?.data.count ?? 0 > 0 {
                    self.lblCountYouLiked.isHidden = false
                    self.vwYouLiked.isHidden = false
                    self.vwNoDataFound.isHidden = true
                } else {
                    self.lblCountYouLiked.isHidden = true
                    self.vwYouLiked.isHidden = true
                    self.vwNoDataFound.isHidden = false
                }
                self.exploreCollectionView.reloadData()
                
            }
        }).store(in: &desposeBag)
        
        self.aExploreViewModel.$errorMyLikeMessage.receive(on: DispatchQueue.main).sink(receiveValue: { error in
            if error != nil {
                
                self.aMyLikeResp = nil
                self.lblCountYouLiked.text = "0"
                self.lblCountYouLiked.isHidden = true
                self.vwYouLiked.isHidden = true
                self.exploreCollectionView.reloadData()
                self.vwNoDataFound.isHidden = false
                
            }
        }).store(in: &desposeBag)
        
        self.aExploreViewModel.$aMyMatches.receive(on: DispatchQueue.main).sink(receiveValue: { model in
            if model != nil {
                
                self.aMyMatches = model
                self.lblCountMatches.text = "\(self.aMyMatches?.data.count ?? 0)"
                if self.aMyMatches?.data.count ?? 0 > 0 {
                    self.lblCountMatches.isHidden = false
                    self.vwMatches.isHidden = false
                    self.vwNoDataFound.isHidden = true
                } else {
                    self.lblCountMatches.isHidden = true
                    self.vwMatches.isHidden = true
                    self.vwNoDataFound.isHidden = false
                }
                self.exploreCollectionView.reloadData()
            }
        }).store(in: &desposeBag)
        
        self.aExploreViewModel.$errorMyMatches.receive(on: DispatchQueue.main).sink(receiveValue: { error in
            if error != nil {
                
                self.aMyMatches = nil
                self.lblCountMatches.text = "0"
                self.lblMatches.isHidden = true
                self.vwMatches.isHidden = true
                self.exploreCollectionView.reloadData()
                self.vwNoDataFound.isHidden = false
                
            }
        }).store(in: &desposeBag)
        
        self.aExploreViewModel.$aComplimentListResponse.receive(on: DispatchQueue.main).sink(receiveValue: { model in
            if model != nil {
                
                self.aComplimentListResponse = model
                self.vwNoDataFound.isHidden = self.aComplimentListResponse?.data?.compliments?.count ?? 0 > 0 ? true : false
                self.lblCountCompliment.text = "\(self.aComplimentListResponse?.data?.compliments?.count ?? 0)"
                if self.aComplimentListResponse?.data?.compliments?.count ?? 0 > 0 {
                    self.lblCountCompliment.isHidden = false
                    self.vwCompliment.isHidden = false
                    self.vwNoDataFound.isHidden = true
                } else {
                    self.lblCountCompliment.isHidden = true
                    self.vwCompliment.isHidden = true
                    self.vwNoDataFound.isHidden = false
                }
                self.exploreCollectionView.reloadData()
                
            }
        }).store(in: &desposeBag)
        
        self.aExploreViewModel.$errorCompliment.receive(on: DispatchQueue.main).sink(receiveValue: { error in
            if error != nil {
                
                self.aComplimentListResponse = nil
                self.lblCountCompliment.text = "0"
                self.lblCompliment.isHidden = true
                self.vwCompliment.isHidden = true
                self.exploreCollectionView.reloadData()
                self.vwNoDataFound.isHidden = false
                
            }
        }).store(in: &desposeBag)
        
        self.aExploreViewModel.$aReadComplimentResponse.receive(on: DispatchQueue.main).sink(receiveValue: { model in
            if model != nil {
                self.aReadComplimentResponse = model
                if model?.data != nil {
                    self.showComingSoon("Chat")
                }
            }
        }).store(in: &desposeBag)
        
        self.aExploreViewModel.$errorReadCompliment.receive(on: DispatchQueue.main).sink(receiveValue: { error in
            if error != nil {
                self.showNewAlertPopUp(Title: "Error", Msg: "Compliment data not found", isSuccess: false, CompletionHandler: {(success) -> Void in
                    
                })
            }
        }).store(in: &desposeBag)
        
    }

    func setRegister(){
        self.exploreCollectionView.register(UINib(nibName: UserInteractionCVC.identifier, bundle: nil), forCellWithReuseIdentifier: UserInteractionCVC.identifier)
        self.exploreCollectionView.delegate = self
        self.exploreCollectionView.dataSource = self
        self.exploreCollectionView.reloadData()
    
        layout.itemSize = CGSize(width: 165, height: 226) // Adjust size as needed
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        self.exploreCollectionView.collectionViewLayout = layout
    }

    @IBAction func notificationButtonTapped(_ sender: UIButton) {
        let aNotificationViewController:NotificationViewController = NotificationViewController.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aNotificationViewController, animated: true)
    }

    @IBAction func applyFilterButtonTapped(_ sender: UIButton) {
        let aExploreFilterViewController:ExploreFilterViewController = ExploreFilterViewController.instantiateFromStoryboard()
        aExploreFilterViewController.modalPresentationStyle = .overCurrentContext
        self.tabBarController?.present(aExploreFilterViewController, animated: true, completion: nil)
    }
    
    @IBAction func likeButtonTapped(_ sender: UIButton) {
        self.lineViewLike.backgroundColor = AppColor.Punch
        self.lineViewMatch.backgroundColor = AppColor.AthensGray
        self.lineViewYouLike.backgroundColor = AppColor.AthensGray
        self.lineViewCompliment.backgroundColor = AppColor.AthensGray
        self.hideShowTabBar(isHide: false)
        self.strSelectedLike = Constants.UserInteractionTypes.likeYou
        
        lblLike.textColor = AppColor.MineShaft
        vwLike.backgroundColor = AppColor.Punch
        
        lblYouLiked.textColor = AppColor.LabelTextColor
        vwYouLiked.backgroundColor = AppColor.LabelBackgroundView
        lblMatches.textColor = AppColor.LabelTextColor
        vwMatches.backgroundColor = AppColor.LabelBackgroundView
        lblCompliment.textColor = AppColor.LabelTextColor
        vwMatches.backgroundColor = AppColor.LabelBackgroundView
        self.aExploreViewModel.getUserIneractionAPI(interactioType: Constants.UserInteractionTypes.likeYou)
    }
    
    @IBAction func youLikedButtonTapped(_ sender: UIButton) {
        
        self.lineViewLike.backgroundColor = AppColor.AthensGray
        self.lineViewMatch.backgroundColor = AppColor.AthensGray
        self.lineViewYouLike.backgroundColor = AppColor.Punch
        self.lineViewCompliment.backgroundColor = AppColor.AthensGray
        
        self.strSelectedLike = Constants.UserInteractionTypes.myLike
        
        lblYouLiked.textColor = AppColor.MineShaft
        vwYouLiked.backgroundColor = AppColor.Punch
        
        lblLike.textColor = AppColor.LabelTextColor
        vwLike.backgroundColor = AppColor.LabelBackgroundView
        lblMatches.textColor = AppColor.LabelTextColor
        vwMatches.backgroundColor = AppColor.LabelBackgroundView
        lblCompliment.textColor = AppColor.LabelTextColor
        vwMatches.backgroundColor = AppColor.LabelBackgroundView
        self.aExploreViewModel.getUserIneractionMyLikeAPI(interactioType: Constants.UserInteractionTypes.myLike)
//        self.aExploreViewModel.getUserIneractionMyLikeAPI(interactioType: Constants.UserInteractionTypes.myFavorite)
    }
    
    @IBAction func matchesButtonTapped(_ sender: UIButton) {
        
        self.lineViewLike.backgroundColor = AppColor.AthensGray
        self.lineViewMatch.backgroundColor = AppColor.Punch
        self.lineViewYouLike.backgroundColor = AppColor.AthensGray
        self.lineViewCompliment.backgroundColor = AppColor.AthensGray
        self.hideShowTabBar(isHide: false)
        self.strSelectedLike = Constants.UserInteractionTypes.matches
        
        lblMatches.textColor = AppColor.MineShaft
        vwMatches.backgroundColor = AppColor.Punch
        
        lblLike.textColor = AppColor.LabelTextColor
        vwLike.backgroundColor = AppColor.LabelBackgroundView
        lblYouLiked.textColor = AppColor.LabelTextColor
        vwYouLiked.backgroundColor = AppColor.LabelBackgroundView
        lblCompliment.textColor = AppColor.LabelTextColor
        vwCompliment.backgroundColor = AppColor.LabelBackgroundView
        
        self.aExploreViewModel.getUserMatchesAPI()
    }
    
    @IBAction func complimentButtonTapped(_ sender: UIButton) {
        
        self.lineViewLike.backgroundColor = AppColor.AthensGray
        self.lineViewMatch.backgroundColor = AppColor.AthensGray
        self.lineViewYouLike.backgroundColor = AppColor.AthensGray
        self.lineViewCompliment.backgroundColor = AppColor.Punch
        self.hideShowTabBar(isHide: false)
        self.strSelectedLike = Constants.UserInteractionTypes.compliment
        lblCompliment.textColor = AppColor.MineShaft
        vwCompliment.backgroundColor = AppColor.Punch
        
        lblLike.textColor = AppColor.LabelTextColor
        vwLike.backgroundColor = AppColor.LabelBackgroundView
        lblYouLiked.textColor = AppColor.LabelTextColor
        vwYouLiked.backgroundColor = AppColor.LabelBackgroundView
        lblMatches.textColor = AppColor.LabelTextColor
        vwMatches.backgroundColor = AppColor.LabelBackgroundView
        self.aExploreViewModel.getComplimentListApi()
    }
    
    func calculateAge(from dateString: String) -> Int? {
        // Define the date formatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd" // Specify the date format
        dateFormatter.locale = Locale.current    // Use device's current locale
        dateFormatter.timeZone = TimeZone.current // Use device's current timezone
        // Convert the string to a Date object
        guard let birthDate = dateFormatter.date(from: dateString) else {
            print("Invalid date format")
            return nil
        }
        
        // Calculate the age using Calendar
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: now)
        return ageComponents.year
    }
}

extension ExploreViewController:UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if strSelectedLike == Constants.UserInteractionTypes.likeYou {
            if aUserInteraction?.data != nil {
                return aUserInteraction?.data?.count ?? 0
            }
        } else if strSelectedLike == Constants.UserInteractionTypes.myLike {
            if aMyLikeResp?.data != nil {
                return aMyLikeResp?.data.count ?? 0
            }
        }  else if strSelectedLike == Constants.UserInteractionTypes.matches {
            if aMyMatches?.data != nil {
                return aMyMatches?.data.count ?? 0
            }
        } else if strSelectedLike == Constants.UserInteractionTypes.compliment {
            if aComplimentListResponse?.data?.compliments != nil {
                return aComplimentListResponse?.data?.compliments?.count ?? 0
            }
        }
        
        return 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UserInteractionCVC.identifier, for: indexPath) as? UserInteractionCVC {
            cell.removeBlur()
            cell.superLikeImgView.isHidden = true
            if strSelectedLike == Constants.UserInteractionTypes.likeYou {
                
                let imgUrl = ApiName.imgBaseURL + (self.aUserInteraction?.data?[indexPath.item].userInfo?.avatar ?? "")
                cell.userImage.loadImage(with: URL(string: imgUrl))
                cell.lblName.text = "\(self.aUserInteraction?.data?[indexPath.item].userInfo?.displayName ?? ""), \(self.calculateAge(from: self.aUserInteraction?.data?[indexPath.item].userInfo?.dob ?? "") ?? 0)"
                if self.aUserInteraction?.data?[indexPath.item].userInfo?.isActive == true {
                    cell.imgVerify.isHidden = false
                } else {
                    cell.imgVerify.isHidden = true
                }
                if UserDataManager.shared.isUserSubscriptionDone != true {
                    cell.applyBlur()
                }
                
            } else if strSelectedLike == Constants.UserInteractionTypes.myLike {
                
                let imgUrl = ApiName.imgBaseURL + (self.aMyLikeResp?.data[indexPath.item].userInfo.avatar ?? "")
                cell.userImage.loadImage(with: URL(string: imgUrl))
                if self.aMyLikeResp?.data[indexPath.item].interactionType == 2 {
                    cell.superLikeImgView.isHidden = false
                } else {
                    cell.superLikeImgView.isHidden = true
                }
                cell.lblName.text = "\(self.aMyLikeResp?.data[indexPath.item].userInfo.displayName ?? ""), \(self.calculateAge(from: self.aMyLikeResp?.data[indexPath.item].userInfo.dob ?? "") ?? 0)"
                if self.aMyLikeResp?.data[indexPath.item].userInfo.isActive == true {
                    cell.imgVerify.isHidden = false
                } else {
                    cell.imgVerify.isHidden = true
                }
            }  else if strSelectedLike == Constants.UserInteractionTypes.matches {
                
                let imgUrl = ApiName.imgBaseURL + (self.aMyMatches?.data[indexPath.item].avatar ?? "")
                cell.userImage.loadImage(with: URL(string: imgUrl))
                
                cell.lblName.text = "\(self.aMyMatches?.data[indexPath.item].displayName ?? ""), \(self.calculateAge(from: self.aMyMatches?.data[indexPath.item].dob ?? "") ?? 0)"
                
                cell.imgVerify.isHidden = true
                if self.aMyMatches?.data[indexPath.item].isActive == true {
                    cell.imgVerify.isHidden = false
                } else {
                    cell.imgVerify.isHidden = true
                }
            } else if strSelectedLike == Constants.UserInteractionTypes.compliment {
                let imgUrl = ApiName.imgBaseURL + (self.aComplimentListResponse?.data?.compliments?[indexPath.row].sender?.avatar ?? "")
                cell.userImage.loadImage(with: URL(string: imgUrl))
                cell.lblName.text = "\(self.aComplimentListResponse?.data?.compliments?[indexPath.row].sender?.displayName ?? "")" //\(self.calculateAge(from: self.aUserInteraction?.data[indexPath.item].userInfo.dob ?? "") ?? 0)"
                if self.aComplimentListResponse?.data?.compliments?[indexPath.row].sender?.isActive == true {
                    cell.imgVerify.isHidden = false
                } else {
                    cell.imgVerify.isHidden = true
                }
                if UserDataManager.shared.isUserSubscriptionDone != true {
                    cell.applyBlur()
                }
            }// true
            
            cell.userImage.translatesAutoresizingMaskIntoConstraints = false
            cell.userImage.contentMode = .scaleAspectFill
            cell.userImage.clipsToBounds = true
            cell.userImage.layer.cornerRadius = 8
            let padding: CGFloat = 12
            let availableWidth = collectionView.frame.width - (padding)
            let width = availableWidth / 2
            cell.wdImg.constant = width
            return cell
        }
        return UICollectionViewCell()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let aOtherUserProfileViewController:OtherUserProfileViewController = OtherUserProfileViewController.instantiateFromStoryboard()
        aOtherUserProfileViewController.fromExploreScreen = true
        
        if strSelectedLike == Constants.UserInteractionTypes.likeYou {
            aOtherUserProfileViewController.userDetailInfo = self.aUserInteraction?.data?[indexPath.item].userInfo
            if (UserDataManager.shared.isUserSubscriptionDone == true) && (strSelectedLike == Constants.UserInteractionTypes.likeYou) {
                self.navigationController?.pushViewController(aOtherUserProfileViewController, animated: true)
            } else {
                self.showSubscriptionPopUp(subscriptionPopUpType: .superLike)
            }
            
        }
        else if strSelectedLike == Constants.UserInteractionTypes.myLike {
            aOtherUserProfileViewController.userDetailInfo = self.aMyLikeResp?.data[indexPath.item].userInfo
            aOtherUserProfileViewController.isShowSuperLikeView = self.aMyLikeResp?.data[indexPath.item].interactionType == 1 ? true : false
            aOtherUserProfileViewController.fromExploreYouLike = true
            self.navigationController?.pushViewController(aOtherUserProfileViewController, animated: true)
        }
        else if strSelectedLike == Constants.UserInteractionTypes.matches {
            aOtherUserProfileViewController.fromExploreMatches = true
            aOtherUserProfileViewController.userMatchesData = self.aMyMatches?.data[indexPath.item]
            self.navigationController?.pushViewController(aOtherUserProfileViewController, animated: true)
        }
        else if strSelectedLike == Constants.UserInteractionTypes.compliment {
            if (UserDataManager.shared.isUserSubscriptionDone == true) && (strSelectedLike == Constants.UserInteractionTypes.compliment) {
                self.aExploreViewModel.readComplimentApi(id: self.aComplimentListResponse?.data?.compliments?[indexPath.row].id ?? 0)
            } else {
                self.showSubscriptionPopUp(subscriptionPopUpType: .chat)
            }
        }
    }

//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//        //return CGSize(width: exploreImageCellWidth , height: exploreImageCellWidth)
//        
//        let padding: CGFloat = 12
//    
//        let availableWidth = collectionView.frame.width - (padding)
//        //collectionView.frame.width - (padding * 3)
//        let width = availableWidth / 2
//        return CGSize(width: width, height: 226)
//    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let itemsPerRow: CGFloat = 2
        let paddingSpace = layout.sectionInset.left + layout.sectionInset.right + layout.minimumInteritemSpacing * (itemsPerRow - 1)
        let availableWidth = collectionView.bounds.width - paddingSpace
        let widthPerItem = availableWidth / itemsPerRow
        return CGSize(width: widthPerItem, height: 226)
    }
    


//    func scrollViewDidScroll(_ scrollView: UIScrollView) {
//
//        self.scrollTranslation = scrollView.panGestureRecognizer.translation(in: scrollView).y
//        hideShowTabBar(isHide:  self.scrollTranslation < 0)
//        scrollView.panGestureRecognizer.setTranslation(.zero, in: scrollView)
//    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollView.contentSize.height > scrollView.frame.height else {
                hideShowTabBar(isHide: false) // No scrolling possible — show tab bar
                return
            }
     
            let translation = scrollView.panGestureRecognizer.translation(in: scrollView).y
            hideShowTabBar(isHide: translation < 0)
        }
}
