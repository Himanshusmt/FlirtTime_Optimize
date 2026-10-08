//
//  Image.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 02/05/24.
//

import UIKit
import ImageIO

extension UIImageView {
    func setGifImage(name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        var frames: [UIImage] = []
        var duration: Double = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            duration += (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        }
        self.image = UIImage.animatedImage(with: frames, duration: duration)
    }
}

extension UIImage {
    func resizeImage(targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { (context) in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resizedImage
    }

    func resizeSquarePlaceHolderImage(width:CGFloat,noOfitemsInRow:CGFloat) -> UIImage?{
            // Define the new size you want
            let newSize = CGSize(width: width/noOfitemsInRow, height: width/noOfitemsInRow) // Change the dimensions as per your requirement
            // Resize the image
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            self.draw(in: CGRect(origin: CGPoint.zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            // Set the resized image to the image view
            return resizedImage
    }

    func resizePlaceHolderImage(width:CGFloat,height:CGFloat,noOfitemsInRow:CGFloat) -> UIImage?{
            // Define the new size you want
            let newSize = CGSize(width: width/noOfitemsInRow, height: height) // Change the dimensions as per your requirement
            // Resize the image
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            self.draw(in: CGRect(origin: CGPoint.zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            // Set the resized image to the image view
            return resizedImage
    }
}
