//
//  CustomSlider.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 13/06/24.
//

import Foundation
import UIKit

class CustomSlider: UISlider {
    let thumbLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Customize the slider appearance
        self.minimumTrackTintColor = AppColor.Punch
        self.maximumTrackTintColor = AppColor.Punch.withAlphaComponent(0.25)

        // Customize the thumb image with a smaller size
//        if let thumbImage = UIImage(named: "sliderThumbIcon") {
//            self.setThumbImage(thumbImage, for: .normal)
//        }
        
        if let thumbImage = UIImage(named: "sliderThumbIcon") {
            let newSize = CGSize(width: 20, height: 20) // bigger size
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            thumbImage.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            self.setThumbImage(resizedImage, for: .normal)
        }

        // Setup the label
        thumbLabel.textAlignment = .center
        thumbLabel.backgroundColor = AppColor.Punch
        thumbLabel.textColor = .white
        thumbLabel.font = UIFont.fredoka(.regular,size:11)
        thumbLabel.layer.cornerRadius = 5
        thumbLabel.layer.masksToBounds = true
//        thumbLabel.text = "50 Miles"

        // Set a fixed size for the label based on the initial content
        self.setLabelUI()

        // Add the label to the slider
        self.addSubview(thumbLabel)

        // Initial position of the label
        updateLabelPosition()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLabelPosition()
    }

    private func setLabelUI(){
        let labelWidth = thumbLabel.intrinsicContentSize.width + 10
        let labelHeight = thumbLabel.intrinsicContentSize.height + 11
        thumbLabel.frame.size = CGSize(width: labelWidth, height: labelHeight)
    }

    func updateLabelPosition() {
        self.setLabelUI()
        let thumbRect = self.thumbRect(forBounds: self.bounds, trackRect: self.trackRect(forBounds: self.bounds), value: self.value)
        // Position the label below the thumb
        thumbLabel.center = CGPoint(x: thumbRect.midX, y: thumbRect.maxY + thumbLabel.frame.height - 5) // Adjust the value as needed
    }

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        // Override to set custom track height
        let customBounds = CGRect(origin: bounds.origin, size: CGSize(width: bounds.size.width, height: 10)) // Adjust the height as needed
        super.trackRect(forBounds: customBounds)
        return customBounds
    }
}
