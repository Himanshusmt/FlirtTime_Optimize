//
//  AboutYouCollectionViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 08/05/24.
//

import UIKit

class AboutYouCollectionViewCell: UICollectionViewCell {

    static let identifier = "AboutYouCollectionViewCell"

    @IBOutlet weak var headerLabelOne: UILabel!
    @IBOutlet weak var headerLabelTwo: UILabel!
    @IBOutlet weak var aboutYouQuestionLabel: UILabel!
    @IBOutlet weak var aboutYouChoicesCollectionView: UICollectionView!
    @IBOutlet weak var headerlabelWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var aboutYouChoicesTableView: UITableView!
    @IBOutlet weak var CellWidthConstraint: NSLayoutConstraint!
    
    var genQuestionArray:[AttributesData] = []

    var onSelectionCallBack:(([AttributesData],Int)->())?
    //var onSelectionCallBack:(([QuestionData],UserInterestData?,Int)->())?
    //  var onEditProfileSelectionCallBack:((MoreAboutMeData?,Int)->())?
    var onEditProfileSelectionCallBack:(([AttributesData]?,Int)->())?
    var onInterestEditProfileSelectionCallBack:(([AttributesData]?,Int,Int)->())?
    var index:Int = 0
    //var aboutYouGeneralDataArray:[QuestionData]? = []
    //var selectedOptionDataArray:[GeneralOption]? = []
    //var interestDataArray:UserInterestData?
    var aboutYouGeneralDataArray:[AttributesData]? = []
    var selectedOptionDataArray:[attOptions]? = []
    var interestDataArray:UserInterestData?
    var aUserInfo: UserDetailsData? = nil

    //    From EditProfileScreen
    //var editProfileMoreAboutYouData:MoreAboutMeData?
    var editProfileMoreAboutYouData:[attOptions]?
    var fromEditProfileScreen:Bool? = false

    override func awakeFromNib() {
        super.awakeFromNib()
        self.registerCell()
    }

    func registerCell(){
        self.headerlabelWidthConstraint.constant  = UIScreen.main.bounds.width - 40
        self.CellWidthConstraint.constant  = UIScreen.main.bounds.width - 40
        self.aboutYouChoicesCollectionView.register(UINib(nibName: InterestCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: InterestCollectionViewCell.identifier)
        self.aboutYouChoicesCollectionView.delegate = self
        self.aboutYouChoicesCollectionView.dataSource = self

        self.aboutYouChoicesTableView.register(UINib(nibName: PreferencesTableViewCell.identifier, bundle: nil), forCellReuseIdentifier: PreferencesTableViewCell.identifier)
//        self.aboutYouChoicesTableView.delegate = self
//        self.aboutYouChoicesTableView.dataSource = self
        
        
        self.aboutYouChoicesTableView.showsHorizontalScrollIndicator = false
        self.aboutYouChoicesTableView.showsVerticalScrollIndicator = false
        
        self.aboutYouChoicesTableView.register(UINib(nibName: HeightPreferenceTableViewCell.identifier, bundle: nil), forCellReuseIdentifier: HeightPreferenceTableViewCell.identifier)
        self.aboutYouChoicesTableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 60, right: 0)
        self.aboutYouChoicesTableView.delegate = self
        self.aboutYouChoicesTableView.dataSource = self
    }

    //    Case: To set AboutYou UI
    // QuestionData
//    func setUI(index:Int,data1:[AttributesData]? = nil,data2:UserInterestData? = nil){
//        self.index = index
//        self.selectedOptionDataArray = data1?[index].aOptions
//        //self.aboutYouGeneralDataArray = data1
//        //self.interestDataArray = data2
//        self.headerLabelOne.text = data1 != nil ? data1?[index].title : data2?.title
//        self.headerLabelTwo.text = data2?.generalText
//        self.aboutYouQuestionLabel.text = data1 != nil ? data1?[index].question : data2?.question
//        self.aboutYouChoicesCollectionView.isHidden = self.index == 3 ? false : true
//        self.aboutYouChoicesTableView.isHidden = self.index == 0 || self.index == 1 || self.index == 2 ? false : true
//        DispatchQueue.main.async {
//            self.aboutYouChoicesTableView.reloadData()
//            self.aboutYouChoicesCollectionView.reloadData()
//        }
//    }
    
