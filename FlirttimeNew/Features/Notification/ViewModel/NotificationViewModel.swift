//
//  NotificationViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 23/05/24.
//

import Foundation

// TODO: replace the MockNotifications responses with ApiName.notifications / notificationRead / read-all requests.
class NotificationViewModel {

    @Published var arrNotification:[NotificationData]? = nil
    @Published var dictNotification:DataReadNotificationModel?
    @Published var errorMessage:String?

    private let store = MockDataStore.shared
    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    func getNotificationListAPI() {
        respond { [weak self] in
            guard let self = self else { return }
            let payload: [String: Any] = [
                "status": true,
                "message": "",
                "img_base_url": ApiName.imgBaseURL,
                "data": MockNotifications.listJSON
            ]
            if let data = self.store.decode(NotificationModel.self, from: payload), data.status == true {
                self.arrNotification = data.data
            } else {
                self.errorMessage = "Unable to load notifications"
            }
        }
    }

    func readNotificationAPI(id:Int) {
        respond { [weak self] in
            guard let self = self else { return }
            guard let notification = MockNotifications.markRead(id: id) else {
                self.errorMessage = "Notification not found"
                return
            }
            let payload: [String: Any] = ["status": true, "message": "", "data": notification, "img_base_url": ApiName.imgBaseURL]
            self.dictNotification = self.store.decode(ReadNotificationModel.self, from: payload)?.data
        }
    }

    func readAllNotificationsAPI() {
        respond { [weak self] in
            MockNotifications.markAllRead()
            self?.getNotificationListAPI()
        }
    }
}
