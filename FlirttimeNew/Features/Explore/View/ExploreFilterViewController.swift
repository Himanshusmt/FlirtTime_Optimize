//
//  ExploreFilterViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 12/06/24.
//

import UIKit

class ExploreFilterViewController: BaseViewController,Instantiable,UIGestureRecognizerDelegate {

    @IBOutlet weak var mainView: UIView!
    @IBOutlet weak var onlineNowSwitch: UISwitch!
    @IBOutlet weak var verifiedSwitch: UISwitch!
    @IBOutlet weak var femaleImageView: UIView!
    @IBOutlet weak var maleImageView: UIView!
    @IBOutlet weak var otherImageView: UIView!
    @IBOutlet weak var ageRangeLabel: UILabel!
    @IBOutlet weak var customSlider: CustomSlider!
    @IBOutlet weak var rangeSliderCustom: RangesSeekSlider!
    
    private var gender:String?
    private var isOnline:String?
    private var minAge:String?
    private var maxAge:String?
    private var isVerified:String?
    private var distance:String?
    
    var filterAction:((FilterModel?)->())?
    var clearFilterAction:()->() = {}
    
    static var storyboardName: StringConvertible {
        return StoryboardName.moments
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUI()
        self.setupSlider()
        self.setRangeSliderUI()
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(sliderTapped(_:)))
            customSlider.addGestureRecognizer(tapGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.checkHideCustomButton(hide: false)
        self.loadPreviousFilterValues()
    }
    
    @objc private func sliderTapped(_ gesture: UITapGestureRecognizer) {
        let slider = gesture.view as! UISlider
        let location = gesture.location(in: slider)
        let percentage = location.x / slider.bounds.width
        let newValue = Float(percentage) * (slider.maximumValue - slider.minimumValue) + slider.minimumValue
        
        slider.setValue(newValue, animated: true)
        slider.sendActions(for: .valueChanged) // 👈 make sure sliderValueChanged gets called
    }
    
    private func loadPreviousFilterValues() {
        guard let filter = UserDataManager.shared.filterDataModel else { return }

        // Restore gender UI
        if let gender = filter.gender {
            switch gender {
            case "1":
                setMaleSelectionUI()
            case "2":
                setFemaleSelectionUI()
            case "3":
                setOtherSelectionUI()
            default:
                break
            }
        }

        // Restore age range
        if let min = filter.minAge, let max = filter.maxAge,
           let minVal = Float(min), let maxVal = Float(max) {
            rangeSliderCustom.selectedMinValue = CGFloat(minVal)
            rangeSliderCustom.selectedMaxValue = CGFloat(maxVal)
            ageRangeLabel.text = "\(Int(minVal))-\(Int(maxVal))"
            self.minAge = min
            self.maxAge = max
        }

        // Restore distance
        if let distance = filter.distance, let distValue = Float(distance) {
            customSlider.value = distValue
            customSlider.thumbLabel.text = "\(Int(distValue))Miles"
            customSlider.updateLabelPosition()
            self.distance = distance
        }

        // Restore switches
        if let isVerified = filter.isVerified {
            verifiedSwitch.isOn = isVerified == "1"
            self.isVerified = isVerified
        }

        if let isOnline = filter.isOnline {
            onlineNowSwitch.isOn = isOnline == "1"
            self.isOnline = isOnline
        }
    }


    func setUI(){
        self.mainView.setRoundedManualTopCorners(cornerRadius:20)
        self.view.backgroundColor = .black.withAlphaComponent(0.4)
//        self.setFemaleSelectionUI()
        self.setSwitchButtonUI()
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self // Set the delegate
        self.view.addGestureRecognizer(tapGesture)
    }

// MARK: RangeSliderUI

