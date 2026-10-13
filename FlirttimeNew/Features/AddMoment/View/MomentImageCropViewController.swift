//
//  MomentImageCropViewController.swift
//  FlirttimeNew
//
//  Crops photos picked on Add Moment to the shape of the feed's photo area
//  (`MomentsTableViewCell.mediaSize`), so a posted moment shows exactly what was framed here.
//

import UIKit

final class MomentImageCropViewController: UIViewController {

    /// Crops `images` one after another. `completion` gets the cropped photos, or none on Cancel.
    static func present(images: [UIImage], from presenter: UIViewController, completion: @escaping ([UIImage]) -> Void) {
        guard !images.isEmpty else {
            completion([])
            return
        }
        let cropVC = MomentImageCropViewController(images: images, completion: completion)
        cropVC.modalPresentationStyle = .fullScreen
        presenter.present(cropVC, animated: true)
    }

    private let images: [UIImage]
    private let completion: ([UIImage]) -> Void
    private var croppedImages: [UIImage] = []
    private var currentIndex = 0
    private var cropRect: CGRect = .zero

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let overlayView = MomentCropOverlayView()
    private let titleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let hintLabel = UILabel()

    private init(images: [UIImage], completion: @escaping ([UIImage]) -> Void) {
        self.images = images
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUI()
        showImage(at: 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        overlayView.frame = view.bounds
        let newCropRect = makeCropRect()
        guard newCropRect != cropRect else { return }
        cropRect = newCropRect
        overlayView.cropRect = newCropRect
        fitImageToCropRect()
    }

    private func setUI() {
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.addSubview(imageView)
        view.addSubview(scrollView)
        view.addSubview(overlayView)

        titleLabel.font = .fredoka(.medium, size: 18)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .fredoka(.regular, size: 16)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        hintLabel.text = "Pinch and drag to frame your photo"
        hintLabel.font = .fredoka(.regular, size: 14)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        hintLabel.textAlignment = .center

        doneButton.backgroundColor = AppColor.Punch
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.titleLabel?.font = .fredoka(.medium, size: 17)
        doneButton.layer.cornerRadius = 25
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        [titleLabel, cancelButton, hintLabel, doneButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: 8),

            doneButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            doneButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -16),
            doneButton.heightAnchor.constraint(equalToConstant: 50),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            hintLabel.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -16)
        ])
    }

    /// The largest rect with the feed photo's aspect ratio that fits between the top bar and the hint.
    private func makeCropRect() -> CGRect {
        let shape = MomentsTableViewCell.mediaSize(forRowWidth: view.bounds.width)
        let area = view.bounds.inset(by: UIEdgeInsets(top: view.safeAreaInsets.top + 64,
                                                      left: 16,
                                                      bottom: view.safeAreaInsets.bottom + 120,
                                                      right: 16))
        guard area.width > 0, area.height > 0 else { return .zero }
        let scale = min(area.width / shape.width, area.height / shape.height)
        let size = CGSize(width: (shape.width * scale).rounded(), height: (shape.height * scale).rounded())
        return CGRect(x: (area.midX - size.width / 2).rounded(),
                      y: (area.midY - size.height / 2).rounded(),
                      width: size.width,
                      height: size.height)
    }

    private func showImage(at index: Int) {
        currentIndex = index
        imageView.image = images[index]
        titleLabel.text = images.count > 1 ? "Crop photo \(index + 1) of \(images.count)" : "Crop photo"
        let isLast = index + 1 >= images.count
        doneButton.setTitle(isLast ? "Done" : "Next", for: .normal)
        fitImageToCropRect()
    }

    /// Zooms so the photo just fills the crop window, centered. The insets keep its edges outside the window.
    private func fitImageToCropRect() {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0, !cropRect.isEmpty else { return }
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = image.size

        let minScale = max(cropRect.width / image.size.width, cropRect.height / image.size.height)
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = minScale * 4
        scrollView.contentInset = UIEdgeInsets(top: cropRect.minY,
                                               left: cropRect.minX,
                                               bottom: view.bounds.height - cropRect.maxY,
                                               right: view.bounds.width - cropRect.maxX)
        scrollView.zoomScale = minScale

        let content = scrollView.contentSize
        scrollView.contentOffset = CGPoint(x: (content.width - cropRect.width) / 2 - cropRect.minX,
                                           y: (content.height - cropRect.height) / 2 - cropRect.minY)
    }

    private func cropCurrentImage() -> UIImage? {
        guard let image = imageView.image else { return nil }
        let imageBounds = CGRect(origin: .zero, size: image.size)
        let visible = imageView.convert(cropRect, from: view).intersection(imageBounds)
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: visible.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -visible.minX, y: -visible.minY))
        }
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        if let cropped = cropCurrentImage() {
            croppedImages.append(cropped)
        }
        if currentIndex + 1 < images.count {
            showImage(at: currentIndex + 1)
        } else {
            finish(with: croppedImages)
        }
    }

    @objc private func cancelTapped() {
        finish(with: [])
    }

    private func finish(with result: [UIImage]) {
        doneButton.isEnabled = false
        cancelButton.isEnabled = false
        dismiss(animated: true) { [completion] in
            completion(result)
        }
    }
}

extension MomentImageCropViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }
}

/// Dims everything outside the crop window and draws its border with a rule-of-thirds grid.
private final class MomentCropOverlayView: UIView {

    /// Matches the corner radius of the feed's photo area.
    private static let cornerRadius: CGFloat = 12

    var cropRect: CGRect = .zero {
        didSet { setNeedsLayout() }
    }

    private let dimLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor.black.withAlphaComponent(0.6).cgColor

        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        gridLayer.lineWidth = 0.5
        gridLayer.fillColor = UIColor.clear.cgColor

        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.fillColor = UIColor.clear.cgColor

        [dimLayer, gridLayer, borderLayer].forEach { layer.addSublayer($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let window = UIBezierPath(roundedRect: cropRect, cornerRadius: Self.cornerRadius)
        let dimPath = UIBezierPath(rect: bounds)
        dimPath.append(window)
        dimLayer.path = dimPath.cgPath
        borderLayer.path = window.cgPath

        let grid = UIBezierPath()
        for step in 1...2 {
            let x = cropRect.minX + cropRect.width * CGFloat(step) / 3
            grid.move(to: CGPoint(x: x, y: cropRect.minY))
            grid.addLine(to: CGPoint(x: x, y: cropRect.maxY))
            let y = cropRect.minY + cropRect.height * CGFloat(step) / 3
            grid.move(to: CGPoint(x: cropRect.minX, y: y))
            grid.addLine(to: CGPoint(x: cropRect.maxX, y: y))
        }
        gridLayer.path = grid.cgPath

        CATransaction.commit()
    }
}
