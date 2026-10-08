//
//  Extensions.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import UIKit
import CoreLocation
import Photos
import PhotosUI
import PDFKit

extension UIView {
    public func setRoundedManualTopCorners(cornerRadius: CGFloat) {
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
        layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
        layer.masksToBounds = true
    }
    
    public func setRoundedManualbottomCorners(cornerRadius: CGFloat) {
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
        layer.maskedCorners = [.layerMaxXMaxYCorner , .layerMinXMaxYCorner]
        layer.masksToBounds = true
    }

    public func setRoundedManualLeftCorners(cornerRadius: CGFloat) {
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        layer.masksToBounds = true
    }

    public func setRoundedManualRightCorners(cornerRadius: CGFloat) {
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
        layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        layer.masksToBounds = true
    }

    func addShadow(color:UIColor,opacity:Float,size:CGSize,radius:CGFloat,maskToBound:Bool) {
        self.layer.shadowColor = color.cgColor // Shadow color
        self.layer.shadowOpacity = opacity // Shadow opacity
        self.layer.shadowOffset = size // Shadow offset
        self.layer.shadowRadius = radius // Shadow radius
        self.layer.masksToBounds = maskToBound // Allow shadow to exceed view bounds if needed
    }

    func removeShadow() {
        self.layer.shadowColor = nil
        self.layer.shadowOpacity = 0
        self.layer.shadowOffset = .zero
        self.layer.shadowRadius = 0
        self.layer.masksToBounds = false
    }

    @discardableResult
    func anchor(top: NSLayoutYAxisAnchor? = nil,
                left: NSLayoutXAxisAnchor? = nil,
                bottom: NSLayoutYAxisAnchor? = nil,
                right: NSLayoutXAxisAnchor? = nil,
                paddingTop: CGFloat = 0,
                paddingLeft: CGFloat = 0,
                paddingBottom: CGFloat = 0,
                paddingRight: CGFloat = 0,
                width: CGFloat = 0,
                height: CGFloat = 0) -> [NSLayoutConstraint] {
      translatesAutoresizingMaskIntoConstraints = false

      var anchors = [NSLayoutConstraint]()

      if let top = top {
        anchors.append(topAnchor.constraint(equalTo: top, constant: paddingTop))
      }
      if let left = left {
        anchors.append(leftAnchor.constraint(equalTo: left, constant: paddingLeft))
      }
      if let bottom = bottom {
        anchors.append(bottomAnchor.constraint(equalTo: bottom, constant: -paddingBottom))
      }
      if let right = right {
        anchors.append(rightAnchor.constraint(equalTo: right, constant: -paddingRight))
      }
      if width > 0 {
        anchors.append(widthAnchor.constraint(equalToConstant: width))
      }
      if height > 0 {
        anchors.append(heightAnchor.constraint(equalToConstant: height))
      }

      anchors.forEach { $0.isActive = true }

      return anchors
    }

    @discardableResult
    func anchorToSuperview() -> [NSLayoutConstraint] {
      return anchor(top: superview?.topAnchor,
                    left: superview?.leftAnchor,
                    bottom: superview?.bottomAnchor,
                    right: superview?.rightAnchor)
    }
}

extension DispatchQueue {
    static func background(delay: Double = 0.0, background: (()->Void)? = nil, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .background).async {
            background?()
            if let completion = completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: {
                    completion()
                })
            }
        }
    }
}

extension UITapGestureRecognizer {

    func didTapAttributedTextInLabel(label: UILabel, inRange targetRange: NSRange) -> Bool {
        // Create instances of NSLayoutManager, NSTextContainer and NSTextStorage
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize.zero)
        let textStorage = NSTextStorage(attributedString: label.attributedText!)

        // Configure layoutManager and textStorage
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        // Configure textContainer
        textContainer.lineFragmentPadding = 0.0
        textContainer.lineBreakMode = label.lineBreakMode
        textContainer.maximumNumberOfLines = label.numberOfLines
        let labelSize = label.bounds.size
        textContainer.size = labelSize

