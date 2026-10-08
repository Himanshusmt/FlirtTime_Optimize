//
//  LocationService.swift
//  FlirttimeNew
//

import Foundation
import CoreLocation
import Combine

final class LocationService: NSObject, ObservableObject {

    static let shared = LocationService()

    private let locationManager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var permissionState: LocationPermissionState = .notDetermined
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentAddress: String?

    private var locationUpdateCompletion: ((CLLocation?, Error?) -> Void)?
    private var permissionCompletion: ((Bool) -> Void)?
    private var locationRequestStartedAt: Date?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10.0
        updatePermissionState()
    }

    func requestLocationPermission(completion: @escaping (Bool) -> Void) {
        permissionCompletion = completion

        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            permissionCompletion = nil
            completion(false)
        case .authorizedWhenInUse, .authorizedAlways:
            permissionCompletion = nil
            completion(true)
        @unknown default:
            permissionCompletion = nil
            completion(false)
        }
    }

    private func updatePermissionState() {
        authorizationStatus = locationManager.authorizationStatus
        permissionState = LocationPermissionState(from: authorizationStatus)
    }

    func getCurrentLocation(completion: @escaping (CLLocation?, Error?) -> Void) {
        guard permissionState.canUseLocation else {
            completion(nil, LocationError.permissionDenied)
            return
        }

        guard CLLocationManager.locationServicesEnabled() else {
            completion(nil, LocationError.locationServicesDisabled)
            return
        }

        locationUpdateCompletion = completion
        locationRequestStartedAt = Date()
        locationManager.startUpdatingLocation()

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, let pending = self.locationUpdateCompletion else { return }
            self.locationManager.stopUpdatingLocation()
            self.locationUpdateCompletion = nil
            pending(nil, LocationError.timeout)
        }
    }

    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationUpdateCompletion = nil
        locationRequestStartedAt = nil
    }

    func getAddressFromLocation(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                guard let placemark = placemarks?.first, error == nil else {
                    completion(nil)
                    return
                }
                let address = [placemark.name, placemark.locality, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                completion(address.isEmpty ? nil : address)
            }
        }
    }

    private func deliver(_ location: CLLocation, to completion: (CLLocation?, Error?) -> Void) {
        currentLocation = location
        locationUpdateCompletion = nil
        locationRequestStartedAt = nil
        completion(location, nil)
        getAddressFromLocation(location) { [weak self] address in
            self?.currentAddress = address
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        guard let completion = locationUpdateCompletion else {
            currentLocation = location
            getAddressFromLocation(location) { [weak self] address in
                self?.currentAddress = address
            }
            return
        }

        let age = Date().timeIntervalSince(location.timestamp)
        let accuracy = location.horizontalAccuracy
        let isFresh = age < 30

        if isFresh, accuracy >= 0, accuracy <= 100 {
            deliver(location, to: completion)
            return
        }

        // After 5 seconds accept the best fresh fix available.
        if let startedAt = locationRequestStartedAt,
           Date().timeIntervalSince(startedAt) >= 5, accuracy >= 0, isFresh {
            deliver(location, to: completion)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let completion = locationUpdateCompletion else { return }
        locationUpdateCompletion = nil
        completion(nil, error)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updatePermissionState()

        if let completion = permissionCompletion, permissionState != .notDetermined {
            permissionCompletion = nil
            completion(permissionState.canUseLocation)
        }
    }
}

// MARK: - Errors

enum LocationError: LocalizedError {
    case permissionDenied
    case locationServicesDisabled
    case timeout

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return ChatStrings.chat_locationPermissionDenied.localizedString()
        case .locationServicesDisabled:
            return ChatStrings.chat_locationServicesDisabled.localizedString()
        case .timeout:
            return ChatStrings.chat_locationTimeout.localizedString()
        }
    }
}
