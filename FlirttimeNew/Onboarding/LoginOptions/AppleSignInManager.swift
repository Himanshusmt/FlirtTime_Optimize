//
//  AppleSignInManager.swift
//  FlirttimeNew
//

import AuthenticationServices
import UIKit

struct AppleCredential {
    let identityToken: String
    let authorizationCode: String?
    /// Apple only returns the name on the very first authorization for this app.
    let firstName: String?
    let lastName: String?
    let email: String?
}

enum AppleSignInError: LocalizedError {
    case cancelled
    case missingIdentityToken
    case unavailable
    case failed

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Apple sign in was cancelled"
        case .missingIdentityToken: return "Unable to read Apple identity token"
        case .unavailable: return "Apple sign in is not available. Please sign in with your Apple ID in Settings."
        case .failed: return "Apple sign in failed. Please try again."
        }
    }
}

/// Wraps `ASAuthorizationController`. Keep a strong reference until the completion fires.
final class AppleSignInManager: NSObject {

    private weak var window: UIWindow?
    private var completion: ((Result<AppleCredential, Error>) -> Void)?

    func signIn(from window: UIWindow?, completion: @escaping (Result<AppleCredential, Error>) -> Void) {
        self.window = window
        self.completion = completion

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    private func finish(_ result: Result<AppleCredential, Error>) {
        let completion = self.completion
        self.completion = nil
        DispatchQueue.main.async { completion?(result) }
    }
}

extension AppleSignInManager: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            finish(.failure(AppleSignInError.missingIdentityToken))
            return
        }
        let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        finish(.success(AppleCredential(identityToken: identityToken,
                                        authorizationCode: authorizationCode,
                                        firstName: credential.fullName?.givenName,
                                        lastName: credential.fullName?.familyName,
                                        email: credential.email)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("AppleSignInManager error: \(error)")
        switch (error as? ASAuthorizationError)?.code {
        case .canceled:
            finish(.failure(AppleSignInError.cancelled))
        // 1000: no Apple ID on the device/simulator or the capability is not provisioned.
        case .unknown:
            finish(.failure(AppleSignInError.unavailable))
        default:
            finish(.failure(AppleSignInError.failed))
        }
    }
}

extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