        // Find the tapped character location and compare it to the specified range
        let locationOfTouchInLabel = self.location(in: label)
        let textBoundingBox = layoutManager.usedRect(for: textContainer)
        //let textContainerOffset = CGPointMake((labelSize.width - textBoundingBox.size.width) * 0.5 - textBoundingBox.origin.x,
        //(labelSize.height - textBoundingBox.size.height) * 0.5 - textBoundingBox.origin.y);
        let textContainerOffset = CGPoint(x: (labelSize.width - textBoundingBox.size.width) * 0.5 - textBoundingBox.origin.x, y: (labelSize.height - textBoundingBox.size.height) * 0.5 - textBoundingBox.origin.y)

        //let locationOfTouchInTextContainer = CGPointMake(locationOfTouchInLabel.x - textContainerOffset.x,
        // locationOfTouchInLabel.y - textContainerOffset.y);
        let locationOfTouchInTextContainer = CGPoint(x: locationOfTouchInLabel.x - textContainerOffset.x, y: locationOfTouchInLabel.y - textContainerOffset.y)
        let indexOfCharacter = layoutManager.characterIndex(for: locationOfTouchInTextContainer, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        return NSLocationInRange(indexOfCharacter, targetRange)
    }
}

extension UIViewController:UIImagePickerControllerDelegate, UINavigationControllerDelegate{

    func showCameraAccessAlert() {
        let alertController = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable access to the camera in Settings",
            preferredStyle: .alert
        )

        let settingsAction = UIAlertAction(title: "Settings", style: .default) { _ in
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
            if UIApplication.shared.canOpenURL(settingsURL) {
                UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
            }
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        alertController.addAction(settingsAction)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }
    
    // Function to show alert for photo library access permission
       func showPhotoLibraryAccessAlert() {
           let alertController = UIAlertController(
               title: "Photo Library Access Required",
               message: "Please enable access to the photo library in Settings",
               preferredStyle: .alert
           )

           let settingsAction = UIAlertAction(title: "Settings", style: .default) { _ in
               guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
               if UIApplication.shared.canOpenURL(settingsURL) {
                   UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
               }
           }

           let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

           alertController.addAction(settingsAction)
           alertController.addAction(cancelAction)

           present(alertController, animated: true, completion: nil)
       }

    func presentCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.sourceType = .camera
            present(imagePicker, animated: true, completion: nil)
        } else {
            // Display an alert indicating that the camera is not available
            let alert = UIAlertController(title: "Camera Not Available", message: "Sorry, but it seems like your device doesn't have a camera.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
    
    func openPhotoLibrary() {
        let photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
        if photoAuthorizationStatus == .authorized {
            DispatchQueue.main.async {
                let picker = UIImagePickerController()
                picker.sourceType = .photoLibrary
                picker.allowsEditing = true
                picker.delegate = self // Make sure your view controller conforms to UIImagePickerControllerDelegate and UINavigationControllerDelegate
                self.present(picker, animated: true, completion: nil)
            }
        } else {
            // Handle case when user doesn't have access to the photo library
            print("User doesn't have access to the photo library")
        }
    }

}

extension UIPageControl {

    var page: Int {
        get {
            currentPage
        }
        set {
            //currentPage = newValue
            print(newValue)
            self.setIndicatorImage(UIImage(named: "PageControllVisible"), forPage: newValue)
            for  index in 0..<numberOfPages where index != newValue {
                self.setIndicatorImage(UIImage(named: "PageControllBlank"), forPage: index)
            }
        }
    }
}

extension Date {
    func convertDateToddMMYYYY() -> String?{
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let date = dateFormatter.string(from: self)
        return date
    }

    func convertDateToYYYYMMdd() -> String?{
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: self)
        return date
    }
    
    func getElapsedInterval() -> String {
        let now = Date()
        let interval = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: self, to: now)

        if let year = interval.year, year > 0 {
            return year == 1 ? "1 year ago" : "\(year) years ago"
        } else if let month = interval.month, month > 0 {
            return month == 1 ? "1 month ago" : "\(month) months ago"
        } else if let day = interval.day, day > 0 {
            if day >= 7 {
                let weeks = day / 7
                let remainingDays = day % 7
                if remainingDays > 0 {
                    let weekStr = weeks == 1 ? "1 week" : "\(weeks) weeks"
                    let dayStr = remainingDays == 1 ? "1 day" : "\(remainingDays) days"
                    return "\(weekStr) \(dayStr) ago"
                } else {
                    return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
                }
            } else {
                return day == 1 ? "1 day ago" : "\(day) days ago"
            }
        } else if let hour = interval.hour, hour > 0 {
            return hour == 1 ? "1 hour ago" : "\(hour) hours ago"
        } else if let minute = interval.minute, minute > 0 {
            return minute == 1 ? "1 minute ago" : "\(minute) minutes ago"
        } else {
            return "Just now"
        }
    }


}

