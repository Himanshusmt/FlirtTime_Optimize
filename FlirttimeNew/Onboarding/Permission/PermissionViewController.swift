//
//  PermissionViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import UIKit
import CoreLocation
import AVFoundation
import Photos

class PermissionViewController: BaseViewController,Instantiable {


    @IBOutlet weak var smsAndCallPermissionBackImage: UIImageView!
    @IBOutlet weak var locationPermissionBackImage: UIImageView!
    @IBOutlet weak var mediaPermissionBackImage: UIImageView!

    private let locationManager = CLLocationManager()
    static var storyboardName: StringConvertible {
        return StoryboardName.splash
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        [self.smsAndCallPermissionBackImage,self.locationPermissionBackImage,self.mediaPermissionBackImage].forEach { object in
            object.addShadow(color: AppColor.AppBlack.withAlphaComponent(0.2), opacity: 1.0, offset: CGSize(width: 0, height: 0.5))
        }
        self.checkCameraPermission()
        self.checkPhotoLibraryPermission()
        self.locationManager.requestWhenInUseAuthorization()
    }

    @IBAction func proceedAction(_ sender: UIButton) {
        self.navigateToNextScreen()
    }

    func navigateToNextScreen(){
        let aLoginOptionsViewController = LoginOptionsViewController.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aLoginOptionsViewController, animated: true)
    }
}

extension PermissionViewController {

    func checkCameraPermission() {
        let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch cameraAuthorizationStatus {
        case .authorized:
            // Camera access already granted
            // Proceed with camera operations
            break
        case .notDetermined:
            // Request camera access
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    // Camera access granted by user
                    // Proceed with camera operations
                } else {
                    // Camera access denied by user
                    // Handle accordingly, e.g., show an alert
                }
            }
        case .denied, .restricted:
            // Camera access denied by user or restricted by parental controls
            // Handle accordingly, e.g., show an alert
            break
        @unknown default:
            break
        }
    }

    func checkPhotoLibraryPermission() {
        let photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus()

        switch photoAuthorizationStatus {
        case .authorized:
            // Photo library access already granted
            // Proceed with photo library operations
            break
        case .notDetermined:
            // Request photo library access
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Photo library access granted by user
                    // Proceed with photo library operations
                } else {
                    // Photo library access denied by user
                    // Handle accordingly, e.g., show an alert
                }
            }
        case .denied, .restricted:
            // Photo library access denied by user or restricted by parental controls
            // Handle accordingly, e.g., show an alert
            break
        @unknown default:
            break
        }
    }

}

// Granted User permission
/*
extension PermissionViewController:CLLocationManagerDelegate {
    func checkLocationPermission() {
        let locationManager = CLLocationManager()

        switch CLLocationManager.authorizationStatus() {
        case .authorizedWhenInUse, .authorizedAlways:
            // Location access already granted
            // Proceed with location-based operations
            break
        case .notDetermined:
            // Request location access
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // Location access denied by user or restricted by parental controls
            // Handle accordingly, e.g., show an alert
            break
        @unknown default:
            break
        }
    }
}
*/
