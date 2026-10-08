//
//  ChatSwiftUIHost.swift
//  FlirttimeNew
//
//  Created by Awais on 14/05/26.
//

import UIKit
import SwiftUI

enum ChatPresentationStyle {
    case fullScreen
    case pageSheet
    case overFullScreen
}

struct ChatSwiftUIHost {

    @discardableResult
    static func present<Content: View>(
        _ view: Content,
        style: ChatPresentationStyle,
        detents: [UISheetPresentationController.Detent] = [.large()],
        prefersGrabber: Bool = true,
        from source: UIViewController? = nil,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) -> UIHostingController<Content> {
        let hosting = UIHostingController(rootView: view)

        switch style {
        case .fullScreen:
            hosting.modalPresentationStyle = .fullScreen
        case .pageSheet:
            hosting.modalPresentationStyle = .pageSheet
            if let sheet = hosting.sheetPresentationController {
                sheet.detents = detents
                sheet.prefersGrabberVisible = prefersGrabber
            }
        case .overFullScreen:
            hosting.modalPresentationStyle = .overFullScreen
            hosting.view.backgroundColor = .clear
        }

        (source ?? topViewController())?.present(hosting, animated: animated, completion: completion)
        return hosting
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.topViewController()
    }
}
