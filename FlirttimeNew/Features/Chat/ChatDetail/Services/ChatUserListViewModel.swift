//
//  ChatUserListViewModel.swift
//  FlirttimeNew
//

import Foundation
import Swinject
import RxSwift

protocol ChatUserListViewModelDelegate: AnyObject {
    func didReceiveData()
    func didReceiveError()
    func didDeleteChat()
    func didDeleteMessage()
    func didFailedToDeleteMessage()
    func didFailedToDelete()
    func didReportChat()
    func didIsBlockedUser()
    func didBlockUser()
    func didUnBlockUser()
    func didFailedToBlockUser()
    func didFailedToUnBlockUser()
    func didReceiveUnauthorizedError(_ message:String,_ statusCode:String)
}

class ChatUserListViewModel {
    
    var sessionManager: SessionManager?
    let defaults = BetterUserDefaults(defaults: UserDefaults.standard)
    let disposeBag = DisposeBag()
    var errorMessage: String? = nil
    weak var delegate: ChatUserListViewModelDelegate?
    var menuActions = [Dictionary<String, Any>]()
    var isBlocked: Bool?
    
    init() {
        sessionManager = Container.sharedContainer.resolve(SessionManager.self)
    }
    
    func getReportReasons() {
        _ = sessionManager?.getReportUserReasons()
            .subscribe(onSuccess: { response in
                self.menuActions = response.reasons.map { key, value in
                    return ["key": key, "title": value]
                }
            }, onFailure: { error in
                print("Error:", error)
            })
            .disposed(by: disposeBag)
    }
    
    func reportUser(userID:String, reason:String){
        _ = sessionManager?.reportuser(userID: userID, reason: reason)
            .subscribe(onSuccess: { postResponse in
                self.delegate?.didReportChat()
            }, onFailure: { _ in
            })
            .disposed(by: disposeBag)
    }
    
    func checkuserBlocked(id:String, userID:String){
        _ = sessionManager?.checkUserBlocked(id:userID, userId:id)
            .subscribe(onSuccess: { response in
                self.isBlocked = response.isBlocked
                self.delegate?.didIsBlockedUser()
            }, onFailure: { _ in
            })
            .disposed(by: disposeBag)
    }
    
    func blockUser(userID:String, id:String) {
        _ = sessionManager?.blockUser(id: id, userId: userID)
            .subscribe(onSuccess: { response in
                self.delegate?.didBlockUser()
            }, onFailure: { error in
                self.delegate?.didFailedToBlockUser()
            })
            .disposed(by: disposeBag)
    }
    
    func unblockUser(userID:String) {
        _ = sessionManager?.unblockUser(id: userID)
            .subscribe(onSuccess: { response in
                self.delegate?.didUnBlockUser()
            }, onFailure: { error in
                self.delegate?.didFailedToUnBlockUser()
            })
            .disposed(by: disposeBag)
    }
    
    func deleteChat(id: String) {
        _ = sessionManager?.deleteChat(id: id)
            .subscribe(onSuccess: { postResponse in
                self.delegate?.didDeleteChat()
            }, onFailure: { error in
                self.delegate?.didFailedToDelete()
            })
            .disposed(by: disposeBag)
    }
    
    func deleteMessage(id: String) {
        _ = sessionManager?.deleteMessage(id: id)
            .subscribe(onSuccess: { postResponse in
                self.delegate?.didDeleteMessage()
            }, onFailure: { error in
                self.delegate?.didFailedToDeleteMessage()
            })
            .disposed(by: disposeBag)
    }
    
    // MARK: - Conversation Creation
    func createConversation(request: ApiRequest, completion: @escaping (String?) -> Void) {
        _ = sessionManager?.createChat(participants: request.parameters?["participants"] as? [String] ?? [], 
                                     isGroup: request.parameters?["isGroup"] as? Bool ?? false,
                                     title: request.parameters?["title"] as? String ?? "",
                                     groupAvatar: request.parameters?["groupAvatar"] as? String ?? "")
            .subscribe(onSuccess: { response in
                if let chatId = response["id"] as? String {
                    completion(chatId)
                } else {
                    completion(nil)
                }
            }, onFailure: { error in
                print("Failed to create conversation: \(error)")
                completion(nil)
            })
            .disposed(by: disposeBag)
    }
}
