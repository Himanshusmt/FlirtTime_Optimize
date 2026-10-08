//
//  EditAboutYouViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 29/05/24.
//

import UIKit
import Photos
import Combine

class EditAboutYouViewController: BaseViewController, Instantiable {

    var aEditAboutYouViewModel = EditAboutViewModel()
    static var storyboardName: StringConvertible {
        return StoryboardName.editProfile
    }

    @IBOutlet weak var dotImage1: UIImageView!
    @IBOutlet weak var dotView1: UIView!
    @IBOutlet weak var dotImage2: UIImageView!
    @IBOutlet weak var dotView2: UIView!
    @IBOutlet weak var dotImage3: UIImageView!
    @IBOutlet weak var dotView3: UIView!
    @IBOutlet weak var dotImage4: UIImageView!
    @IBOutlet weak var dotView4: UIView!
    @IBOutlet weak var dotImage5: UIImageView!
    @IBOutlet weak var dotView5: UIView!

    @IBOutlet weak var dotImage6: UIImageView!
    @IBOutlet weak var dotView6: UIView!
    @IBOutlet weak var dotImage7: UIImageView!
    @IBOutlet weak var dotView7: UIView!
    @IBOutlet weak var dotImage8: UIImageView!
    @IBOutlet weak var dotView8: UIView!
    @IBOutlet weak var dotImage9: UIImageView!
    @IBOutlet weak var dotView9: UIView!
    @IBOutlet weak var dotImage10: UIImageView!
    @IBOutlet weak var dotView10: UIView!
    
    @IBOutlet weak var dotImage11: UIImageView!
    @IBOutlet weak var dotView11: UIView!
    
    @IBOutlet weak var dotImage12: UIImageView!
    @IBOutlet weak var dotView12: UIView!

    @IBOutlet weak var subDotView1: UIView!
    @IBOutlet weak var subDotView2: UIView!
    @IBOutlet weak var subDotView3: UIView!
    @IBOutlet weak var subDotView4: UIView!
    @IBOutlet weak var subDotView5: UIView!
    @IBOutlet weak var subDotView6: UIView!
    @IBOutlet weak var subDotView7: UIView!
    @IBOutlet weak var subDotView8: UIView!
    @IBOutlet weak var subDotView9: UIView!
    @IBOutlet weak var subDotView10: UIView!
    
    @IBOutlet weak var subDotView11: UIView!
    @IBOutlet weak var subDotView12: UIView!

    @IBOutlet weak var aboutYouCollectionView: UICollectionView!
    @IBOutlet weak var aboutYourCollectionViewFlowLayout: UICollectionViewFlowLayout!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var previousButton: UIButton!
    @IBOutlet weak var skipButton: UIView!

    //var aEditAboutViewModel = EditAboutViewModel()
    var minPicValidate:Bool? = false
    var currentIndex:Int? = 0
    var aboutYouCompletionCallBack:(()->())?
    var scrollDebounceTimer: Timer?
    var images: [UIImage?] = Array(repeating: nil, count: 6) // Array to store images for each cell
    var imageSelectedIndex:Int?
    //var aMoreAboutMeQuestionData:MoreAboutMeQuestionModel?
    var aMoreAboutMeQuestionData:[AttributesData] = []
    private var selectedOptionData:[MoreAboutOption]? = []
    
    private var desposeBag:Set<AnyCancellable> = []

    //     EditProfile scenario
    var fromEditProfile:Bool? = false
    var selectedIndex:Int?
    var arrUITopDotView:[UIView] = []
    var isInterest:Bool? = false

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUpBinding()
        self.setUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.checkHideCustomButton(hide: true)
        
        if fromEditProfile == true {
            self.skipButton.isHidden = true
        }
        
        if self.selectedIndex != nil {
            
            scrollDebounceTimer?.invalidate()
            // Start a new debounce timer
            scrollDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                DispatchQueue.main.async {
//                    let currentIndex = max(0, self.aboutYouCollectionView.indexPathsForVisibleItems.first?.item ?? 0)
                    let nextIndex = min(self.selectedIndex ?? 0, self.aMoreAboutMeQuestionData.count - 1) //9 currentIndex
                    let nextIndexPath = IndexPath(item: nextIndex, section: 0)
                    self.aboutYouCollectionView.scrollToItem(at: nextIndexPath, at: .centeredHorizontally, animated: true)
                    self.setNextButtonUI(index: nextIndex)
                }
            }
            
            
        }
        
        if aMoreAboutMeQuestionData.count <= 1 {
           // let imgUrl = ApiName.imgBaseURL + (aMoreAboutMeQuestionData[0].photo ?? "")
            let imgUrl = ApiName.imgBaseURL + (aMoreAboutMeQuestionData.first?.photo ?? "")
            self.dotImage1.loadImage(with: URL(string: imgUrl))
        }
    }

