//
//  SendLocationView.swift
//  FlirttimeNew
//
//  Google Maps preview of the user's position with a "send current location" action.
//

import SwiftUI
import GoogleMaps
import CoreLocation
import UIKit

struct SendLocationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationService = LocationService.shared
    @State private var isLocationLoading = false
    @State private var isLocationReady = false
    @State private var showingPermissionAlert = false
    @State private var locationError: String?
    @State private var pulseAnimation = false

    let onLocationSent: (SendLocationRequest) -> Void

    private let acceptableLocationAge: TimeInterval = 300

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                mapSection
                actionsSection
            }
            .background(Color.chatBackground)
            .navigationTitle(ChatStrings.chat_sendLocation.localizedString())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        SwiftUI.Image(ChatAssets.back)
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .onAppear {
                checkLocationPermission()
                pulseAnimation = true
            }
            .onChange(of: locationService.permissionState) { newState in
                if newState.canUseLocation, !isLocationReady {
                    showingPermissionAlert = false
                    prepareLocation()
                }
            }
            .onDisappear {
                locationService.stopLocationUpdates()
            }
            .alert(ChatStrings.chat_locationPermissionRequired.localizedString(), isPresented: $showingPermissionAlert) {
                Button(ChatStrings.chat_openSettings.localizedString()) {
                    openLocationSettings()
                }
                Button(ChatStrings.chat_cancel.localizedString(), role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(ChatStrings.chat_pleaseEnableLocation.localizedString())
            }
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        ZStack {
            if isLocationReady {
                GoogleMapView(locationService: locationService)
                    .transition(.opacity)
            } else {
                locationLoadingView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        .clipped()
    }

    private var locationLoadingView: some View {
        ZStack {
            Color.chatSurface

            if let error = locationError, !isLocationLoading {
                VStack(spacing: 16) {
                    SwiftUI.Image(systemName: "location.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.chatPrimary.opacity(0.6))

                    Text(ChatStrings.chat_locationUnavailable.localizedString())
                        .font(.chat(.semibold, size: 16))
                        .foregroundColor(.chatTextPrimary)

                    Text(error)
                        .font(.chat(.regular, size: 13))
                        .foregroundColor(.chatTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button(action: {
                        locationError = nil
                        loadCurrentLocation()
                    }) {
                        Text(ChatStrings.chat_retry.localizedString())
                            .font(.chat(.medium, size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.chatPrimary))
                    }
                    .padding(.top, 4)
                }
            } else {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.chatPrimary.opacity(0.15), lineWidth: 1.5)
                            .frame(width: 100, height: 100)
                            .scaleEffect(pulseAnimation ? 1.4 : 1.0)
                            .opacity(pulseAnimation ? 0.0 : 0.6)

                        Circle()
                            .stroke(Color.chatPrimary.opacity(0.25), lineWidth: 1.5)
                            .frame(width: 70, height: 70)
                            .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                            .opacity(pulseAnimation ? 0.0 : 0.8)

                        Circle()
                            .fill(Color.chatPrimary.opacity(0.12))
                            .frame(width: 44, height: 44)

                        SwiftUI.Image(ChatAssets.location)
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.chatPrimary)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            pulseAnimation = true
                        }
                    }

                    VStack(spacing: 6) {
                        Text(ChatStrings.chat_gettingLocation.localizedString())
                            .font(.chat(.medium, size: 15))
                            .foregroundColor(.chatTextPrimary)

                        Text(ChatStrings.chat_momentNotice.localizedString())
                            .font(.chat(.regular, size: 13))
                            .foregroundColor(.chatTextSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 16) {
            Button(action: sendCurrentLocation) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.chatPrimary)
                            .frame(width: 44, height: 44)

                        SwiftUI.Image(ChatAssets.location)
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 22, height: 22)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ChatStrings.chat_sendYourCurrentLocation.localizedString())
                            .font(.chat(.semibold, size: 15))
                            .foregroundColor(.chatTextPrimary)

                        if let address = locationService.currentAddress {
                            Text(address)
                                .font(.chat(.regular, size: 13))
                                .foregroundColor(.chatTextSecondary)
                                .lineLimit(1)
                        } else if isLocationLoading {
                            Text(ChatStrings.chat_gettingLocation.localizedString())
                                .font(.chat(.regular, size: 13))
                                .foregroundColor(.chatTextTertiary)
                        }
                    }

                    Spacer()

                    if isLocationLoading {
                        ProgressView().tint(.chatPrimary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.chatPrimarySoft)
                )
            }
            .disabled(!isLocationReady || isLocationLoading)
            .opacity(isLocationReady ? 1.0 : 0.5)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    // MARK: - Permission & location

    private func checkLocationPermission() {
        switch locationService.permissionState {
        case .notDetermined:
            locationService.requestLocationPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        prepareLocation()
                    } else {
                        showingPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showingPermissionAlert = true
        case .authorizedWhenInUse, .authorizedAlways:
            prepareLocation()
        case .unknown:
            break
        }
    }

    /// Uses a cached fix when available, otherwise fetches a fresh one.
    private func prepareLocation() {
        if let currentLocation = locationService.currentLocation, currentLocation.horizontalAccuracy >= 0 {
            MapSnapshotCache.shared.prewarmNow(
                lat: currentLocation.coordinate.latitude,
                lng: currentLocation.coordinate.longitude
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                isLocationReady = true
            }
            if Date().timeIntervalSince(currentLocation.timestamp) >= acceptableLocationAge {
                loadCurrentLocation()
            }
        } else {
            loadCurrentLocation()
        }
    }

    private func loadCurrentLocation() {
        isLocationLoading = true
        locationError = nil
        locationService.getCurrentLocation { location, error in
            DispatchQueue.main.async {
                isLocationLoading = false
                if let error {
                    locationError = error.localizedDescription
                    isLocationReady = false
                } else if let location {
                    MapSnapshotCache.shared.prewarmNow(
                        lat: location.coordinate.latitude,
                        lng: location.coordinate.longitude
                    )
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLocationReady = true
                    }
                }
            }
        }
    }

    private func sendCurrentLocation() {
        if let location = locationService.currentLocation, location.horizontalAccuracy >= 0 {
            sendLocation(location)
            return
        }

        isLocationLoading = true
        locationError = nil
        locationService.getCurrentLocation { location, error in
            DispatchQueue.main.async {
                isLocationLoading = false
                if let location {
                    sendLocation(location)
                } else {
                    locationError = error?.localizedDescription ?? ChatStrings.chat_unableGetLocation.localizedString()
                    isLocationReady = false
                }
            }
        }
    }

    private func sendLocation(_ location: CLLocation) {
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        isLocationLoading = true

        Task {
            // Cache the snapshot first so the message cell renders it immediately.
            _ = await MapSnapshotCache.shared.generate(lat: lat, lng: lng)

            await MainActor.run {
                isLocationLoading = false
                if let address = locationService.currentAddress, !address.isEmpty {
                    dispatchLocationRequest(lat: lat, lng: lng, address: address)
                } else {
                    locationService.getAddressFromLocation(location) { address in
                        dispatchLocationRequest(lat: lat, lng: lng, address: address)
                    }
                }
            }
        }
    }

    private func dispatchLocationRequest(lat: Double, lng: Double, address: String?) {
        let request = SendLocationRequest(
            conversationId: "",
            type: .staticLocation,
            latitude: lat,
            longitude: lng,
            address: address,
            duration: nil,
            comment: nil
        )
        onLocationSent(request)
        dismiss()
    }

    private func openLocationSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsUrl)
    }
}

// MARK: - Google Maps View

struct GoogleMapView: UIViewRepresentable {
    let locationService: LocationService

    final class Coordinator {
        var lastCenteredTimestamp: Date?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let coordinate = locationService.currentLocation?.coordinate
        let camera = GMSCameraPosition.camera(
            withLatitude: coordinate?.latitude ?? 0,
            longitude: coordinate?.longitude ?? 0,
            zoom: 15.0
        )
        let options = GMSMapViewOptions()
        options.camera = camera
        let mapView = GMSMapView(options: options)
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        return mapView
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {
        guard let location = locationService.currentLocation,
              context.coordinator.lastCenteredTimestamp != location.timestamp else { return }

        context.coordinator.lastCenteredTimestamp = location.timestamp
        let camera = GMSCameraPosition.camera(
            withLatitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            zoom: 15.0
        )
        uiView.moveCamera(GMSCameraUpdate.setCamera(camera))
    }
}