    func setUI(index:Int,data1:[AttributesData]? = nil,data2:UserInterestData? = nil, userInfo: UserDetailsData? = nil){
        self.index = index
        
        self.genQuestionArray = data1 ?? []
        
        self.selectedOptionDataArray = data1?[index].aOptions
        //self.aboutYouGeneralDataArray = data1
        //self.interestDataArray = data2
        self.headerLabelOne.text = data1 != nil ? data1?[index].title : data2?.title
        //self.headerLabelTwo.text = " " //data2?.generalText
        if index == 4 {
            self.headerLabelTwo.isHidden = false
            self.headerLabelTwo.text = "You can choose minimum 5"
        } else {
            self.headerLabelTwo.isHidden = true
            self.headerLabelTwo.text = ""
        }
        self.aboutYouQuestionLabel.text = data1 != nil ? data1?[index].question : data2?.question
        
        if data1?[index].selection_type == Constants.QuestionType.radio.rawValue {
            self.aboutYouChoicesCollectionView.isHidden = true
            self.aboutYouChoicesTableView.isHidden = false
            DispatchQueue.main.async {
                self.aboutYouChoicesTableView.reloadData()
            }
        } else {
            self.aboutYouChoicesCollectionView.isHidden = false
            self.aboutYouChoicesTableView.isHidden = true
            DispatchQueue.main.async {
                self.aboutYouChoicesCollectionView.reloadData()
            }
        }
        //self.aboutYouChoicesCollectionView.isHidden = self.index == 3 ? false : true
        //self.aboutYouChoicesTableView.isHidden = self.index == 0 || self.index == 1 || self.index == 2 ? false : true
        
    }

    //    Case: To set ProfileMoreAboutYou UI
    //data1:MoreAboutMeData?
    func setEditProfileMoreAboutYouUI(index:Int,data1:[AttributesData]?,data2:AboutYouHeaderModel? = nil,showInterestCollection:Bool? = false, userInfo: UserDetailsData? = nil){
        self.genQuestionArray = data1 ?? []
        self.index = index
        //self.editProfileMoreAboutYouData = data1?[index].aOptions
        self.selectedOptionDataArray = data1?[index].aOptions
        self.headerLabelOne.text = data1?[index].question
        self.headerLabelTwo.isHidden = true
        self.aboutYouQuestionLabel.text = ""
        self.aboutYouChoicesCollectionView.isHidden = !(showInterestCollection ?? false)
        self.aboutYouChoicesTableView.isHidden = showInterestCollection ?? false
        self.fromEditProfileScreen = true
        DispatchQueue.main.async {
            self.aboutYouChoicesTableView.reloadData()
            self.aboutYouChoicesCollectionView.reloadData()
        }
    }
    
    func setUIIntrest(index:Int,data1:[AttributesData]? = nil,data2:UserInterestData? = nil, userInfo: UserDetailsData? = nil){
        self.index = index
        
        self.genQuestionArray = data1 ?? []
        
        self.selectedOptionDataArray = data1?[index].aOptions
        //self.aboutYouGeneralDataArray = data1
        //self.interestDataArray = data2
        self.headerLabelOne.text = data1 != nil ? data1?[index].title : data2?.title
        //self.headerLabelTwo.text = " " //data2?.generalText
        
        self.headerLabelTwo.isHidden = false
        self.headerLabelTwo.text = "You can choose minimum 5"
        
        self.fromEditProfileScreen = true
        
        self.aboutYouQuestionLabel.text = data1 != nil ? data1?[index].question : data2?.question
        
        if data1?[index].selection_type == Constants.QuestionType.radio.rawValue {
            self.aboutYouChoicesCollectionView.isHidden = true
            self.aboutYouChoicesTableView.isHidden = false
            DispatchQueue.main.async {
                self.aboutYouChoicesTableView.reloadData()
            }
        } else {
            self.aboutYouChoicesCollectionView.isHidden = false
            self.aboutYouChoicesTableView.isHidden = true
            DispatchQueue.main.async {
                self.aboutYouChoicesCollectionView.reloadData()
            }
        }
        //self.aboutYouChoicesCollectionView.isHidden = self.index == 3 ? false : true
        //self.aboutYouChoicesTableView.isHidden = self.index == 0 || self.index == 1 || self.index == 2 ? false : true
        
    }
}

