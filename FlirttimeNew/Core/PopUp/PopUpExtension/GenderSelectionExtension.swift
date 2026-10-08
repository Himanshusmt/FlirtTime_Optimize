//
//  GenderSelectionExtension.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 11/05/24.
//

import Foundation
import UIKit


extension FlirtCustomPopUp {

    func setMaleSelectionUI(){
        self.maleImageView.layer.borderWidth = 2
        self.maleImageView.addShadow(color: AppColor.BlueRibbon, opacity: 1.0, offset: CGSize(width: 0, height: 1.0))
        [self.femaleImageView,self.otherImageView].forEach { imageView in
            imageView?.layer.borderWidth = 1
            imageView?.addShadow(color: AppColor.AppWhite, opacity: 0, offset: CGSize(width: 0, height: 0.0))
        }
        
        self.selectedGender = self.genderOptions[0].title
        self.selectedGenderID = self.genderOptions[0].id
        //"Male"
        self.setSaveButtonUI()
    }

    func setFemaleSelectionUI(){
        self.femaleImageView.layer.borderWidth = 2
        self.femaleImageView.addShadow(color: AppColor.Carnation, opacity: 1.0, offset: CGSize(width: 0, height: 1.0))
        [self.maleImageView,self.otherImageView].forEach { imageView in
            imageView?.layer.borderWidth = 1
            imageView?.addShadow(color: AppColor.AppWhite, opacity: 0, offset: CGSize(width: 0, height: 0.0))
        }
        
        self.selectedGender = self.genderOptions[1].title
        self.selectedGenderID = self.genderOptions[1].id
        //self.selectedGender = "Female"
        self.setSaveButtonUI()
    }

    func setOtherSelectionUI(){
        self.otherImageView.layer.borderWidth = 2
        self.otherImageView.addShadow(color: AppColor.ElectricViolet, opacity: 1.0, offset: CGSize(width: 0, height: 1.0))
        [self.femaleImageView,self.maleImageView].forEach { imageView in
            imageView?.layer.borderWidth = 1
            imageView?.addShadow(color: AppColor.AppWhite, opacity: 0, offset: CGSize(width: 0, height: 0.0))
        }
        
        self.selectedGender = self.genderOptions[2].title
        self.selectedGenderID = self.genderOptions[2].id
        //self.selectedGender = "Other"
        self.setSaveButtonUI()
    }
}
