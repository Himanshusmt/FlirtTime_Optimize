//
//  LiveStreamingViewController.swift
//  FlirttimeNew
//
//  UIViewController Host for LiveStreamingView
//

import UIKit
import SwiftUI

final class LiveStreamingViewController: UIViewController {

    private let isHost: Bool
    private var hostingController: UIHostingController<LiveStreamingView>?

    init(isHost: Bool = true) {
        self.isHost = isHost
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.isHost = true
        super.init(coder: coder)
    }

    override var prefersStatusBarHidden: Bool {
        return false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        LiveStreamingManager.shared.isHost = isHost
        LiveStreamingManager.shared.role = isHost ? .broadcaster : .audience

        let liveView = LiveStreamingView(onDismiss: { [weak self] in
            self?.dismiss(animated: true)
        })

        let hosting = UIHostingController(rootView: liveView)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hosting.didMove(toParent: self)
        self.hostingController = hosting
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            LiveStreamingManager.shared.leaveLiveStream()
        }
    }
}
