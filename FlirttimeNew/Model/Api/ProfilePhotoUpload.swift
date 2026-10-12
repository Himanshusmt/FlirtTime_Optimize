//
//  ProfilePhotoUpload.swift
//  FlirttimeNew
//

import Foundation

/// The `data` of POST `onboarding/profile-photo`.
struct ProfilePhotoUpload: Codable {
    let photoId: String?
    /// S3 key relative to `ApiName.imgBaseURL`, e.g. "photos/<userId>/<file>.jpg".
    let profilePhoto: String?
    let isPrimary: Bool?

    var profilePhotoURL: URL? {
        guard let profilePhoto, !profilePhoto.isEmpty else { return nil }
        return URL(string: ApiName.imgBaseURL + profilePhoto)
    }
}
