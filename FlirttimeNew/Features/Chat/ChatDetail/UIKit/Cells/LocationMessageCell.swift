import UIKit
import CoreLocation

final class LocationMessageCell: BaseMessageCell {

    static let cellId = "LocationMessageCell"

    private let mapImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 14
        iv.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        iv.backgroundColor = ChatTheme.surface
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let locationIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(named: ChatAssets.location)?.withRenderingMode(.alwaysTemplate))
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = ChatStrings.chat_locationContent.localizedString()
        label.font = UIFont.chat(.medium, size: 14)
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(size: 13)
        label.numberOfLines = 2
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let centerPinImageView: UIImageView = {
        let iv = UIImageView(image: UIImage(named: ChatAssets.location)?.withRenderingMode(.alwaysTemplate))
        iv.tintColor = ChatTheme.primary
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.layer.shadowColor = UIColor.black.cgColor
        iv.layer.shadowOpacity = 0.25
        iv.layer.shadowRadius = 3
        iv.layer.shadowOffset = CGSize(width: 0, height: 1)
        return iv
    }()

    private var snapshotTask: Task<Void, Never>?
    private var geocodeTask: Task<Void, Never>?
    private var secondaryTextColor: UIColor = ChatTheme.textSecondary

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContentArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContentArea()
    }

    private func setupContentArea() {
        contentArea.addSubview(mapImageView)
        contentArea.addSubview(locationIcon)
        contentArea.addSubview(titleLabel)
        contentArea.addSubview(addressLabel)
        contentArea.addSubview(centerPinImageView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleMapTap))
        contentArea.addGestureRecognizer(tap)
        contentArea.isUserInteractionEnabled = true

        NSLayoutConstraint.activate([
            mapImageView.topAnchor.constraint(equalTo: contentArea.topAnchor),
            mapImageView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            mapImageView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            mapImageView.heightAnchor.constraint(equalToConstant: MessageCellMetrics.locationMapHeight),

            centerPinImageView.centerXAnchor.constraint(equalTo: mapImageView.centerXAnchor),
            centerPinImageView.bottomAnchor.constraint(equalTo: mapImageView.centerYAnchor),
            centerPinImageView.widthAnchor.constraint(equalToConstant: 32),
            centerPinImageView.heightAnchor.constraint(equalToConstant: 32),

            locationIcon.topAnchor.constraint(equalTo: mapImageView.bottomAnchor, constant: 10),
            locationIcon.leftAnchor.constraint(equalTo: contentArea.leftAnchor, constant: 12),
            locationIcon.widthAnchor.constraint(equalToConstant: 16),
            locationIcon.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.centerYAnchor.constraint(equalTo: locationIcon.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: locationIcon.trailingAnchor, constant: 6),
            titleLabel.rightAnchor.constraint(equalTo: contentArea.rightAnchor, constant: -12),

            addressLabel.topAnchor.constraint(equalTo: locationIcon.bottomAnchor, constant: 6),
            addressLabel.leftAnchor.constraint(equalTo: contentArea.leftAnchor, constant: 12),
            addressLabel.rightAnchor.constraint(equalTo: contentArea.rightAnchor, constant: -12),
            addressLabel.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor, constant: -10),
        ])
    }

    override func configureContent(with model: MessageCellModel) {
        guard let location = model.locationData else { return }

        let lat = location.lat ?? 0
        let lon = location.lng ?? 0

        if let address = location.address, !address.isEmpty {
            addressLabel.text = address
            addressLabel.textColor = secondaryTextColor
        } else {
            addressLabel.text = ChatStrings.chat_gettingAddress.localizedString()
            addressLabel.textColor = secondaryTextColor.withAlphaComponent(0.6)
            reverseGeocode(lat: lat, lng: lon)
        }

        if let cached = MapSnapshotCache.shared.memGet(lat: lat, lng: lon)
            ?? MapSnapshotCache.shared.diskGet(lat: lat, lng: lon) {
            mapImageView.image = cached
            snapshotTask?.cancel()
            snapshotTask = nil
            return
        }

        mapImageView.image = nil
        snapshotTask?.cancel()
        let stableId = model.stableId
        snapshotTask = Task { [weak self] in
            guard let image = await MapSnapshotCache.shared.generate(lat: lat, lng: lon) else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.cellModel?.stableId == stableId else { return }
                UIView.transition(with: self.mapImageView, duration: 0.25, options: .transitionCrossDissolve) {
                    self.mapImageView.image = image
                }
            }
        }
    }

    private func reverseGeocode(lat: Double, lng: Double) {
        geocodeTask?.cancel()
        geocodeTask = Task { [weak self] in
            let location = CLLocation(latitude: lat, longitude: lng)
            guard let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
                  let placemark = placemarks.first else { return }
            guard !Task.isCancelled else { return }
            let parts = [placemark.name, placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            let address = parts.prefix(3).joined(separator: ", ")
            guard !address.isEmpty else { return }
            await MainActor.run {
                guard let self else { return }
                self.addressLabel.text = address
                self.addressLabel.textColor = self.secondaryTextColor
            }
        }
    }

    override func configureBubbleAppearance(model: MessageCellModel) {
        setBubbleContentInsets(top: 0, horizontal: 0, bottom: 0)
        bubbleContainer.backgroundColor = model.isIncoming ? ChatTheme.incomingBubble : ChatTheme.outgoingBubble
        bubbleContainer.layer.cornerRadius = 14
        bubbleContainer.clipsToBounds = true

        let textColor = model.isIncoming ? ChatTheme.incomingText : ChatTheme.outgoingText
        secondaryTextColor = model.isIncoming ? ChatTheme.textSecondary : ChatTheme.outgoingText.withAlphaComponent(0.85)
        titleLabel.textColor = textColor
        addressLabel.textColor = secondaryTextColor
        locationIcon.tintColor = model.isIncoming ? ChatTheme.primary : ChatTheme.outgoingText

        if model.replyPreview != nil {
            wrapInReplyBubble(model: model, innerInsets: 6)
        }
    }

    @objc private func handleMapTap() {
        guard let model = cellModel else { return }
        actionsDelegate?.cellDidTapLocation(self, model: model)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        snapshotTask?.cancel()
        snapshotTask = nil
        geocodeTask?.cancel()
        geocodeTask = nil
        mapImageView.image = nil
        addressLabel.text = nil
    }
}
