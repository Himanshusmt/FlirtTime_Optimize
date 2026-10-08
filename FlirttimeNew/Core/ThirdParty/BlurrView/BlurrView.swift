//
//  BlurrView.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 12/05/24.
//

import Foundation
import UIKit

class BlurView: UIView {
    // Declare the blur effect view as a property
    private var blurEffectView: UIVisualEffectView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupBlurView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupBlurView()
    }

    private func setupBlurView() {
        // Create a blur effect
        let blurEffect = UIBlurEffect(style: .light)

        // Create a visual effect view with the blur effect
        blurEffectView = UIVisualEffectView(effect: blurEffect)

        // Set the autoresizing mask to ensure the blur view resizes with its superview
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Add the blur effect view as a subview
        addSubview(blurEffectView)

        // Setup constraints to match the blur effect view to the bounds of this view
        blurEffectView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurEffectView.topAnchor.constraint(equalTo: topAnchor),
            blurEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
