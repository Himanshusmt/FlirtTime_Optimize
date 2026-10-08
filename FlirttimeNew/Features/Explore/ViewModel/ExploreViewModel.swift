//
//  ExploreViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 21/05/24.
//
import Foundation
import UIKit

// TODO: replace the MockPeople responses with ApiName.getUserInteractions / getMatchList /
// getComplimentList / readCompliment / getStatusCount requests.
class ExploreViewModel  {

    @Published var aUserInteraction:InteractionResponse?
    @Published var errorMessage:String?
    @Published var aMyLikeResponse:MyLikeInteractionResponse?
    @Published var errorMyLikeMessage:String?
    @Published var aComplimentListResponse: ComplimentListResponse?
    @Published var aReadComplimentResponse: ReadComplimentResponse?

    @Published var aMyMatches:MatchResponse?
    @Published var errorMyMatches:String?
    @Published var errorCompliment: String?
    @Published var errorReadCompliment: String?
    @Published var globleArray: [MyLikeInteractionResponse] = []
    @Published var getStatusCount:GetCountModel?

    private let store = MockDataStore.shared

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    private func interactionJSON(index: Int, person: MockPerson, type: Int, userInfoKey: String, incoming: Bool) -> [String: Any] {
        let me = store.currentUserID
        return [
            "id": 500 + index,
            "user_id": incoming ? person.id : me,
            "to_user_id": incoming ? me : person.id,
            "interaction_type": type,
            "created_at": "2026-10-0\(index + 1) 10:00:00",
            "updated_at": "2026-10-0\(index + 1) 10:00:00",
            userInfoKey: MockPeople.userInfoJSON(person)
        ]
    }

    private var complimentsJSON: [[String: Any]] {
        MockPeople.complimentSenders.enumerated().compactMap { index, entry in
            guard let person = MockPeople.person(id: entry.id) else { return nil }
            return [
                "id": 700 + index,
                "sender_id": person.id,
                "receiver_id": store.currentUserID,
                "content": entry.text,
                "is_read": 0,
                "created_at": "2026-10-0\(index + 1) 10:00:00",
                "updated_at": "2026-10-0\(index + 1) 10:00:00",
                "sender": MockPeople.senderProfileJSON(person)
            ]
        }
    }
}

extension ExploreViewModel {

    func getUserIneractionMyLikeAPI(interactioType: String) {
        respond { [weak self] in
            guard let self = self else { return }
            let data: [[String: Any]] = MockPeople.youLikedIDs.enumerated().compactMap { index, entry in
                guard let person = MockPeople.person(id: entry.id) else { return nil }
                return self.interactionJSON(index: index, person: person, type: entry.superLike ? 2 : 1, userInfoKey: "to_user_info", incoming: false)
            }
            let payload: [String: Any] = ["status": true, "message": "", "data": data, "img_base_url": ApiName.imgBaseURL]
            if let model = self.store.decode(MyLikeInteractionResponse.self, from: payload) {
                self.aMyLikeResponse = model
            } else {
                self.errorMyLikeMessage = "Unable to load likes"
            }
        }
    }

    func getUserIneractionAPI(interactioType: String) {
        respond { [weak self] in
            guard let self = self else { return }
            let data: [[String: Any]] = MockPeople.likesYouIDs.enumerated().compactMap { index, id in
                guard let person = MockPeople.person(id: id) else { return nil }
                return self.interactionJSON(index: index, person: person, type: 1, userInfoKey: "user_info", incoming: true)
            }
            let payload: [String: Any] = ["status": true, "message": "", "data": data, "img_base_url": ApiName.imgBaseURL]
            if let model = self.store.decode(InteractionResponse.self, from: payload) {
                self.aUserInteraction = model
            } else {
                self.errorMessage = "Unable to load likes"
            }
        }
    }

    func getUserMatchesAPI() {
        respond { [weak self] in
            guard let self = self else { return }
            let data = MockPeople.matchIDs.compactMap(MockPeople.person(id:)).map(MockPeople.matchedUserJSON)
            let payload: [String: Any] = ["status": true, "message": "", "data": data]
            if let model = self.store.decode(MatchResponse.self, from: payload) {
                self.aMyMatches = model
            } else {
                self.errorMyMatches = "Unable to load matches"
            }
        }
    }

    func getComplimentListApi() {
        respond { [weak self] in
            guard let self = self else { return }
            let compliments = self.complimentsJSON
            let payload: [String: Any] = [
                "status": true,
                "message": "",
                "img_base_url": ApiName.imgBaseURL,
                "data": [
                    "current_page": 1,
                    "data": compliments,
                    "first_page_url": "",
                    "from": 1,
                    "last_page": 1,
                    "last_page_url": "",
                    "links": [],
                    "path": "",
                    "per_page": 20,
                    "to": compliments.count,
                    "total": compliments.count
                ]
            ]
            if let model = self.store.decode(ComplimentListResponse.self, from: payload) {
                self.aComplimentListResponse = model
            } else {
                self.errorCompliment = "Unable to load compliments"
            }
        }
    }

    func readComplimentApi(id: Int) {
        respond { [weak self] in
            guard let self = self else { return }
            guard var compliment = self.complimentsJSON.first(where: { $0["id"] as? Int == id }) else {
                self.errorReadCompliment = "Compliment data not found"
                return
            }
            compliment["sender"] = nil
            compliment["is_read"] = 1
            let payload: [String: Any] = ["status": true, "message": "", "data": compliment, "img_base_url": ApiName.imgBaseURL]
            self.aReadComplimentResponse = self.store.decode(ReadComplimentResponse.self, from: payload)
        }
    }

    func getStatucCountApi() {
        respond { [weak self] in
            guard let self = self else { return }
            let superLikes = MockPeople.youLikedIDs.filter(\.superLike).count
            let payload: [String: Any] = [
                "status": true,
                "message": "",
                "img_base_url": ApiName.imgBaseURL,
                "data": [
                    "like_count": MockPeople.likesYouIDs.count,
                    "like_you_count": MockPeople.youLikedIDs.count - superLikes,
                    "favorite_count": superLikes,
                    "favorite_you_count": 0,
                    "match_count": MockPeople.matchIDs.count,
                    "compliment_count": MockPeople.complimentSenders.count
                ]
            ]
            self.getStatusCount = self.store.decode(GetCountModel.self, from: payload)
        }
    }
}
