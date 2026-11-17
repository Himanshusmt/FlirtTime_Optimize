//
//  LiveVideoCanvasView.swift
//  FlirttimeNew
//
//  SwiftUI Video Canvas for Live Streaming
//

import SwiftUI
import UIKit

struct LiveVideoCanvasView: UIViewRepresentable {
    let isLocal: Bool
    let remoteUid: UInt?

    init(isLocal: Bool = true, remoteUid: UInt? = nil) {
        self.isLocal = isLocal
        self.remoteUid = remoteUid
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        if isLocal {
            LiveStreamingManager.shared.bindLocalCanvas(to: view)
        } else if let uid = remoteUid {
            LiveStreamingManager.shared.bindRemoteCanvas(to: view, uid: uid)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if isLocal {
            LiveStreamingManager.shared.bindLocalCanvas(to: uiView)
        } else if let uid = remoteUid {
            LiveStreamingManager.shared.bindRemoteCanvas(to: uiView, uid: uid)
        }
    }
}