    func setRangeSliderUI(){
        // custom number formatter range slider
        rangeSliderCustom.delegate = self
        rangeSliderCustom.minValue = 18.0
        rangeSliderCustom.maxValue = 70.0
        rangeSliderCustom.selectedMinValue = 18.0
        rangeSliderCustom.selectedMaxValue = 35.0
        self.minAge = "\(Int(rangeSliderCustom.selectedMinValue))"
        self.maxAge = "\(Int(rangeSliderCustom.selectedMaxValue))"
        if let thumbImage = UIImage(named: "sliderThumbIcon") {
            let size = CGSize(width: 20, height: 20) // increase size here
            UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
            thumbImage.draw(in: CGRect(origin: .zero, size: size))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            rangeSliderCustom.handleImage = resizedImage
        }
        rangeSliderCustom.selectedHandleDiameterMultiplier = 1.2
        rangeSliderCustom.colorBetweenHandles = AppColor.Punch
        rangeSliderCustom.lineHeight = 9.5
        rangeSliderCustom.maxLabelFont = UIFont.fredoka(.regular,size:11)
        rangeSliderCustom.minLabelFont = UIFont.fredoka(.regular,size:11)
        rangeSliderCustom.maxLabelColor = AppColor.AppWhite
        rangeSliderCustom.minLabelColor = AppColor.AppWhite
        rangeSliderCustom.minDistance = 4
        rangeSliderCustom.step = 2
        self.ageRangeLabel.text = "\(Int(rangeSliderCustom.selectedMinValue))-\(Int(rangeSliderCustom.selectedMaxValue))"
    }

    // MARK: SingleThumbSliderUI

    private func setupSlider() {
        customSlider.isContinuous = true
        customSlider.minimumValue = 0
        customSlider.maximumValue = 200
        customSlider.value = 50
        self.distance = "50"
        customSlider.thumbLabel.text = "\(Int(customSlider.value))Miles"
        customSlider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
    }

    @objc func sliderValueChanged(_ sender: CustomSlider) {
        let sliderValue = Int(sender.value)
        self.distance = "\(sliderValue)"
        sender.thumbLabel.text = "\(sliderValue)Miles"
        sender.thumbLabel.sizeToFit()
        sender.thumbLabel.frame.size = CGSize(width: sender.thumbLabel.frame.width + 10, height: sender.thumbLabel.frame.height + 2)
        sender.updateLabelPosition()
    }

    private func setSwitchButtonUI(){
        [onlineNowSwitch,verifiedSwitch].forEach { swtich in
            swtich.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }

        [onlineNowSwitch,verifiedSwitch].forEach { swtich in
            swtich.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        }
        self.isVerified = "1"
        self.isOnline = "1"
    }

    @objc func switchValueChanged(_ sender: UISwitch) {

        if sender == self.verifiedSwitch {
            if sender.isOn {
                self.isVerified = "1"
                print("Switch is ON")
            } else {
                self.isVerified = "0"
                print("Switch is OFF")
            }
        }else if sender == self.onlineNowSwitch{
            if sender.isOn {
                self.isOnline = "1"
                print("Switch is ON")
            } else {
                self.isOnline = "0"
                print("Switch is OFF")
            }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view, view.isDescendant(of: mainView) {
            return false
        }
        return true
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        self.dismiss(animated: true)
    }

//    @objc func handleSwipe(_ gesture: UITapGestureRecognizer) {
//        self.dismiss(animated: true)
//    }

    @IBAction func cancelButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }

    @IBAction func applyFilterBUttonTapped(_ sender: UIButton) {
        var filterData:FilterModel? = FilterModel()
        filterData?.gender = self.gender
        filterData?.minAge = self.minAge
        filterData?.maxAge = self.maxAge
        filterData?.distance = self.distance
        filterData?.isVerified = self.isVerified
        filterData?.isOnline = self.isOnline
        print(filterData as Any)
        UserDataManager.shared.filterDataModel = filterData
        self.filterAction?(filterData)
        self.dismiss(animated: true)
    }

    @IBAction func clearFilterButtonTapped(_ sender: UIButton) {
//        var filterData:FilterModel? = FilterModel()
//        filterData?.gender = ""
//        filterData?.minAge = "18"
//        filterData?.maxAge = "60"
//        filterData?.distance = "0"
//        filterData?.isVerified = self.isVerified
//        filterData?.isOnline = self.isOnline

        clearFilterValues()
        self.clearFilterAction()
        self.dismiss(animated: true)
    }
    
