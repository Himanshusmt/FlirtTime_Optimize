//
//  FaceVerificationViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 03/05/24.
//

import UIKit
import Photos
import AVFoundation

class FaceVerificationViewController: BaseViewController,Instantiable, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var selfieView: UIView!
    @IBOutlet weak var userImageView: UIImageView!
    @IBOutlet weak var openCameraButton: UIImageView!
    @IBOutlet weak var retakeButton: UIButton!
    @IBOutlet weak var faceScanningImage: UIImageView!
    @IBOutlet weak var switchToBackFrontCameraButton: UIButton!

    private var session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var currentCameraPosition: AVCaptureDevice.Position = .front
    private var capturePhotoOutput: AVCapturePhotoOutput!
    var photoCaptureCompletion: ((UIImage?) -> Void)?
    var headerText:String?
    var isHideScanningImage:Bool? = false
    var actualImage:UIImage?


    let dataOutputQueue = DispatchQueue (
        label: "video data queue",
        qos: .userInitiated,
        attributes: [],
        autoreleaseFrequency: .workItem)

    @IBOutlet weak var dismissCameraButton: UIButton!
    var callBackAction:((UIImage?)->Void)?

    static var storyboardName: StringConvertible {
        return StoryboardName.signUp
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.faceScanningImage.isHidden = self.isHideScanningImage ?? false
        self.headerLabel.text = self.headerText
        self.userImageView.image = nil
        self.setCameraButtonUI()
        self.setupCamera()
        self.dismissCameraButton.isHidden = false
        self.setupCapturePhotoOutput()
    }

    @IBAction func cameraButtonTapped(_ sender: UIButton) {
        if self.userImageView.image != nil {
            self.dismiss(animated: true) {
                guard let action = self.callBackAction else { return }
                if let image = self.actualImage {
                    action(image)
                }else{
                    action(self.userImageView.image)
                }
            }
        }else{
            self.showClickedImage()
        }
    }

    @IBAction func dismissButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }

    @IBAction func retakeButtonTapped(_ sender: UIButton) {
        self.userImageView.isHidden = true
        self.selfieView.isHidden = false
        self.userImageView.image = nil
        self.setCameraButtonUI()
    }


    @IBAction func switchToBackFrontButtonTapped(_ sender: UIButton) {
        self.switchCamera()
    }

    func setCameraButtonUI(){
        self.openCameraButton.image = self.userImageView.image != nil ? UIImage(named: "whiteCircle") : UIImage(named: "cameraButton")
        self.retakeButton.isHidden = !(self.userImageView.image != nil)
        self.switchToBackFrontCameraButton.isHidden = self.userImageView.image != nil
    }
}

extension FaceVerificationViewController {
    func showClickedImage(){
        self.photoCaptureCompletion = { capturedImage in
            // Handle the captured image here
            DispatchQueue.main.async {
                self.selfieView.isHidden = true
                self.userImageView.isHidden = false
                self.userImageView.contentMode = .scaleAspectFill
                self.userImageView.image = capturedImage
                self.setCameraButtonUI()
            }
        }

        // No capture device (e.g. Simulator): use a stand-in photo so the flow can continue
        guard !session.inputs.isEmpty else {
            self.actualImage = UIImage(named: "ProfileClearSet")
            self.photoCaptureCompletion?(self.actualImage)
            return
        }
        self.capturePhoto { _ in }
    }

    private func switchCamera() {
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }
        self.self.openCameraButton.isUserInteractionEnabled = false
        session.beginConfiguration()
        session.removeInput(currentInput)

        let newCamera = (currentInput.device.position == .front) ? getCamera(for: .back) : getCamera(for: .front)
        do {
            let newInput = try AVCaptureDeviceInput(device: newCamera!)
            session.addInput(newInput)
        } catch {
            print("Error switching cameras: \(error)")
        }

        session.commitConfiguration()
        currentCameraPosition = (currentCameraPosition == .front) ? .back : .front
        self.openCameraButton.isUserInteractionEnabled = true

    }

    private func getCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: position).devices
        return devices.first
    }


}

extension FaceVerificationViewController: AVCapturePhotoCaptureDelegate {
    private func setupCamera() {
        // Define the capture device we want to use
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front) else {
            return
        }

        // Connect the camera to the capture session input
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            session.addInput(cameraInput)
        } catch {
            fatalError(error.localizedDescription)
        }

        // Create the video data output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        // Add the video output to the capture session
        session.addOutput(videoOutput)

        let videoConnection = videoOutput.connection(with: .video)
        videoConnection?.videoOrientation = .portrait

        // Configure the preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = screen
        //
        if let previewLayer = previewLayer {
            self.selfieView.layer.addSublayer(previewLayer)
        }

        // Start the session after configuration
        DispatchQueue.main.async {
            self.session.startRunning()
        }
    }

    private func setupCapturePhotoOutput() {
        session.sessionPreset = .photo

        capturePhotoOutput = AVCapturePhotoOutput()
        capturePhotoOutput.isHighResolutionCaptureEnabled = true

        if let capturePhotoOutput = capturePhotoOutput, session.canAddOutput(capturePhotoOutput) {
            session.addOutput(capturePhotoOutput)
        } else {
            print("Failed to add capture photo output to session")
        }
    }


    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard let capturePhotoOutput = capturePhotoOutput else {
            print("Capture photo output not set")
            completion(nil)
            return
        }

        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isAutoStillImageStabilizationEnabled = true
        photoSettings.isHighResolutionPhotoEnabled = true

        capturePhotoOutput.capturePhoto(with: photoSettings, delegate: self)
    }

    // When you call capturePhoto, it initiates the process of capturing a photo using the capturePhotoOutput. Once the photo is captured and processed, the photoOutput(_:didFinishProcessingPhoto:error:) method of AVCapturePhotoCaptureDelegate is invoked. In that method, the captured image data is converted to a UIImage, and then it's passed to the completion handler:

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?){
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("Error converting captured image to UIImage")
            return
        }

//         Apply transformation to fix the orientation
        var orientatedImage = UIImage()
        if self.currentCameraPosition == .front {
            orientatedImage = flipImageHorizontally(image: image)
        }else{
            orientatedImage = image // Keep the default orientation for the back camera
        }
        self.actualImage = orientatedImage
        DispatchQueue.main.async {
            guard let completion = self.photoCaptureCompletion else { return }
            completion(self.actualImage)
        }
    }

    func flipImageHorizontally(image: UIImage) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        let context = UIGraphicsGetCurrentContext()!
        // Move origin to the middle
        context.translateBy(x: image.size.width / 2, y: image.size.height / 2)
        // Apply the horizontal flip transformation
        context.scaleBy(x: -1.0, y: 1.0)
        // Move origin back
        context.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
        // Draw the image
        image.draw(at: .zero)
        let flippedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return flippedImage
    }

    
}
