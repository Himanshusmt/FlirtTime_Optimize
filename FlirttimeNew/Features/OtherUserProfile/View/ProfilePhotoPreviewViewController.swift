//
//  ProfilePhotoPreviewViewController.swift
//  FlirttimeNew
//
//  Instagram-style enlarged profile photo. Layout lives in OtherUserProfile.storyboard;
//  the photo can only be zoomed in (minimumZoomScale is 1 and zoom bouncing is off).
//

import UIKit

final class ProfilePhotoPreviewViewController: UIViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.otherUserProfile
    }

    private static let doubleTapZoomScale: CGFloat = 2.5

    var photoPath: String?
    var previewImage: UIImage?
    var userName = ""

    @IBOutlet private weak var photoContainerView: UIView!
    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var photoImageView: UIImageView!
    @IBOutlet private weak var nameLabel: UILabel!

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        nameLabel.text = userName
        photoImageView.accessibilityLabel = "\(userName)'s profile photo"
        photoImageView.loadImage(path: photoPath, placeholder: previewImage ?? UIImage(named: "ProfileBlur"))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        photoContainerView.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        nameLabel.alpha = 0
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.75,
                       initialSpringVelocity: 0.6, options: [.curveEaseOut]) {
            self.photoContainerView.transform = .identity
            self.nameLabel.alpha = 1
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        photoContainerView.layer.cornerRadius = photoContainerView.bounds.width / 2
        if scrollView.zoomScale == scrollView.minimumZoomScale {
            photoImageView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    // MARK: - Actions

    @IBAction private func closeTapped(_ sender: Any) {
        UIView.animate(withDuration: 0.2) {
            self.photoContainerView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            self.photoContainerView.alpha = 0
            self.nameLabel.alpha = 0
        }
        dismiss(animated: true)
    }

    @IBAction private func photoDoubleTapped(_ sender: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = sender.location(in: photoImageView)
        let scale = min(Self.doubleTapZoomScale, scrollView.maximumZoomScale)
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        scrollView.zoom(to: rect, animated: true)
    }
}

// MARK: - Zoom

extension ProfilePhotoPreviewViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        photoImageView
    }
}