//    override func viewDidAppear(_ animated: Bool) {
//        super.viewDidAppear(animated)
//        //if self.fromEditProfile ?? false
//        if self.fromEditProfile ?? false {
//            DispatchQueue.main.async {
//                let nextIndexPath = IndexPath(item:self.selectedIndex ?? 0, section: 0)
//                self.aboutYouCollectionView.scrollToItem(at: nextIndexPath, at: .centeredHorizontally, animated: false)
//                self.previousButton.isHidden = true
//                self.skipButton.isHidden = true
//                self.setNextButtonUI(index: self.selectedIndex ?? 0)
//            }
//        }
//    }

    func setUI(){
        
        arrUITopDotView = [subDotView1,subDotView2,subDotView3,subDotView4,subDotView5,subDotView6,subDotView7,subDotView8,subDotView9,subDotView10,subDotView11,subDotView12]
        
        for i in 0..<self.arrUITopDotView.count{
            arrUITopDotView[i].isHidden = true
        }
        
        for i in 0..<self.aMoreAboutMeQuestionData.count{
            if i < arrUITopDotView.count {
                arrUITopDotView[i].isHidden = false
            }
            
        }
        
        self.previousButton.isHidden = true
//        self.aEditAboutViewModel.educationalBackGroundArray = self.aMoreAboutMeQuestionData?.data?[1]
//        self.aEditAboutViewModel.drinkAlcoholArray = self.aMoreAboutMeQuestionData?.data?[2]
//        self.aEditAboutViewModel.smokingPreferenceArray = self.aMoreAboutMeQuestionData?.data?[3]
//        self.aEditAboutViewModel.childrenPlanArray = self.aMoreAboutMeQuestionData?.data?[4]
//        self.aEditAboutViewModel.religionChoiceArray = self.aMoreAboutMeQuestionData?.data?[0]
//        self.aEditAboutViewModel.lookingForRelationshipArray = self.aMoreAboutMeQuestionData?.data?[5]
//        self.aEditAboutViewModel.preferHeightArray = self.aMoreAboutMeQuestionData?.data?[6]
//        self.aEditAboutViewModel.exerciseArray = self.aMoreAboutMeQuestionData?.data?[7]
//        self.aEditAboutViewModel.partyPreferenceArray = self.aMoreAboutMeQuestionData?.data?[8]
//        self.aEditAboutViewModel.zodiacArray = self.aMoreAboutMeQuestionData?.data?[9]
        self.setupCollectionViewLayout()
    }
    
    func setUpBinding(){
        self.aEditAboutYouViewModel.$aUserDetailResponseModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                print("Success............")
                if self.fromEditProfile == true && self.selectedIndex == nil {
                    self.navigationController?.popViewController(animated: true)
                } else if self.currentIndex == self.aMoreAboutMeQuestionData.count - 1 {
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }.store(in: &desposeBag)
    }

    private func setupCollectionViewLayout() {
        guard let flowLayout = aboutYourCollectionViewFlowLayout else {return}
        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        flowLayout.itemSize = CGSize(width: UIScreen.main.bounds.width - 40, height: self.aboutYouCollectionView.frame.height)
        self.aboutYouCollectionView.collectionViewLayout = flowLayout
        self.aboutYouCollectionView.register(UINib(nibName: AboutYouCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: AboutYouCollectionViewCell.identifier)
        self.aboutYouCollectionView.delegate = self
        self.aboutYouCollectionView.dataSource = self
        self.aboutYouCollectionView.isScrollEnabled = false
        self.aboutYouCollectionView.isPagingEnabled = false
        self.aboutYouCollectionView.showsHorizontalScrollIndicator = false
        self.aboutYouCollectionView.backgroundColor = UIColor.clear
        self.aboutYouCollectionView.reloadData()
    }

    @IBAction func backButton(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }

    @IBAction func previousButtonTapped(_ sender: UIButton) {
        self.scrollToPreviousCell()
    }

    @IBAction func nextButtonTapped(_ sender: UIButton) {
        if self.fromEditProfile ?? false && self.selectedIndex == nil {
            //self.prepareSelectedDataToPost()
            self.submitQuestion()
            //self.navigationController?.popViewController(animated: true)
        } else if self.fromEditProfile ?? false && self.isInterest == true {
            
            
        } else {
            if self.currentIndex == self.aMoreAboutMeQuestionData.count - 1 {
                //self.prepareSelectedDataToPost()
                self.submitQuestion()
                //self.navigationController?.popViewController(animated: true)
            }else{
                self.submitQuestion()
                self.scrollToNextCell()
            }
        }
    }
    
    func submitQuestion() {
        
            
            let filteredResults = self.aMoreAboutMeQuestionData.compactMap { data -> FilteredResult? in
                guard let selectedOptions = data.aOptions?.filter({ $0.isSelected == true }), !selectedOptions.isEmpty else {
                    return nil
                }
                
                return FilteredResult(dataId: data.id, dataAlias: data.alias, selection_type: data.selection_type, selectedOptions: selectedOptions)
            }
            
        
            print(filteredResults)
            
            var param: [String: Any] = [:]
            
//                    ["sexuality":"","height":"","weight":"",
//                                 "eye_colour":"","hair_colour":"",
//                                 "living":"","children":"",
//                                 "smoking":"","drinking":"",
//                                 "interests":"","mother_tongue":"",
//                                 "marital_status":"","religion":"","education":""]
            
            for results in filteredResults {
                
                if results.selection_type == Constants.QuestionType.radio.rawValue {
                    
                    switch results.dataAlias {
                    case Constants.QuestionOption.children:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "children")
                    case Constants.QuestionOption.drinking:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "drinking")
                    case Constants.QuestionOption.education:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "education")
                    case Constants.QuestionOption.sexuality:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "sexuality")
                    case Constants.QuestionOption.height:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "height")
                    case Constants.QuestionOption.weight:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "weight")
                    case Constants.QuestionOption.eye_colour:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "eye_colour")
                    case Constants.QuestionOption.hair_colour:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "hair_colour")
                    case Constants.QuestionOption.living:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "living")
                    case Constants.QuestionOption.smoking:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "smoking")
                    case Constants.QuestionOption.relationship:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "relationship")
                    case Constants.QuestionOption.religion:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "religion")
                    case Constants.QuestionOption.education:
                        param.updateValue(results.selectedOptions[0].id ?? 0, forKey: "education")
                    default:
                        break
                    }
                    
                    
                } else {
                    switch results.dataAlias {
                    case Constants.QuestionOption.interests:
                        var intRes:[Int] = []
                        
                        for value in results.selectedOptions {
                            
                            intRes.append(value.id ?? 0)
                            
                        }
                        
                        param.updateValue(intRes, forKey: "interests")
                    default:
                        break
                    }
                }
                
            }
            print("question Answers Param.........",param)
            self.aEditAboutYouViewModel.callSaveUserDetailsAPI(filteredData:param)
            
    }

    func submitInerestData() {
        
        var param:[String:Any] = [:]
        var arrIntID = self.getSelectedInterestIds(from: self.aMoreAboutMeQuestionData[0])
        param = ["interests": arrIntID]
    
        print("Interest Answers Param.........",param)
        self.aEditAboutYouViewModel.callSaveUserDetailsAPI(filteredData:param)
    }
    func prepareSelectedDataToPost(){
//        [self.aEditAboutViewModel.educationalBackGroundArray?.options,self.aEditAboutViewModel.drinkAlcoholArray?.options,self.aEditAboutViewModel.smokingPreferenceArray?.options,self.aEditAboutViewModel.childrenPlanArray?.options,self.aEditAboutViewModel.religionChoiceArray?.options,self.aEditAboutViewModel.preferHeightArray?.options,self.aEditAboutViewModel.lookingForRelationshipArray?.options,self.aEditAboutViewModel.exerciseArray?.options,self.aEditAboutViewModel.partyPreferenceArray?.options,self.aEditAboutViewModel.zodiacArray?.options].forEach { data in
//            if let selectedData = data?.filter({$0.isSelected ?? false}).first {
//                self.selectedOptionData?.append(selectedData)
//            }
//        }
//        print(self.selectedOptionData as Any)
    }

    //data:MoreAboutMeData
    func updateAboutYouData(data:[AttributesData]?,index:Int){
//        switch index {
//        case 0:
//            self.aEditAboutViewModel.educationalBackGroundArray = data
//        case 1:
//            self.aEditAboutViewModel.drinkAlcoholArray = data
//        case 2:
//            self.aEditAboutViewModel.smokingPreferenceArray = data
//        case 3:
//            self.aEditAboutViewModel.childrenPlanArray = data
//        case 4:
//            self.aEditAboutViewModel.religionChoiceArray = data
//        case 5:
//            self.aEditAboutViewModel.lookingForRelationshipArray = data
//        case 6:
//            self.aEditAboutViewModel.preferHeightArray = data
//        case 7:
//            self.aEditAboutViewModel.exerciseArray = data
//        case 8:
//            self.aEditAboutViewModel.partyPreferenceArray = data
//        case 9:
//            self.aEditAboutViewModel.zodiacArray = data
//        default:
//            break
//        }
        if index < aMoreAboutMeQuestionData.count {
            self.setNextButtonUI(index: index)
            //self.skipButton.isHidden = false
        }
//        if index == aMoreAboutMeQuestionData.count - 1 {
//            
//            self.skipButton.isHidden = true
//        }
        
    }
    
    func updateInterestData(total:Int){
        self.nextButton.backgroundColor = total >= 5 ? AppColor.Punch.withAlphaComponent(1) : AppColor.Punch.withAlphaComponent(0.5)
        self.nextButton.isUserInteractionEnabled = total >= 5 ? true : false
    }

    func setNextButtonUI(index:Int){
        let subDotArray = [self.subDotView1,self.subDotView2,self.subDotView3,self.subDotView4,self.subDotView5,self.subDotView6,self.subDotView7,self.subDotView8,self.subDotView9,self.subDotView10,self.subDotView11,self.subDotView12]
        //var validate:Bool = false
        self.currentIndex = index

        switch index {
        case 0:
            self.previousButton.isHidden = true
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.next, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.educationalBackGroundArray?.options) ?? false

            [self.dotImage1,self.dotView2,self.dotView3,self.dotView4,self.dotView5,self.dotView6,self.dotView7,self.dotView8,self.dotView9,self.dotView10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotView1,self.dotImage2,self.dotImage3,self.dotImage4,self.dotImage5,self.dotImage6,self.dotImage7,self.dotImage8,self.dotImage9,self.dotImage10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }

            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage1.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage1.image = UIImage(named: "preferences1")

        case 1:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.next, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.drinkAlcoholArray?.options) ?? false

            [self.dotView1,self.dotImage2,self.dotView3,self.dotView4,self.dotView5,self.dotView6,self.dotView7,self.dotView8,self.dotView9,self.dotView10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotView2,self.dotImage3,self.dotImage4,self.dotImage5,self.dotImage6,self.dotImage7,self.dotImage8,self.dotImage9,self.dotImage10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage2.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage2.image = UIImage(named: "preferences2")

        case 2:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.next, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.smokingPreferenceArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotImage3,self.dotView4,self.dotView5,self.dotView6,self.dotView7,self.dotView8,self.dotView9,self.dotView10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotView3,self.dotImage4,self.dotImage5,self.dotImage6,self.dotImage7,self.dotImage8,self.dotImage9,self.dotImage10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage3.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage3.image = UIImage(named: "preferences3")

        case 3:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.next, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.childrenPlanArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotView3,self.dotImage4,self.dotView5,self.dotView6,self.dotView7,self.dotView8,self.dotView9,self.dotView10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotImage3,self.dotView4,self.dotImage5,self.dotImage6,self.dotImage7,self.dotImage8,self.dotImage9,self.dotImage10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage4.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage4.image = UIImage(named: "preferences4")

        case 4:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.next, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.religionChoiceArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotView3,self.dotView4,self.dotImage5,self.dotView6,self.dotView7,self.dotView8,self.dotView9,self.dotView10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotImage3,self.dotImage4,self.dotView5,self.dotImage6,self.dotImage7,self.dotImage8,self.dotImage9,self.dotImage10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage5.loadImage(with: URL(string: imgUrl))
            }
            
            //self.dotImage5.image = UIImage(named: "preferences5")

        case 5:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.next, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.lookingForRelationshipArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotView3,self.dotView4,self.dotView5,self.dotImage6,self.dotView7,self.dotView8,self.dotView9,self.dotView10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotImage3,self.dotImage4,self.dotImage5,self.dotView6,self.dotImage7,self.dotImage8,self.dotImage9,self.dotImage10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage6.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage6.image = UIImage(named: "preferences6")

        case 6:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.next, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.preferHeightArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotView3,self.dotView4,self.dotView5,self.dotView6,self.dotImage7,self.dotView8,self.dotView9,self.dotView10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotImage3,self.dotImage4,self.dotImage5,self.dotImage6,self.dotView7,self.dotImage8,self.dotImage9,self.dotImage10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage7.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage7.image = UIImage(named: "preferences7")

        case 7:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.next, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.exerciseArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotView3,self.dotView4,self.dotView5,self.dotView6,self.dotView7,self.dotImage8,self.dotView9,self.dotView10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotImage3,self.dotImage4,self.dotImage5,self.dotImage6,self.dotImage7,self.dotView8,self.dotImage9,self.dotImage10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage8.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage8.image = UIImage(named: "preferences8")

        case 8:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.next, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.partyPreferenceArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotView3,self.dotView4,self.dotView5,self.dotView6,self.dotView7,self.dotView8,self.dotImage9,self.dotView10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotImage3,self.dotImage4,self.dotImage5,self.dotImage6,self.dotImage7,self.dotImage8,self.dotView9,self.dotImage10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage9.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage9.image = UIImage(named: "preferences9")

        case 9:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.finish, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.zodiacArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotView3,self.dotView4,self.dotView5,self.dotView6,self.dotView7,self.dotView8,self.dotView9,self.dotImage10,self.dotView11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotImage3,self.dotImage4,self.dotImage5,self.dotImage6,self.dotImage7,self.dotImage8,self.dotImage9,self.dotView10,self.dotImage11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage10.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage10.image = UIImage(named: "preferences10")
            
        case 10:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.finish, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.zodiacArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotView3,self.dotView4,self.dotView5,self.dotView6,self.dotView7,self.dotView8,self.dotView9,self.dotView10,self.dotImage11,self.dotView12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotImage3,self.dotImage4,self.dotImage5,self.dotImage6,self.dotImage7,self.dotImage8,self.dotImage9,self.dotImage10,self.dotView11,self.dotImage12].forEach{ view in
                view?.isHidden = true
            }
            
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage11.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage11.image = UIImage(named: "preferences10")
            
        case 11:
            self.previousButton.isHidden = fromEditProfile ?? false
            self.nextButton.setTitle(fromEditProfile ?? false ? Constants.AlertButtons.continueButton : Constants.AlertButtons.finish, for: .normal)
