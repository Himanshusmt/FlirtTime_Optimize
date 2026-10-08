//
//  CircularProgressView.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 04/05/24.
//


import Foundation
import UIKit
import QuartzCore

import UIKit
import QuartzCore

class CircularProgressView: UIView {

    private var progressLayer = CAShapeLayer()
    private var trackLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.configureProgressViewToBeCircular()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.configureProgressViewToBeCircular()
    }

    var setProgressColor: UIColor = UIColor.red {
        didSet {
            progressLayer.strokeColor = setProgressColor.cgColor
        }
    }

    var setProgressLineWidth: CGFloat = 10 {
        didSet {
            progressLayer.lineWidth = setProgressLineWidth
            self.updatePaths()
        }
    }

    var setTrackLineWidth: CGFloat = 10 {
        didSet {
            trackLayer.lineWidth = setTrackLineWidth
            self.updatePaths()
        }
    }

    var setTrackColor: UIColor = UIColor.lightGray {
        didSet {
            trackLayer.strokeColor = setTrackColor.cgColor
        }
    }

    var startAngle: CGFloat = CGFloat(-0.5 * Double.pi) {
        didSet {
            self.updatePaths()
        }
    }

    var endAngle: CGFloat = CGFloat(1.5 * Double.pi) {
        didSet {
            self.updatePaths()
        }
    }

    private func viewCGPaths(startAngle: CGFloat, endAngle: CGFloat) -> CGPath? {
        let radius = min(frame.size.width, frame.size.height) / 2 - setProgressLineWidth / 2
        return UIBezierPath(arcCenter: CGPoint(x: frame.size.width / 2.0, y: frame.size.height / 2.0),
                            radius: radius,
                            startAngle: startAngle,
                            endAngle: endAngle, clockwise: true).cgPath
    }

    private func updatePaths() {
        trackLayer.path = self.viewCGPaths(startAngle: startAngle, endAngle: endAngle)
        progressLayer.path = self.viewCGPaths(startAngle: startAngle, endAngle: endAngle)
    }

    private func configureProgressViewToBeCircular() {
        self.backgroundColor = UIColor.clear
        self.layer.cornerRadius = self.frame.size.width / 2.0

        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = setTrackColor.cgColor
        trackLayer.lineWidth = setTrackLineWidth
        trackLayer.strokeEnd = 1.0
        trackLayer.lineCap = .round
        self.layer.addSublayer(trackLayer)

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = setProgressColor.cgColor
        progressLayer.lineWidth = setProgressLineWidth
        progressLayer.strokeEnd = 0.0
        progressLayer.lineCap = .round
        
        // Shadow
        progressLayer.shadowColor = UIColor.black.cgColor
        progressLayer.shadowOpacity = 0.3
        progressLayer.shadowOffset = CGSize(width: 1, height: 1)
        progressLayer.shadowRadius = 3

        
        self.layer.addSublayer(progressLayer)

        self.updatePaths()
    }

    func setProgressWithAnimation(duration: TimeInterval, value: Float) {
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.duration = duration
        animation.fromValue = progressLayer.strokeEnd
        animation.toValue = value
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        progressLayer.strokeEnd = CGFloat(value)
        progressLayer.add(animation, forKey: "animateCircle")
    }
}
