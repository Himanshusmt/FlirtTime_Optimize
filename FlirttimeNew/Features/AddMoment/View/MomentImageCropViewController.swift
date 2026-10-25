//
//  MomentImageCropViewController.swift
//  FlirttimeNew
//
//  Crops photos picked on Add Moment. The default window matches the feed photo area
//  (`MomentsTableViewCell.mediaSize`). Drag the corners or edges to resize it.
//

import UIKit

private enum CropHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case move
}

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
    private var hasCustomCrop = false

    private var activeHandle: CropHandle?
    private var resizeStartCrop: CGRect = .zero
    private var resizeStartPoint: CGPoint = .zero

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let overlayView = MomentCropOverlayView()
    private let titleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let hintLabel = UILabel()

    /// Smallest crop window: the feed photo card. Cannot crop smaller than that.

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
        let area = croppableArea()
        if !hasCustomCrop {
            let newCropRect = makeDefaultCropRect(in: area)
            guard newCropRect != cropRect else { return }
            cropRect = newCropRect
            overlayView.cropRect = newCropRect
            syncScrollViewToCropRect(resetZoom: true)
        } else {
            let clamped = clamp(cropRect, to: area)
            guard clamped != cropRect else { return }
            cropRect = clamped
            overlayView.cropRect = clamped
            syncScrollViewToCropRect(resetZoom: false)
        }
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

        let pan = UIPanGestureRecognizer(target: self, action: #selector(overlayPanned(_:)))
        pan.maximumNumberOfTouches = 1
        overlayView.addGestureRecognizer(pan)

        titleLabel.font = .fredoka(.medium, size: 18)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .fredoka(.regular, size: 16)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        hintLabel.text = "Drag corners to resize · pinch to zoom"
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

    /// Space between the top bar and the hint, where the crop window can live.
    private func croppableArea() -> CGRect {
        view.bounds.inset(by: UIEdgeInsets(top: view.safeAreaInsets.top + 64,
                                           left: 16,
                                           bottom: view.safeAreaInsets.bottom + 120,
                                           right: 16))
    }

    /// The largest rect with the feed photo's aspect, 100 pt taller, that fits in `area`.
    private func makeDefaultCropRect(in area: CGRect) -> CGRect {
        let feed = MomentsTableViewCell.mediaSize(forRowWidth: view.bounds.width)
        let shape = CGSize(width: feed.width, height: feed.height + 100)
        guard area.width > 0, area.height > 0, shape.width > 0, shape.height > 0 else { return .zero }
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
        syncScrollViewToCropRect(resetZoom: true)
    }

    /// Keeps the photo covering the crop window. `resetZoom` recenters and fits; otherwise zoom/offset stay put.
    private func syncScrollViewToCropRect(resetZoom: Bool) {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0, !cropRect.isEmpty else { return }
        if resetZoom {
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: image.size)
            scrollView.contentSize = image.size
        }

        let minScale = max(cropRect.width / image.size.width, cropRect.height / image.size.height)
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = minScale * 4
        scrollView.contentInset = UIEdgeInsets(top: cropRect.minY,
                                               left: cropRect.minX,
                                               bottom: view.bounds.height - cropRect.maxY,
                                               right: view.bounds.width - cropRect.maxX)
        if resetZoom || scrollView.zoomScale < minScale {
            scrollView.zoomScale = minScale
        }

        if resetZoom {
            let content = scrollView.contentSize
            scrollView.contentOffset = CGPoint(x: (content.width - cropRect.width) / 2 - cropRect.minX,
                                               y: (content.height - cropRect.height) / 2 - cropRect.minY)
        } else {
            clampContentOffsetToCropRect()
        }
    }

    private func clampContentOffsetToCropRect() {
        let content = scrollView.contentSize
        var offset = scrollView.contentOffset
        let minX = -cropRect.minX
        let minY = -cropRect.minY
        let maxX = max(minX, content.width - cropRect.width - cropRect.minX)
        let maxY = max(minY, content.height - cropRect.height - cropRect.minY)
        offset.x = min(max(offset.x, minX), maxX)
        offset.y = min(max(offset.y, minY), maxY)
        scrollView.contentOffset = offset
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

    // MARK: - Resize

    @objc private func overlayPanned(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: view)
        switch gesture.state {
        case .began:
            activeHandle = overlayView.handle(at: point)
            resizeStartCrop = cropRect
            resizeStartPoint = point
        case .changed:
            guard let handle = activeHandle else { return }
            let translation = CGPoint(x: point.x - resizeStartPoint.x, y: point.y - resizeStartPoint.y)
            let next = resized(resizeStartCrop, handle: handle, translation: translation, in: croppableArea())
            guard next != cropRect else { return }
            cropRect = next
            overlayView.cropRect = next
            hasCustomCrop = true
            syncScrollViewToCropRect(resetZoom: false)
        default:
            activeHandle = nil
        }
    }

    private func resized(_ start: CGRect, handle: CropHandle, translation: CGPoint, in area: CGRect) -> CGRect {
        if handle == .move {
            let x = min(max(start.minX + translation.x, area.minX), area.maxX - start.width)
            let y = min(max(start.minY + translation.y, area.minY), area.maxY - start.height)
            return CGRect(x: x.rounded(), y: y.rounded(), width: start.width, height: start.height)
        }

        var minX = start.minX
        var maxX = start.maxX
        var minY = start.minY
        var maxY = start.maxY

        switch handle {
        case .topLeft:
            minX += translation.x
            minY += translation.y
        case .topRight:
            maxX += translation.x
            minY += translation.y
        case .bottomLeft:
            minX += translation.x
            maxY += translation.y
        case .bottomRight:
            maxX += translation.x
            maxY += translation.y
        case .top:
            minY += translation.y
        case .bottom:
            maxY += translation.y
        case .left:
            minX += translation.x
        case .right:
            maxX += translation.x
        case .move:
            break
        }

        let minSize = minCropSize(in: area)
        minX = min(max(minX, area.minX), maxX - minSize.width)
        maxX = max(min(maxX, area.maxX), minX + minSize.width)
        minY = min(max(minY, area.minY), maxY - minSize.height)
        maxY = max(min(maxY, area.maxY), minY + minSize.height)
        minX = max(minX, area.minX)
        maxX = min(maxX, area.maxX)
        minY = max(minY, area.minY)
        maxY = min(maxY, area.maxY)
        if maxX - minX < minSize.width || maxY - minY < minSize.height { return start }
        return CGRect(x: minX.rounded(), y: minY.rounded(), width: (maxX - minX).rounded(), height: (maxY - minY).rounded())
    }

    /// Feed photo size, limited to the space available on the cropper.
    private func minCropSize(in area: CGRect) -> CGSize {
        let cell = MomentsTableViewCell.displayMediaSize(forRowWidth: view.bounds.width)
        return CGSize(width: min(cell.width, area.width), height: min(cell.height, area.height))
    }

    private func clamp(_ rect: CGRect, to area: CGRect) -> CGRect {
        let minSize = minCropSize(in: area)
        guard !rect.isEmpty, area.width >= minSize.width, area.height >= minSize.height else { return rect }
        var r = rect
        r.size.width = min(max(r.width, minSize.width), area.width)
        r.size.height = min(max(r.height, minSize.height), area.height)
        r.origin.x = min(max(r.origin.x, area.minX), area.maxX - r.width)
        r.origin.y = min(max(r.origin.y, area.minY), area.maxY - r.height)
        return r
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

/// Dims everything outside the crop window and draws its border, grid, and resize handles.
private final class MomentCropOverlayView: UIView {

    /// Matches the corner radius of the feed's photo area.
    private static let cornerRadius: CGFloat = 12
    private static let handleLength: CGFloat = 24
    private static let handleSlop: CGFloat = 28
    private static let edgeSlop: CGFloat = 22
    private static let moveSlop: CGFloat = 18

    var cropRect: CGRect = .zero {
        didSet { setNeedsLayout() }
    }

    private let dimLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor.black.withAlphaComponent(0.6).cgColor

        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        gridLayer.lineWidth = 0.5
        gridLayer.fillColor = UIColor.clear.cgColor

        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.fillColor = UIColor.clear.cgColor

        handleLayer.strokeColor = UIColor.white.cgColor
        handleLayer.lineWidth = 4
        handleLayer.lineCap = .square
        handleLayer.lineJoin = .miter
        handleLayer.fillColor = UIColor.clear.cgColor

        [dimLayer, gridLayer, borderLayer, handleLayer].forEach { layer.addSublayer($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Only the handles and the crop frame receive touches, so pinch/drag still reach the photo.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        handle(at: point) != nil
    }

    func handle(at point: CGPoint) -> CropHandle? {
        guard !cropRect.isEmpty else { return nil }
        let corners: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: cropRect.minX, y: cropRect.minY)),
            (.topRight, CGPoint(x: cropRect.maxX, y: cropRect.minY)),
            (.bottomLeft, CGPoint(x: cropRect.minX, y: cropRect.maxY)),
            (.bottomRight, CGPoint(x: cropRect.maxX, y: cropRect.maxY))
        ]
        if let match = corners.first(where: { hypot(point.x - $0.1.x, point.y - $0.1.y) <= Self.handleSlop }) {
            return match.0
        }

        let edgeHit = Self.edgeSlop
        if abs(point.y - cropRect.minY) <= edgeHit, (cropRect.minX...cropRect.maxX).contains(point.x) { return .top }
        if abs(point.y - cropRect.maxY) <= edgeHit, (cropRect.minX...cropRect.maxX).contains(point.x) { return .bottom }
        if abs(point.x - cropRect.minX) <= edgeHit, (cropRect.minY...cropRect.maxY).contains(point.y) { return .left }
        if abs(point.x - cropRect.maxX) <= edgeHit, (cropRect.minY...cropRect.maxY).contains(point.y) { return .right }

        let expanded = cropRect.insetBy(dx: -Self.moveSlop, dy: -Self.moveSlop)
        let inner = cropRect.insetBy(dx: Self.moveSlop, dy: Self.moveSlop)
        if expanded.contains(point) && !inner.contains(point) {
            return .move
        }
        return nil
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
        handleLayer.path = handlePath(in: cropRect).cgPath

        CATransaction.commit()
    }

    private func handlePath(in rect: CGRect) -> UIBezierPath {
        let length = Self.handleLength
        let path = UIBezierPath()
        func corner(_ origin: CGPoint, dx: CGFloat, dy: CGFloat) {
            path.move(to: CGPoint(x: origin.x, y: origin.y + dy))
            path.addLine(to: origin)
            path.addLine(to: CGPoint(x: origin.x + dx, y: origin.y))
        }
        corner(CGPoint(x: rect.minX, y: rect.minY), dx: length, dy: length)
        corner(CGPoint(x: rect.maxX, y: rect.minY), dx: -length, dy: length)
        corner(CGPoint(x: rect.minX, y: rect.maxY), dx: length, dy: -length)
        corner(CGPoint(x: rect.maxX, y: rect.maxY), dx: -length, dy: -length)
        return path
    }
}
