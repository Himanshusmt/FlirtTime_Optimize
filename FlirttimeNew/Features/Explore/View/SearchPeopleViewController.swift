//
//  SearchPeopleViewController.swift
//  FlirttimeNew
//
//  The whole layout (top bar, search bar, profile grid, empty state) lives in
//  SearchPeople.storyboard; this class only fills it with data and handles input.
//

import UIKit
import Combine

final class SearchPeopleViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.searchPeople
    }

    @IBOutlet private weak var searchBarView: UIView!
    @IBOutlet private weak var searchTextField: UITextField!
    @IBOutlet private weak var clearButton: UIButton!
    @IBOutlet private weak var resultsLabel: UILabel!
    @IBOutlet private weak var peopleCollectionView: UICollectionView!
    @IBOutlet private weak var emptyStateView: UIView!
    @IBOutlet private weak var emptyTitleLabel: UILabel!
    @IBOutlet private weak var emptyMessageLabel: UILabel!
    @IBOutlet private weak var loadingIndicator: UIActivityIndicatorView!

    private let viewModel = SearchPeopleViewModel()
    private var cancellables: Set<AnyCancellable> = []
    private var people: [UserSearchResult] = []

    private var typedText: String {
        searchTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setBinding()
        setupSearchBar()
        updateSearchBarFocus(false)
        render()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if people.isEmpty && typedText.isEmpty {
            searchTextField.becomeFirstResponder()
        }
    }

    private func setBinding() {
        Publishers.Merge3(viewModel.$people.map { _ in () },
                          viewModel.$isLoading.map { _ in () },
                          viewModel.$errorMessage.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
    }

    private func render() {
        let isSearching = !typedText.isEmpty
        let isLoading = viewModel.isLoading
        if people.count != viewModel.people.count || people.map(\.userId) != viewModel.people.map(\.userId) {
            people = viewModel.people
            peopleCollectionView.reloadData()
        }

        if isLoading && people.isEmpty {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }

        let query = viewModel.query
        let count = people.count
        resultsLabel.text = count == 1 ? "1 result for \u{201C}\(query)\u{201D}" : "\(count) results for \u{201C}\(query)\u{201D}"
        resultsLabel.isHidden = !isSearching || query.isEmpty || (isLoading && count == 0)

        let showsEmptyState = !isLoading && count == 0
        emptyStateView.isHidden = !showsEmptyState
        if showsEmptyState {
            if !isSearching {
                emptyTitleLabel.text = "Find someone special"
                emptyMessageLabel.text = "Search by name or city to find people."
            } else if let error = viewModel.errorMessage {
                emptyTitleLabel.text = "Something went wrong"
                emptyMessageLabel.text = error
            } else {
                emptyTitleLabel.text = "No people found"
                emptyMessageLabel.text = "Try a different name or city to find someone special."
            }
        }
        clearButton.isHidden = searchTextField.text?.isEmpty ?? true
    }

    private func setupSearchBar() {
        searchBarView.backgroundColor = .white
        searchBarView.layer.shadowColor = AppColor.AppBlack.cgColor
        searchBarView.layer.shadowOpacity = 0.08
        searchBarView.layer.shadowRadius = 10
        searchBarView.layer.shadowOffset = CGSize(width: 0, height: 4)
        searchTextField.textColor = AppColor.MineShaft
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: searchTextField.placeholder ?? "Search by name or city",
            attributes: [.foregroundColor: AppColor.Boulder]
        )
    }

    private func updateSearchBarFocus(_ focused: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.searchBarView.layer.borderColor = (focused ? AppColor.Punch : AppColor.Silver).cgColor
        }
    }

    private func openProfile(_ person: UserSearchResult) {
        let seed = OtherUserProfileRouter.Seed(userID: person.userId,
                                               name: person.displayName,
                                               avatar: person.profilePhoto,
                                               location: person.city,
                                               age: person.age,
                                               isVerified: person.isVerified == true,
                                               isOnline: person.isOnline == true)
        OtherUserProfileRouter.open(seed, from: self)
    }

    // MARK: - Actions

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func searchTextChanged(_ sender: UITextField) {
        viewModel.search(sender.text ?? "")
        render()
    }

    @IBAction private func clearButtonTapped(_ sender: UIButton) {
        searchTextField.text = nil
        viewModel.search("")
        render()
        searchTextField.becomeFirstResponder()
    }
}

extension SearchPeopleViewController: UITextFieldDelegate {

    func textFieldDidBeginEditing(_ textField: UITextField) {
        updateSearchBarFocus(true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        updateSearchBarFocus(false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension SearchPeopleViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        people.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SearchPeopleCell.identifier, for: indexPath) as? SearchPeopleCell else {
            return UICollectionViewCell()
        }
        cell.configure(with: people[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= people.count - 4 {
            viewModel.loadMoreIfNeeded()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        searchTextField.resignFirstResponder()
        openProfile(people[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else { return .zero }
        let itemsPerRow: CGFloat = 2
        let padding = flowLayout.sectionInset.left + flowLayout.sectionInset.right + flowLayout.minimumInteritemSpacing * (itemsPerRow - 1)
        let width = floor((collectionView.bounds.width - padding) / itemsPerRow)
        return CGSize(width: width, height: (width * 1.38).rounded())
    }
}
