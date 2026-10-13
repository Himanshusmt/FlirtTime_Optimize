//
//  FilteredProfilesViewModel.swift
//  FlirttimeNew
//

import Foundation

// TODO: replace the local block / report lists with the blocked-user list and unblock endpoints.
final class FilteredProfilesViewModel {

    @Published private(set) var blocked: [FilteredProfile] = []
    @Published private(set) var reported: [FilteredProfile] = []

    func load() {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            guard let self else { return }
            let chatBlocked = BlockedUsersManager.shared.blockedUserIDs.compactMap(Int.init)
            let blockedIDs = Set(chatBlocked).union(MockDiscover.shared.blockedUserIDs)
            self.blocked = blockedIDs.sorted().map(Self.profile)
            self.reported = MockDiscover.shared.reportedUserIDs.sorted().map(Self.profile)
        }
    }

    func profiles(for kind: FilteredProfileKind) -> [FilteredProfile] {
        kind == .blocked ? blocked : reported
    }

    func unblock(_ profile: FilteredProfile) {
        BlockedUsersManager.shared.unblockUser(id: String(profile.userID))
        MockDiscover.shared.unblock(userID: profile.userID)
        blocked.removeAll { $0.userID == profile.userID }
    }

    private static func profile(for userID: Int) -> FilteredProfile {
        guard let person = MockPeople.person(id: userID) else {
            return FilteredProfile(userID: userID, name: "Flirt Time member", photo: nil, location: nil)
        }
        return FilteredProfile(userID: userID, name: person.displayName, photo: person.photos.first, location: person.location)
    }
}
