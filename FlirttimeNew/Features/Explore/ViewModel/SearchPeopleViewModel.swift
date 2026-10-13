//
//  SearchPeopleViewModel.swift
//  FlirttimeNew
//

import Foundation

// TODO: replace the MockPeople response with the real people search API.
final class SearchPeopleViewModel {

    @Published var people: [UserDetailInfo]?
    @Published var errorMessage: String?

    private let store = MockDataStore.shared

    func getPeople() {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            guard let self else { return }
            let payload = MockPeople.all.map(MockPeople.userInfoJSON)
            if let people = self.store.decode([UserDetailInfo].self, from: payload) {
                self.people = people
            } else {
                self.errorMessage = "Unable to load people"
            }
        }
    }

    static func filter(_ people: [UserDetailInfo], query: String) -> [UserDetailInfo] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        guard !terms.isEmpty else { return people }

        return people.filter { person in
            let searchable = [person.displayName, person.fullname, person.location]
                .compactMap { $0 }
                .joined(separator: " ")
            return terms.allSatisfy { searchable.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