extension AboutYouCollectionViewCell: UICollectionViewDelegate, UICollectionViewDataSource,UICollectionViewDelegateFlowLayout{
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.selectedOptionDataArray?.count ?? 0
        //self.interestDataArray?.options?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: InterestCollectionViewCell.identifier, for: indexPath) as? InterestCollectionViewCell {
            cell.setUI(data: self.selectedOptionDataArray?[indexPath.row], userInfo: aUserInfo)
            cell.isExclusiveTouch = true
            return cell
            
            //cell.setUI(data: self.interestDataArray?.options?[indexPath.row])
        }
        return UICollectionViewCell()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        //interestDataArray?.options?
        //let newSelectedOptionData:[attOptions]?
        
        
        //        var arrSelIndex = self.genQuestionArray[0].aOptions?.filter{ $0.isSelected == true }
        //        print("arr.....",arrSelIndex?.count ?? 0)
        //        print("arr.....",arrSelIndex ?? [])
        var totalSelCount  = 0
        self.selectedOptionDataArray = self.selectedOptionDataArray?.enumerated().map({ (index,data) in
            let updatedData = data
            if updatedData.isSelected == true {
                totalSelCount = totalSelCount + 1
            }
            return updatedData
            
        })
        
        if totalSelCount < 10 {
            
            self.selectedOptionDataArray = self.selectedOptionDataArray?.enumerated().map({ (index,data) in
                var updatedData = data
                if indexPath.row == index {
                    if updatedData.isSelected == nil {
                        updatedData.isSelected = true
                    } else if updatedData.isSelected == true {
                        updatedData.isSelected = false
                    } else if updatedData.isSelected == false {
                        updatedData.isSelected = true
                    }
                    //                updatedData.isSelected = updatedData.isSelected == nil ? true : !(updatedData.isSelected ?? false)
                }else{
                    updatedData.isSelected = updatedData.isSelected == nil ? false : updatedData.isSelected ?? false
                }
                
                return updatedData
            })
            
            //self.interestDataArray?.options
            //self.selectedOptionDataArray = newSelectedOptionData
            if self.fromEditProfileScreen == true {
                //                self.genQuestionArray[index].aOptions = self.selectedOptionDataArray
                //                guard let action = self.onEditProfileSelectionCallBack else { return }
                //        //        action(self.aboutYouGeneralDataArray ?? [],self.interestDataArray!,index)
                //                action(self.genQuestionArray,index)
                //                DispatchQueue.main.async {
                //                    self.aboutYouChoicesCollectionView.reloadItems(at: [indexPath])
                //                }
                
                self.genQuestionArray[index].aOptions = self.selectedOptionDataArray
                let arrSelIndex = self.genQuestionArray[0].aOptions?.filter{ $0.isSelected == true }
                print("arr.....",arrSelIndex?.count ?? 0)
                print("arr.....",arrSelIndex ?? [])
                guard let action = self.onInterestEditProfileSelectionCallBack else { return }
                //        action(self.aboutYouGeneralDataArray ?? [],self.interestDataArray!,index)
                action(self.genQuestionArray,index,arrSelIndex?.count ?? 0)
                DispatchQueue.main.async {
                    self.aboutYouChoicesCollectionView.reloadItems(at: [indexPath])
                }
                
            } else {
                // ✅ Save selected options back
                self.genQuestionArray[index].aOptions = self.selectedOptionDataArray
                
                // ✅ Count how many options are selected
                let selectedCount = self.selectedOptionDataArray?.filter { $0.isSelected == true }.count ?? 0
                
                // ✅ Notify parent VC that data changed
                guard let action = self.onSelectionCallBack else { return }
                action(self.genQuestionArray, index)
                
                DispatchQueue.main.async {
                    self.aboutYouChoicesCollectionView.reloadItems(at: [indexPath])
                }
                
                // ✅ Optional: if this is the "interest" alias, send count to VC
                if self.genQuestionArray[index].alias == "interest" {
                    self.onInterestEditProfileSelectionCallBack?(self.genQuestionArray, index, selectedCount)
                }
            }
        } else {
            
            self.selectedOptionDataArray = self.selectedOptionDataArray?.enumerated().map({ (index,data) in
                var updatedData = data
                if indexPath.row == index {
                    if updatedData.isSelected == nil {
                        updatedData.isSelected = false
                    } else if updatedData.isSelected == true {
                        updatedData.isSelected = false
                    }
                    //                updatedData.isSelected = updatedData.isSelected == nil ? true : !(updatedData.isSelected ?? false)
                }else{
                    updatedData.isSelected = updatedData.isSelected == nil ? false : updatedData.isSelected ?? false
                }
                
                return updatedData
            })
            
            //self.interestDataArray?.options
            //self.selectedOptionDataArray = newSelectedOptionData
            if self.fromEditProfileScreen == true {
                //                self.genQuestionArray[index].aOptions = self.selectedOptionDataArray
                //                guard let action = self.onEditProfileSelectionCallBack else { return }
                //        //        action(self.aboutYouGeneralDataArray ?? [],self.interestDataArray!,index)
                //                action(self.genQuestionArray,index)
                //                DispatchQueue.main.async {
                //                    self.aboutYouChoicesCollectionView.reloadItems(at: [indexPath])
                //                }
                
                self.genQuestionArray[index].aOptions = self.selectedOptionDataArray
                let arrSelIndex = self.genQuestionArray[0].aOptions?.filter{ $0.isSelected == true }
                print("arr.....",arrSelIndex?.count ?? 0)
                print("arr.....",arrSelIndex ?? [])
                guard let action = self.onInterestEditProfileSelectionCallBack else { return }
                //        action(self.aboutYouGeneralDataArray ?? [],self.interestDataArray!,index)
                action(self.genQuestionArray,index,arrSelIndex?.count ?? 0)
                DispatchQueue.main.async {
                    self.aboutYouChoicesCollectionView.reloadItems(at: [indexPath])
                }
                
            } else {
                self.genQuestionArray[index].aOptions = self.selectedOptionDataArray
                guard let action = self.onSelectionCallBack else { return }
                //        action(self.aboutYouGeneralDataArray ?? [],self.interestDataArray!,index)
                action(self.genQuestionArray,index)
                DispatchQueue.main.async {
                    self.aboutYouChoicesCollectionView.reloadItems(at: [indexPath])
                }
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = UIScreen.main.bounds.width - 55
        let itemWidth = width / 2
        return CGSize(width: itemWidth, height: 60)
    }
}

