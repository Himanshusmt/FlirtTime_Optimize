import UIKit

enum ChatMessagesLayout {

    static func create() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = MessageCellMetrics.lineSpacing
        layout.minimumInteritemSpacing = 0
        layout.sectionHeadersPinToVisibleBounds = false
        layout.estimatedItemSize = .zero
        return layout
    }
}