extension String {
    func convertDateTo_ddMMyyyy() -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")

        guard let date = inputFormatter.date(from: self) else { return self }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "dd/MM/yyyy"
        return outputFormatter.string(from: date)
    }
}

extension UIViewController {
    func navigateToLoginScreen(){
        ChatAuthStore.shared.logout()
        UserDataManager.shared.removeUserData()
        MockDataStore.shared.reset()
        let aLoginViewController = LoginOptionsViewController.instantiateFromStoryboard()
        let navigationController = UINavigationController(rootViewController: aLoginViewController)
        navigationController.isNavigationBarHidden = true
        UserDataManager.shared.isOTPVerificationDone = false
        UIApplication.shared.windows.first?.rootViewController = navigationController
        UIApplication.shared.windows.first?.makeKeyAndVisible()
    }
}

extension Array {
    func item(at index: Int) -> Element? {
        return (index < self.count && index >= 0) ? self[index] : nil
    }
}

extension TimeInterval {

    // Get the formatted elapsed time
    func formattedElapsedTime() -> String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Data {
    func renderFirstPageOfPDF() -> UIImage? {
        guard let document = PDFDocument(data: self) else {
            return nil
        }

        guard let page = document.page(at: 0) else {
            return nil
        }

        let pageSize = page.bounds(for: .mediaBox).size

        let renderer = UIGraphicsImageRenderer(size: pageSize)
        let renderedImage = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: pageSize))

            ctx.cgContext.translateBy(x: 0.0, y: pageSize.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)

            ctx.cgContext.drawPDFPage(page.pageRef!)
        }

        return renderedImage
    }
}

extension String {
    func convertStringToDate() -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return dateFormatter.date(from: self)
    }
    var firstLetterCapitalized: String {
            guard let first = self.first else { return self }
            return first.uppercased() + self.dropFirst()
        }
}

extension UIImage {
    func normalizedImage() -> UIImage {
        if self.imageOrientation == .up {
            return self
        }
        
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: self.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
    }
    
    func fixedOrientation() -> UIImage {
            guard let cgImage = self.cgImage else { return self }

            if imageOrientation == .up {
                return self
            }

            var transform = CGAffineTransform.identity

            switch imageOrientation {
            case .down, .downMirrored:
                transform = transform.translatedBy(x: size.width, y: size.height)
                transform = transform.rotated(by: .pi)
            case .left, .leftMirrored:
                transform = transform.translatedBy(x: size.width, y: 0)
                transform = transform.rotated(by: .pi / 2)
            case .right, .rightMirrored:
                transform = transform.translatedBy(x: 0, y: size.height)
                transform = transform.rotated(by: -.pi / 2)
            case .up, .upMirrored:
                break
            @unknown default:
                break
            }

            switch imageOrientation {
            case .upMirrored, .downMirrored:
                transform = transform.translatedBy(x: size.width, y: 0)
                transform = transform.scaledBy(x: -1, y: 1)
            case .leftMirrored, .rightMirrored:
                transform = transform.translatedBy(x: size.height, y: 0)
                transform = transform.scaledBy(x: -1, y: 1)
            default:
                break
            }

            guard let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: cgImage.bitsPerComponent,
                bytesPerRow: 0,
                space: cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: cgImage.bitmapInfo.rawValue
            ) else { return self }

            context.concatenate(transform)

            switch imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored:
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
            default:
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }

            guard let newCGImage = context.makeImage() else { return self }
            return UIImage(cgImage: newCGImage)
        }
}








