//
//  OtherUserPhotoGridViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 17/05/24.
//

import  UIKit

class OtherUserPhotoGridCell: UICollectionViewCell {
    static let identifier = "OtherUserPhotoGridCell"

    @IBOutlet weak var imageView: UIImageView!
    

}

class OtherUserPhotoGridViewController: BaseViewController, Instantiable {
   
    @IBOutlet weak var collectionView: UICollectionView!
    
    let arrayMoments: [UIImage] = ["delete-13", "delete-14", "delete-21", "delete-18", "delete-19", "delete-20", "delete-8",
                                   "delete-13", "delete-18", "delete-14", "delete-21", "delete-19", "delete-20", "delete-8",
                                   "delete-13", "delete-21", "delete-14", "delete-18", "delete-19", "delete-20", "delete-9"]
        .compactMap { UIImage(named: $0) }
    
    static var storyboardName: StringConvertible {
        return StoryboardName.moments
    }
    private let spacing: CGFloat = 4

    override func viewDidLoad() {
        super.viewDidLoad()
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        self.collectionView.collectionViewLayout = layout
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
    }

    @IBAction func actionOnBack(_ sender: Any) {
        self.navigationController?.popViewController(animated: true)
    }

}

extension OtherUserPhotoGridViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView,numberOfItemsInSection section: Int) -> Int {
        return arrayMoments.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OtherUserPhotoGridCell.identifier, for: indexPath) as? OtherUserPhotoGridCell {
            cell.imageView.image = arrayMoments[indexPath.row]
            cell.imageView.contentMode = .scaleAspectFill
            cell.imageView.clipsToBounds = true
            return cell
        }
        return UICollectionViewCell()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width - collectionView.contentInset.left - collectionView.contentInset.right
        // Every 7th photo spans the full row, the rest form a 3-column grid.
        if indexPath.item % 7 == 6 {
            return CGSize(width: width, height: width * 0.66)
        }
        let cellWidth = floor((width - spacing * 2) / 3)
        return CGSize(width: cellWidth, height: cellWidth)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.showComingSoon("Moments")
    }
}