//            validate = self.aEditAboutViewModel.validation(data:self.aEditAboutViewModel.zodiacArray?.options) ?? false

            [self.dotView1,self.dotView2,self.dotView3,self.dotView4,self.dotView5,self.dotView6,self.dotView7,self.dotView8,self.dotView9,self.dotView10,self.dotView11,self.dotImage12].forEach{ view in
                view?.isHidden = false
            }

            [self.dotImage1,self.dotImage2,self.dotImage3,self.dotImage4,self.dotImage5,self.dotImage6,self.dotImage7,self.dotImage8,self.dotImage9,self.dotImage10,self.dotImage11,self.dotView12].forEach{ view in
                view?.isHidden = true
            }
            
            if self.aMoreAboutMeQuestionData[index].photo != nil {
                let imgUrl = ApiName.imgBaseURL + (self.aMoreAboutMeQuestionData[index].photo ?? "")
                self.dotImage12.loadImage(with: URL(string: imgUrl))
            }
            //self.dotImage12.image = UIImage(named: "preferences10")

        default:
            break
        }
        
        if self.selectedIndex != nil {
            if self.selectedIndex ?? 0 < index {
                self.previousButton.isHidden = false
                self.nextButton.setTitle(Constants.AlertButtons.next, for: .normal)
            }
        }
        
        
        
        
        //validate
        self.nextButton.backgroundColor = self.selectedCountForButtons(index: index) ? AppColor.Punch.withAlphaComponent(1) : AppColor.Punch.withAlphaComponent(0.5)
        self.nextButton.isUserInteractionEnabled = self.selectedCountForButtons(index: index) ? true : false

        for (index,item) in subDotArray.enumerated(){
            if index < self.currentIndex ?? 0 {
                item?.backgroundColor = AppColor.Punch
            }else if index > self.currentIndex ?? 0 {
                item?.backgroundColor = AppColor.Iron
            }
        }
    }
    
    func selectedCountForButtons(index:Int) -> Bool {
        guard aMoreAboutMeQuestionData[index].selection_type == Constants.QuestionType.radio, let options = aMoreAboutMeQuestionData[index].aOptions else {
               return false
            }
            //print("Count......",options.filter { $0.isSelected == true }.count)
           if (options.filter { $0.isSelected == true }.count > 0)
            {
               return true
            } else {
               return false
            }
        //return false
    }

    // Your existing scroll functions
    func scrollToNextCell() {
        // Cancel any ongoing debounce timer
        scrollDebounceTimer?.invalidate()

        // Start a new debounce timer
        scrollDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            DispatchQueue.main.async {
                let currentIndex = max(0, self.aboutYouCollectionView.indexPathsForVisibleItems.first?.item ?? 0)
                let nextIndex = min(currentIndex + 1, self.aMoreAboutMeQuestionData.count - 1) //9
                let nextIndexPath = IndexPath(item: nextIndex, section: 0)
                self.aboutYouCollectionView.scrollToItem(at: nextIndexPath, at: .centeredHorizontally, animated: true)
                self.setNextButtonUI(index: nextIndex)
            }
        }
    }

    func scrollToPreviousCell() {
        // Cancel any ongoing debounce timer
        scrollDebounceTimer?.invalidate()

        // Start a new debounce timer
        scrollDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            DispatchQueue.main.async {
                let currentIndex = max(0, self.aboutYouCollectionView.indexPathsForVisibleItems.first?.item ?? 0)
                let previousIndex = max(currentIndex - 1, 0)
                let previousIndexPath = IndexPath(item: previousIndex, section: 0)
                self.aboutYouCollectionView.scrollToItem(at: previousIndexPath, at: .centeredHorizontally, animated: true)
                self.setNextButtonUI(index: previousIndex)
            }
        }
    }

    @IBAction func skipPageButtonTapped(_ sender: UIButton) {
        if (self.currentIndex == self.aMoreAboutMeQuestionData.count - 1) || (self.aMoreAboutMeQuestionData.count == 0) {
            self.navigationController?.popViewController(animated: true)
        }else{
            self.scrollToNextCell()
        }
    }
    
    func getSelectedInterestIds(from attributesData: AttributesData) -> [Int] {
        // Safely unwrap the options array
        guard let options = attributesData.aOptions else { return [] }
        
        // Filter for options where isSelected is true and extract their ids
        let selectedIds = options.compactMap { option -> Int? in
            if option.isSelected == true {
                return option.id
            }
            return nil
        }
        
        return selectedIds
    }
}

