//
//  EditImageCollCell.swift
//  FlirttimeNew
//

import UIKit

class EditImageCollCell: UICollectionViewCell {
    static let identifier = "EditImageCollCell"

    @IBOutlet weak var editImageView: UIImageView!
    @IBOutlet weak var crossButton: UIButton!
    var onDeleteTapped: (() -> Void)?
    var onReplaceTapped: (() -> Void)?

    @IBAction func crossButtonTapped(_ sender: UIButton) {
        onDeleteTapped?()
    }

    @IBAction func replaceButtonTapped(_ sender: UIButton) {
        onReplaceTapped?()
    }
}
