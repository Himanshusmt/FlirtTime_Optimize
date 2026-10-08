//
//  CustomAlertVW.swift
//  FlirtTime
//
//  Created by Smt MacMini on 27/12/24.
//

import UIKit

class CustomAlertVW: UIView {
    
    @IBOutlet weak var lblTitle:UILabel!
    @IBOutlet weak var lblMSG:UILabel!
    @IBOutlet weak var progressView:UIProgressView!
    @IBOutlet weak var imgVW:UIImageView!
    @IBOutlet weak var vwStack:UIView!
    
    var progressCount = 1.0
    
    var timer: Timer?
    var callCount = 0
    let totalCalls = 16
    let duration: TimeInterval = 2.0
    var callBackAction:(()->Void)?

    
    override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }
    
    private func commonInit() {
            // Load the .xib file
            let nib = UINib(nibName: "CustomAlertVW", bundle: nil)
            guard let view = nib.instantiate(withOwner: self, options: nil).first as? UIView else { return }
            view.frame = self.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
            
        }
    
    func setView(Title:String, Msg:String, isSuccess:Bool) {
        vwStack.isHidden = false
        startTimer()
        lblTitle.text = Title
        lblMSG.text = Msg
        
        if isSuccess == true {
            progressView.tintColor = AppColor.AlertBottomSuccess
            imgVW.image = UIImage(named: "alert_Success")
        } else {
            progressView.tintColor = AppColor.AlertBottomFailure
            imgVW.image = UIImage(named: "alert_failure")
        }
        
        
    }
    

    func startTimer() {
            // Calculate the interval between calls
            let interval = duration / Double(totalCalls)

            // Schedule the timer
            timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        }
    
    @objc func timerFired() {
            if callCount < totalCalls {
                callCount += 1
                setProgressBar()
            } else {
                // Stop the timer once the total calls have been made
                timer?.invalidate()
                timer = nil
                print("Timer completed")
                vwStack.isHidden = true
                progressCount = 1.0
                guard let action = self.callBackAction else { return }
                action()
                self.removeFromSuperview()
            }
        }
    
    func setProgressBar() {
        progressCount = progressCount - 0.0625
        self.progressView.setProgress(Float(progressCount), animated: true)
    }

}
