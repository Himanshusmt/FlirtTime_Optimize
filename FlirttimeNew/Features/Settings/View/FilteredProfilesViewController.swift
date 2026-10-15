//
//  FilteredProfilesViewController.swift
//  FlirttimeNew
//

import UIKit
import Combine

final class FilteredProfilesViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    @IBOutlet private weak var segmentControl: UISegmentedControl!
    @IBOutlet private weak var profilesTableView: UITableView!
    @IBOutlet private weak var emptyStateView: UIView!
    @IBOutlet private weak var emptyIconImageView: UIImageView!
    @IBOutlet private weak var emptyTitleLabel: UILabel!
    @IBOutlet private weak var emptyMessageLabel: UILabel!
    @IBOutlet private weak var loadingIndicator: UIActivityIndicatorView!

    private let viewModel = FilteredProfilesViewModel()
    private var cancellables: Set<AnyCancellable> = []

    private var hasLoaded: Bool {
        viewModel.loadedKinds.contains(kind)
    }

    private var kind: FilteredProfileKind {
        FilteredProfileKind(rawValue: segmentControl.selectedSegmentIndex) ?? .blocked
    }

    private var profiles: [FilteredProfile] {
        viewModel.profiles(for: kind)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSegmentControl()
        setBinding()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        viewModel.load()
        reload()
    }

    private func setupSegmentControl() {
        segmentControl.setTitleTextAttributes([.font: MomentsFont.scaled(.medium, 14), .foregroundColor: UIColor.white], for: .selected)
        segmentControl.setTitleTextAttributes([.font: MomentsFont.scaled(.medium, 14), .foregroundColor: AppColor.DoveGray], for: .normal)
    }

    private func setBinding() {
        Publishers.CombineLatest3(viewModel.$blocked, viewModel.$reported, viewModel.$loadedKinds)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reload()
            }.store(in: &cancellables)

        viewModel.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.aCustomToastView.show(message: message)
            }.store(in: &cancellables)
    }

    private func reload() {
        segmentControl.setTitle("Blocked (\(viewModel.count(for: .blocked)))", forSegmentAt: FilteredProfileKind.blocked.rawValue)
        segmentControl.setTitle("Reported (\(viewModel.count(for: .reported)))", forSegmentAt: FilteredProfileKind.reported.rawValue)
        if hasLoaded || !profiles.isEmpty {
            loadingIndicator.stopAnimating()
        } else {
            loadingIndicator.startAnimating()
        }
        profilesTableView.reloadData()
        let isEmpty = hasLoaded && profiles.isEmpty
        emptyStateView.isHidden = !isEmpty
        guard isEmpty else { return }
        switch kind {
        case .blocked:
            emptyIconImageView.image = UIImage(systemName: "hand.raised.fill")
            emptyTitleLabel.text = "No blocked profiles"
            emptyMessageLabel.text = "People you block won't see your profile or be able to message you."
        case .reported:
            emptyIconImageView.image = UIImage(systemName: "flag.fill")
            emptyTitleLabel.text = "No reports yet"
            emptyMessageLabel.text = "Profiles you report will show up here while our team reviews them."
        }
    }

    private func confirmUnblock(_ profile: FilteredProfile) {
        aDeleteCustomPopUp.show(message: Constants.UnblockType.unblockMessage + profile.name + "?",
                                button1Text: Constants.AlertButtons.cancel,
                                button2Text: Constants.AlertButtons.okay) { [weak self] in
            self?.viewModel.unblock(profile) { [weak self] success in
                guard success else { return }
                self?.aCustomToastView.show(message: "\(profile.name) has been unblocked")
            }
        }
    }

    // MARK: - Actions

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func segmentChanged(_ sender: UISegmentedControl) {
        UISelectionFeedbackGenerator().selectionChanged()
        reload()
    }
}

extension FilteredProfilesViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        profiles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: FilteredProfileCell.identifier, for: indexPath) as? FilteredProfileCell else {
            return UITableViewCell()
        }
        let profile = profiles[indexPath.row]
        cell.configure(with: profile, kind: kind)
        cell.onAction = { [weak self] in self?.confirmUnblock(profile) }
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= profiles.count - 3 {
            viewModel.loadMore(kind)
        }
    }
}
