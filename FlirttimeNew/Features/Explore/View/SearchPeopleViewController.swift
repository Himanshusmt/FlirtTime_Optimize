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
    private var allPeople: [UserDetailInfo] = []
    private var filteredPeople: [UserDetailInfo] = []
    private var hasLoaded = false

    private static let dobFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var query: String {
        searchTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setBinding()
        updateSearchBarFocus(false)
        loadingIndicator.startAnimating()
        viewModel.getPeople()
    }

    private func setBinding() {
        viewModel.$people.receive(on: DispatchQueue.main).sink { [weak self] people in
            guard let self, let people else { return }
            self.hasLoaded = true
            self.allPeople = people
            self.applySearch()
        }.store(in: &cancellables)

        viewModel.$errorMessage.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self, error != nil else { return }
            self.hasLoaded = true
            self.allPeople = []
            self.applySearch()
        }.store(in: &cancellables)
    }

    private func applySearch() {
        filteredPeople = SearchPeopleViewModel.filter(allPeople, query: query)
        loadingIndicator.stopAnimating()
        peopleCollectionView.reloadData()

        let count = filteredPeople.count
        if query.isEmpty {
            resultsLabel.text = count == 1 ? "1 person to discover" : "\(count) people to discover"
        } else {
            resultsLabel.text = count == 1 ? "1 result for \u{201C}\(query)\u{201D}" : "\(count) results for \u{201C}\(query)\u{201D}"
        }
        resultsLabel.isHidden = !hasLoaded

        let isEmpty = hasLoaded && count == 0
        emptyStateView.isHidden = !isEmpty
        if isEmpty {
            emptyTitleLabel.text = query.isEmpty ? "No one here yet" : "No people found"
            emptyMessageLabel.text = query.isEmpty
                ? "Check back soon, new people join every day."
                : "Try a different name or city to find someone special."
        }
        clearButton.isHidden = searchTextField.text?.isEmpty ?? true
    }

    private func updateSearchBarFocus(_ focused: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.searchBarView.layer.borderColor = (focused ? AppColor.Punch : AppColor.AthensGray).cgColor
            self.searchBarView.backgroundColor = focused ? .white : AppColor.AthensGray
        }
    }

    private func age(from dob: String?) -> Int? {
        guard let dob, let birthDate = Self.dobFormatter.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    // MARK: - Actions

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func searchTextChanged(_ sender: UITextField) {
        applySearch()
    }

    @IBAction private func clearButtonTapped(_ sender: UIButton) {
        searchTextField.text = nil
        applySearch()
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
        filteredPeople.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SearchPeopleCell.identifier, for: indexPath) as? SearchPeopleCell else {
            return UICollectionViewCell()
        }
        let person = filteredPeople[indexPath.item]
        cell.configure(with: person, age: age(from: person.dob))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        searchTextField.resignFirstResponder()
        let profileViewController: OtherUserProfileViewController = OtherUserProfileViewController.instantiateFromStoryboard()
        profileViewController.userDetailInfo = filteredPeople[indexPath.item]
        navigationController?.pushViewController(profileViewController, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else { return .zero }
        let itemsPerRow: CGFloat = 2
        let padding = flowLayout.sectionInset.left + flowLayout.sectionInset.right + flowLayout.minimumInteritemSpacing * (itemsPerRow - 1)
        let width = floor((collectionView.bounds.width - padding) / itemsPerRow)
        return CGSize(width: width, height: (width * 1.38).rounded())
    }
}