extension AboutYouCollectionViewCell: UITableViewDelegate, UITableViewDataSource{
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.selectedOptionDataArray?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let options = self.selectedOptionDataArray,
           indexPath.row < options.count,
           let cell = tableView.dequeueReusableCell(withIdentifier: PreferencesTableViewCell.identifier,
                                                    for: indexPath) as? PreferencesTableViewCell {
            
            cell.setAboutYouUI(data1: options[indexPath.row], userInfo: aUserInfo)
            return cell
        }
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.selectedOptionDataArray = self.selectedOptionDataArray?.enumerated().map({ (index,data) in
            var updatedData = data
            updatedData.isSelected = indexPath.row == index ? true : false
            return updatedData
        })
        
        if self.fromEditProfileScreen == true {
            
            self.genQuestionArray[index].aOptions = self.selectedOptionDataArray
            //            self.aboutYouGeneralDataArray?[index].aOptions = self.selectedOptionDataArray
            guard let action = self.onEditProfileSelectionCallBack else { return }
            //            action(self.aboutYouGeneralDataArray ?? [],self.interestDataArray,index)
            action(self.genQuestionArray,index).self
            
            DispatchQueue.main.async {
                self.aboutYouChoicesTableView.reloadData()
            }
            
        } else {
            
            self.genQuestionArray[index].aOptions = self.selectedOptionDataArray
            //            self.aboutYouGeneralDataArray?[index].aOptions = self.selectedOptionDataArray
            guard let action = self.onSelectionCallBack else { return }
            //            action(self.aboutYouGeneralDataArray ?? [],self.interestDataArray,index)
            action(self.genQuestionArray,index).self
            
            DispatchQueue.main.async {
                self.aboutYouChoicesTableView.reloadData()
            }
        }
    }
}
