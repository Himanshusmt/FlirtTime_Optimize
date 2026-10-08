//
//  InstaImageZoom.swift
//  FlirttimeNew
//

import UIKit

/// Instagram-style pinch zoom: the photo lifts into the window while pinching and springs back on release.
public class InstaImageZoom {
    static let ImageZoomStartedZoomNotification = Notification.Name("ImageZoom_Started_Zoom_Notification")
    static let ImageZoomEndedZoomNotification = Notification.Name("ImageZoom_Ended_Zoom_Notification")

    private var currentImageView: UIImageView?
    private var hostImageView: UIImageView?
    private var isAnimatingReset = false
    private var firstCenterPoint = CGPoint.zero
    private var startingRect = CGRect.zero
    private var lastPinchCenter = CGPoint.zero
    private var lastTouchPosition = CGPoint.zero

    var isHandlingGesture: Bool {
        return hostImageView != nil
    }

    static public let shared = InstaImageZoom()

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    public func gestureStateChanged(_ gesture: UIGestureRecognizer, withZoomImageView imageView: UIImageView) {
        guard let theGesture = gesture as? UIPinchGestureRecognizer else { return }

        if isAnimatingReset {
            return
        }

        if theGesture.state == .ended || theGesture.state == .cancelled || theGesture.state == .failed {
            resetImageZoom()
            return
        }

        if isHandlingGesture && hostImageView != imageView {
            return
        }

        if !isHandlingGesture && theGesture.state == .began {
            guard imageView.image != nil, let currentWindow = keyWindow else { return }
            firstCenterPoint = theGesture.location(in: currentWindow)

            let point = imageView.convert(imageView.bounds.origin, to: nil)
            startingRect = CGRect(x: point.x, y: point.y, width: imageView.frame.width, height: imageView.frame.height)

            let zoomImageView = UIImageView(image: imageView.image)
            zoomImageView.contentMode = imageView.contentMode
            zoomImageView.clipsToBounds = imageView.clipsToBounds
            zoomImageView.layer.cornerRadius = imageView.layer.cornerRadius
            zoomImageView.bounds = startingRect
            let imageViewBoundsCenter = CGPoint(x: imageView.bounds.width * 0.5, y: imageView.bounds.height * 0.5)
            zoomImageView.center = imageView.convert(imageViewBoundsCenter, to: currentWindow)
            currentWindow.addSubview(zoomImageView)
            currentImageView = zoomImageView

            hostImageView = imageView
            imageView.isHidden = true

            NotificationCenter.default.post(name: InstaImageZoom.ImageZoomStartedZoomNotification, object: nil)
        }

        guard theGesture.state == .changed, let currentImageView else { return }

        if theGesture.numberOfTouches == 1 {
            let currentTouchPosition = theGesture.location(ofTouch: 0, in: imageView)

            if lastTouchPosition == CGPoint.zero {
                lastTouchPosition = currentTouchPosition
                return
            }

            let translation = CGPoint(x: currentTouchPosition.x - lastTouchPosition.x, y: currentTouchPosition.y - lastTouchPosition.y)
            currentImageView.center = CGPoint(x: lastPinchCenter.x + translation.x, y: lastPinchCenter.y + translation.y)
            lastTouchPosition = currentTouchPosition
        } else {
            // Zoom in only: pinching closed never shrinks the photo below its on-screen size.
            let newScale = max(theGesture.scale, 1)
            currentImageView.frame = CGRect(x: currentImageView.frame.origin.x,
                                            y: currentImageView.frame.origin.y,
                                            width: startingRect.width * newScale,
                                            height: startingRect.height * newScale)

            let location = theGesture.location(in: keyWindow)
            let centerXDif = (firstCenterPoint.x - location.x) + (firstCenterPoint.x.distance(to: startingRect.midX) * (1 - newScale))
            let centerYDif = (firstCenterPoint.y - location.y) + (firstCenterPoint.y.distance(to: startingRect.midY) * (1 - newScale))
            currentImageView.center = CGPoint(x: startingRect.midX - centerXDif,
                                              y: startingRect.midY - centerYDif)

            lastTouchPosition = CGPoint.zero
        }

        lastPinchCenter = currentImageView.center
    }

    public func resetImageZoom() {
        if isAnimatingReset || !isHandlingGesture {
            return
        }

        isAnimatingReset = true

        UIView.animate(withDuration: 0.2, animations: {
            self.currentImageView?.frame = self.startingRect
        }, completion: { _ in
            self.currentImageView?.removeFromSuperview()
            self.currentImageView = nil
            self.hostImageView?.isHidden = false
            self.hostImageView = nil
            self.startingRect = CGRect.zero
            self.firstCenterPoint = CGPoint.zero
            self.lastTouchPosition = CGPoint.zero
            self.isAnimatingReset = false
            NotificationCenter.default.post(name: InstaImageZoom.ImageZoomEndedZoomNotification, object: nil)
        })
    }
}
