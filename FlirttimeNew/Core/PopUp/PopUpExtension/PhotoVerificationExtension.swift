//
//  PhotoVerificationPopUpExtension.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 11/05/24.
//

import Foundation
import UIKit

extension FlirtCustomPopUp{

    func uploadPhoto(){
        self.button2.backgroundColor = AppColor.Punch
        self.button2.isUserInteractionEnabled = true
        self.picUploadingView.isHidden = false
        self.uploadingImage.image = self.userUploadingImage
        // Reset progress layer's stroke end value to 0
        uploadingProgressView.setProgressWithAnimation(duration: 0, value: 0)
        uploadingProgressView.setProgressColor = AppColor.Punch
        uploadingProgressView.setTrackColor = AppColor.Iron
        uploadingProgressView.setProgressLineWidth = 4.5
        uploadingProgressView.setTrackLineWidth = 4.5
        progressAnimationWorkItem?.cancel()
        startUploadProgress()
    }

    //    Progress stops short of 100% until the caller reports the real result
    func startUploadProgress() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.popUpType == .pictureUploading else { return }
            self.uploadingProgressView.setProgressWithAnimation(duration: 3.0, value: 0.9)
        }
    }

    //    Upload succeeded: finish the progress, then report success and close
    func completeUpload() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.popUpType == .pictureUploading else { return }
            self.uploadingProgressView.setProgressWithAnimation(duration: 0.3, value: 1.0)
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.callBackAction?("")
                self.genericCallBack?(.pictureUploading)
                self.hide()
            }
            self.progressAnimationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
        }
    }

    //    Upload failed: switch to the failed view with a Retake button
    func failUpload(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.popUpType == .pictureUploading else { return }
            self.progressAnimationWorkItem?.cancel()
            self.showuploadingFailedView(message)
        }
    }

    //    For user image verification
    func showuploadingFailedView(_ text: String = "") {
        self.textLabel.numberOfLines = 0
        self.textLabel.text = text
        self.picUploadingView.isHidden = true
        self.picUploadFailedView.isHidden = false
        self.popUpType = .picUploadingFailed
        self.button2.setTitle(Constants.AlertButtons.retake, for: .normal)
        self.button2.isUserInteractionEnabled = true
        self.button2.backgroundColor = AppColor.Punch
    }

    //    Dismiss animation during user image verification
    func dismissAnimation() {
        // Cancel the progress animation work item when dismissing the view
        self.progressAnimationWorkItem?.cancel()
    }
}