extension EditAboutYouViewController: UICollectionViewDelegate, UICollectionViewDataSource,UICollectionViewDelegateFlowLayout{

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: UIScreen.main.bounds.width - 40, height:self.aboutYouCollectionView.frame.height)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        //return 10
        return aMoreAboutMeQuestionData.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AboutYouCollectionViewCell.identifier, for: indexPath) as? AboutYouCollectionViewCell {
//            switch indexPath.row {
//            case 0:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.educationalBackGroundArray)
//            case 1:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.drinkAlcoholArray)
//            case 2:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.smokingPreferenceArray)
//            case 3:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.childrenPlanArray)
//            case 4:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.religionChoiceArray)
//            case 5:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.lookingForRelationshipArray)
//            case 6:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.preferHeightArray)
//            case 7:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.exerciseArray)
//            case 8:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.partyPreferenceArray)
//            case 9:
//                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aEditAboutViewModel.zodiacArray)
//            default:
//                break
//            }
            
            if isInterest == false {
                cell.setEditProfileMoreAboutYouUI(index: indexPath.row, data1:self.aMoreAboutMeQuestionData)
                cell.onEditProfileSelectionCallBack = { [weak self] (data,index) in
                    self?.aMoreAboutMeQuestionData = data ?? []
                    self?.updateAboutYouData(data: data, index: index)
                }
            } else {
                cell.setUIIntrest(index: 0,data1: self.aMoreAboutMeQuestionData)
                cell.onInterestEditProfileSelectionCallBack = { [weak self] (data,index,total) in
                    self?.aMoreAboutMeQuestionData = data ?? []
                    self?.updateInterestData(total: total)
                }
            }
            return cell
        }
        return UICollectionViewCell()
    }
}
