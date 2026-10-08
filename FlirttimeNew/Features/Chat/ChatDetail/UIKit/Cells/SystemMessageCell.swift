import UIKit

// MARK: - System Message Cell

final class SystemMessageCell: UICollectionViewCell {

    static let cellId = "SystemMessageCell"

    private let label: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(size: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let capsuleView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.1)
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        contentView.addSubview(capsuleView)
        capsuleView.addSubview(label)

        NSLayoutConstraint.activate([
            capsuleView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            capsuleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            capsuleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            capsuleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75),

            label.topAnchor.constraint(equalTo: capsuleView.topAnchor, constant: 6),
            label.leftAnchor.constraint(equalTo: capsuleView.leftAnchor, constant: 12),
            label.rightAnchor.constraint(equalTo: capsuleView.rightAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor, constant: -6),
        ])
    }

    func configure(text: String) {
        label.text = text
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = capsuleView.frame.height
        capsuleView.layer.cornerRadius = height > 0 ? height / 2 : 14
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.text = nil
    }
}