    private func clearFilterValues() {
        resetGenderUI()
//
//        onlineNowSwitch.isOn = false
//           verifiedSwitch.isOn = false
//           self.isOnline = "0"
//           self.isVerified = "0"
//
//           // Reset age range: 18 to 60
//           rangeSliderCustom.selectedMinValue = 18.0
//           rangeSliderCustom.selectedMaxValue = 60.0
//           self.minAge = "18"
//           self.maxAge = "60"
//           ageRangeLabel.text = "18-60"
//
//           // Reset distance: 0 miles
//           customSlider.value = 0
//           customSlider.thumbLabel.text = "0Miles"
//           customSlider.updateLabelPosition()
//           self.distance = "0"

           // Clear filter data from memory
        
        var filterData:FilterModel? = FilterModel()
        filterData?.gender = "0"
        filterData?.minAge = "18"
        filterData?.maxAge = "70"
        filterData?.distance = "200"
        filterData?.isVerified = "0"
        filterData?.isOnline = "0"
        print(filterData as Any)
        UserDataManager.shared.filterDataModel = filterData

        
    }
    
    private func resetGenderUI() {
        self.gender = "0"
        [femaleImageView, maleImageView, otherImageView].forEach { view in
            view?.layer.borderWidth = 1
            view?.layer.borderColor = UIColor.clear.cgColor
            view?.layer.shadowOpacity = 0
        }
    }
    
    private func setMaleSelectionUI(){
        self.gender = "1"
        self.maleImageView.layer.borderWidth = 2
        self.maleImageView.addShadow(color: AppColor.BlueRibbon, opacity: 1.0, offset: CGSize(width: 0, height: 1.0))
        [self.femaleImageView,self.otherImageView].forEach { imageView in
            imageView?.layer.borderWidth = 1
            imageView?.addShadow(color: AppColor.AppWhite, opacity: 0, offset: CGSize(width: 0, height: 0.0))
        }
    }

    private func setFemaleSelectionUI(){
        self.gender = "2"
        self.femaleImageView.layer.borderWidth = 2
        self.femaleImageView.addShadow(color: AppColor.Carnation, opacity: 1.0, offset: CGSize(width: 0, height: 1.0))
        [self.maleImageView,self.otherImageView].forEach { imageView in
            imageView?.layer.borderWidth = 1
            imageView?.addShadow(color: AppColor.AppWhite, opacity: 0, offset: CGSize(width: 0, height: 0.0))
        }
    }

    private func setOtherSelectionUI(){
        self.gender = "3"
        self.otherImageView.layer.borderWidth = 2
        self.otherImageView.addShadow(color: AppColor.ElectricViolet, opacity: 1.0, offset: CGSize(width: 0, height: 1.0))
        [self.femaleImageView,self.maleImageView].forEach { imageView in
            imageView?.layer.borderWidth = 1
            imageView?.addShadow(color: AppColor.AppWhite, opacity: 0, offset: CGSize(width: 0, height: 0.0))
        }
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
}

extension ExploreFilterViewController: RangeSeekSliderDelegate {

    func rangeSeekSlider(_ slider: RangesSeekSlider, didChange minValue: CGFloat, maxValue: CGFloat) {
        print("Custom slider updated. Min Value: \(minValue) Max Value: \(maxValue)")
        let ageRange = minValue == maxValue ? "\(Int(maxValue))" : "\(Int(minValue))-\(Int(maxValue))"
        self.ageRangeLabel.text = ageRange
        self.minAge = "\(Int(minValue))"
        self.maxAge = "\(Int(maxValue))"
    }
    func didStartTouches(in slider: RangesSeekSlider) {
        print("did start touches")
    }

    func didEndTouches(in slider: RangesSeekSlider) {
        print("did end touches")
    }
}

class TappableSlider: UISlider {
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        let percentage = point.x / bounds.width
        let newValue = Float(percentage) * (maximumValue - minimumValue) + minimumValue
        setValue(newValue, animated: true)
        sendActions(for: .valueChanged)
        return true // 👈 thumb jumps immediately
    }
}
