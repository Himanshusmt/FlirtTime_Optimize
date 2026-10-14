//
//  InterestCollectionViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 08/05/24.
//

import UIKit

class InterestCollectionViewCell: UICollectionViewCell {

    static let identifier = "InterestCollectionViewCell"

    @IBOutlet weak var mainView: UIView!
    @IBOutlet weak var interestIcon: UIImageView!
    @IBOutlet weak var interestTitleLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    //InterestOption
    func setUI(data:attOptions?, userInfo: UserDetailsData?){
        self.interestTitleLabel.text = data?.title
        self.interestIcon.setInterestIcon(data?.photo)
        self.interestTitleLabel.textColor = data?.isSelected ?? false ? AppColor.AppWhite : AppColor.AppBlack
        self.mainView.layer.borderColor = data?.isSelected ?? false ? AppColor.Punch.cgColor : AppColor.Iron.cgColor
        self.mainView.backgroundColor = data?.isSelected ?? false ? AppColor.Punch : AppColor.AppWhite
        self.mainView.addShadow(color: AppColor.Amaranth, opacity: data?.isSelected ?? false ?  0.2 : 0.0, offset: CGSize(width: 0, height: 8.0))
    }
}

extension UIImageView {
    /// Interest icons are either an emoji (backend catalog) or an image path (bundled `Attributes.json`).
    func setInterestIcon(_ icon: String?) {
        let icon = icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !icon.isEmpty else {
            image = nil
            return
        }
        if icon.contains("/") || icon.contains(".") {
            image = nil
            let path = icon.hasPrefix("http") ? icon : ApiName.imgBaseURL + icon
            if let url = URL(string: path) {
                loadImage(with: url)
            }
            return
        }
        contentMode = .scaleAspectFit
        image = Self.emojiImage(icon)
    }

    private static let emojiCache = NSCache<NSString, UIImage>()

    private static func emojiImage(_ emoji: String) -> UIImage {
        if let cached = emojiCache.object(forKey: emoji as NSString) { return cached }
        let font = UIFont.systemFont(ofSize: 64)
        let text = emoji as NSString
        let size = text.size(withAttributes: [.font: font])
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            text.draw(at: .zero, withAttributes: [.font: font])
        }
        emojiCache.setObject(image, forKey: emoji as NSString)
        return image
    }
}
