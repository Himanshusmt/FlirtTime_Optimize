//
//  OnboardingFlow.swift
//  FlirttimeNew
//

import UIKit

/// The only steps the onboarding API accepts. Anything else is a 400.
enum OnboardingStep: String {
    case basicInfo
    case photos
    case gesture
    case completed

    /// A known `currentStep` wins. `isProfileComplete` means Home only when the step is missing.
    /// Removed steps (`preferences`, `genderPreference`, `religion`, `interests`, `audio`, `faceVerification`) fall back.
    static func resolve(currentStep: String?, isProfileComplete: Bool?, fallback: OnboardingStep) -> OnboardingStep {
        if let raw = currentStep?.trimmingCharacters(in: .whitespacesAndNewlines),
           let step = OnboardingStep(rawValue: raw) {
            return step
        }
        if isProfileComplete == true { return .completed }
        return fallback
    }
}

/// `data` of GET `/api/v1/onboarding/progress`, and of saves that advance the step.
struct OnboardingProgress {
    let currentStep: String?
    let isProfileComplete: Bool?

    /// Resume target. Unknown or missing step opens Introduce Yourself.
    var resolvedStep: OnboardingStep {
        OnboardingStep.resolve(currentStep: currentStep, isProfileComplete: isProfileComplete, fallback: .basicInfo)
    }

    init(currentStep: String? = nil, isProfileComplete: Bool? = nil) {
        self.currentStep = currentStep
        self.isProfileComplete = isProfileComplete
    }

    /// Reads `currentStep` from `{ data: { currentStep } }` or a bare object. `steps` is ignored.
    init(json: [String: Any]) {
        let data = json["data"] as? [String: Any] ?? json
        let user = data["user"] as? [String: Any]
        currentStep = Self.string(data["currentStep"]) ?? Self.string(user?["currentStep"])
        isProfileComplete = Self.bool(data["isProfileComplete"]) ?? Self.bool(user?["isProfileComplete"])
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }
}

enum OnboardingFlow {

    /// Splash and login. `completed` is Home. Going Great is only shown in-session after a gesture pass.
    static func viewController(for step: OnboardingStep, signUpOption: SignUpOption? = nil) -> UIViewController {
        switch step {
        case .completed:
            return AppTabBarController.instantiateFromStoryboard()
        case .photos:
            return StartProfileVerificationViewController.instantiateFromStoryboard()
        case .gesture:
            return GestureVerificationViewController.instantiateFromStoryboard()
        case .basicInfo:
            let details = UserDetailsViewController.instantiateFromStoryboard()
            details.signUpOption = signUpOption
            return details
        }
    }
}
