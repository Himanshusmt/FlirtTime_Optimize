//
//  PhoneIOSClientVerification.swift
//  FlirttimeNew
//

import Foundation

/// `data` of POST `/api/v1/auth/phone/ios/verify-client`.
struct PhoneIOSClientVerification: Codable {
    let receipt: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        receipt = c.string("receipt", "iosReceipt")
    }
}
