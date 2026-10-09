//
//  WhyVibeDetailsViewController.swift
//  FlirttimeNew
//

import UIKit

final class WhyVibeDetailsViewController: UIViewController {

    private let profile: VibeProfile

    init(profile: VibeProfile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite

        let titleLabel = UILabel.vibeLabel(.bold, 22, style: .title2, color: AppColor.AppBlack, lines: 0)
        titleLabel.text = "Why you and \(profile.displayName) might vibe"
        titleLabel.accessibilityTraits = .header

        let stack = UIStackView(arrangedSubviews: [titleLabel])
        stack.axis = .vertical
        stack.spacing = 16

        if let shared = profile.sharedVibesText {
            let sharedLabel = UILabel.vibeLabel(.medium, 15, color: AppColor.Punch)
            sharedLabel.text = "✨ " + shared
            stack.addArrangedSubview(sharedLabel)
        }

        let reasons = UIStackView()
        reasons.axis = .vertical
        reasons.spacing = 10
        for reason in profile.reasons {
            let label = UILabel.vibeLabel(.regular, 16, color: AppColor.MineShaft, lines: 0)
            label.text = "•  " + reason
            reasons.addArrangedSubview(label)
        }
        stack.addArrangedSubview(reasons)

        if !profile.sharedInterests.isEmpty {
            let header = UILabel.vibeLabel(.bold, 16, style: .headline, color: AppColor.AppBlack)
            header.text = "Interests you share"
            let chips = VibeChipsView()
            chips.configure(profile.sharedInterests, highlighted: Set(profile.sharedInterests.map(\.id)))
            chips.isUserInteractionEnabled = false
            stack.addArrangedSubview(header)
            stack.setCustomSpacing(8, after: header)
            stack.addArrangedSubview(chips)
        }

        let footnote = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.SilverChalice, lines: 0)
        footnote.text = "Based only on what you've both added to your profiles."
        stack.addArrangedSubview(footnote)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }
}
