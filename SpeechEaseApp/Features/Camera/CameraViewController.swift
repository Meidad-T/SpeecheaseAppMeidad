import UIKit
@preconcurrency import AVFoundation
import Vision

protocol CameraControllerDelegate: AnyObject {
    func didFinishRecording(url: URL)
    func didFailRecording(error: Error)
}

class CameraRecordingViewController: UIViewController, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer!
    var movieOutput = AVCaptureMovieFileOutput()
    private var videoDataOutput = AVCaptureVideoDataOutput()
    
    private var overlayView: VisionOverlayView!

    private var audioInput: AVCaptureDeviceInput?

    // Drives correct, device-independent video rotation (iOS 17+).
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    weak var delegate: CameraControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupOverlay()
        setupCamera()
    }
    
    private func setupOverlay() {
        overlayView = VisionOverlayView(frame: view.bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlayView)
    }
    
    func updateOverlaySettings(hands: Bool, body: Bool, face: Bool, handColor: UIColor, bodyColor: UIColor, faceColor: UIColor) {
        guard overlayView != nil else { return }
        overlayView.showHandLines = hands
        overlayView.showBodyLines = body
        overlayView.showFaceLines = face
        
        overlayView.handColor = handColor
        overlayView.bodyColor = bodyColor
        overlayView.faceColor = faceColor
    }
    
    func updateAudioSettings(enabled: Bool) {
        guard let session = captureSession, let audioInput = audioInput else { return }
        
        let isAudioAdded = session.inputs.contains(audioInput)
        
        if enabled && !isAudioAdded {
            session.beginConfiguration()
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
            session.commitConfiguration()
        } else if !enabled && isAudioAdded {
            session.beginConfiguration()
            session.removeInput(audioInput)
            session.commitConfiguration()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        applyPreviewRotation()
        overlayView.previewLayer = previewLayer
        view.bringSubviewToFront(overlayView)
    }

    /// Rotates the on-screen preview so it's upright, using the device-aware angle
    /// from the rotation coordinator (falls back to nothing until it's ready).
    private func applyPreviewRotation() {
        guard let connection = previewLayer?.connection,
              let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// Applies rotation/mirroring to the Vision data output (so overlays line up
    /// with the preview) and the movie file output (so recordings aren't sideways).
    private func applyOutputRotations() {
        guard let coordinator = rotationCoordinator else { return }
        // Match the preview angle for the Vision feed so overlay coordinates align.
        let previewAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        let captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture

        if let c = videoDataOutput.connection(with: .video) {
            if c.isVideoRotationAngleSupported(previewAngle) { c.videoRotationAngle = previewAngle }
            if c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = true
            }
        }
        if let c = movieOutput.connection(with: .video) {
            if c.isVideoRotationAngleSupported(captureAngle) { c.videoRotationAngle = captureAngle }
            if c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = true
            }
        }
    }
    
    func setupCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.setupAudioSession()
            }
            
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .high
            
            let movieOut = AVCaptureMovieFileOutput()
            let videoDataOut = AVCaptureVideoDataOutput()
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                print("No front camera available")
                return
            }
            
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                }
            } catch {
                print("Camera Input Error: \(error)")
                return
            }
            
            var audioIn: AVCaptureDeviceInput?
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                do {
                    let input = try AVCaptureDeviceInput(device: audioDevice)
                    audioIn = input
                    if session.canAddInput(input) {
                        session.addInput(input)
                    }
                } catch {
                    print("Audio Input Error: \(error)")
                }
            }
            
            if session.canAddOutput(movieOut) {
                session.addOutput(movieOut)
            }
            
            if session.canAddOutput(videoDataOut) {
                videoDataOut.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
                videoDataOut.alwaysDiscardsLateVideoFrames = true
                session.addOutput(videoDataOut)
                // Rotation + mirroring are applied in applyOutputRotations() once the
                // rotation coordinator exists (after the preview layer is created).
            }

            session.commitConfiguration()

            session.startRunning()

            DispatchQueue.main.async {
                self.captureSession = session
                self.movieOutput = movieOut
                self.videoDataOutput = videoDataOut
                self.audioInput = audioIn

                self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
                self.previewLayer.videoGravity = .resizeAspectFill
                self.previewLayer.frame = self.view.bounds
                self.view.layer.insertSublayer(self.previewLayer, at: 0)
                self.overlayView.previewLayer = self.previewLayer

                // Device-aware rotation for preview, Vision feed, and recordings.
                self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                    device: videoDevice,
                    previewLayer: self.previewLayer
                )
                self.applyPreviewRotation()
                self.applyOutputRotations()
            }
        }
    }
    
    func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func startRecording() {
        guard let output = captureSession?.outputs.first(where: { $0 is AVCaptureMovieFileOutput }) as? AVCaptureMovieFileOutput else { return }
        
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("temp_camera_recording.mov")
        try? FileManager.default.removeItem(at: tempUrl)
        
        output.startRecording(to: tempUrl, recordingDelegate: self)
    }
    
    func stopRecording() {
        movieOutput.stopRecording()
    }
    
    // MARK: - Vision Delegate
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let size = CGSize(width: Double(width), height: Double(height))
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        let handPoseRequest = VNDetectHumanHandPoseRequest()
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
        let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
        
        do {
            try handler.perform([handPoseRequest, faceLandmarksRequest, bodyPoseRequest])
            
            var bodyChains: [[CGPoint]] = []
            var handChains: [[CGPoint]] = []
            var faceChains: [OverlayData.FacePath] = []
            
            if let bodyResults = bodyPoseRequest.results {
                for body in bodyResults {
                    if let points = try? body.recognizedPoints(.all) {
                         let chains: [[VNHumanBodyPoseObservation.JointName]] = [
                            [.leftWrist, .leftElbow, .leftShoulder],
                            [.rightWrist, .rightElbow, .rightShoulder],
                            [.leftShoulder, .neck, .rightShoulder]
                         ]
                         for chain in chains {
                             let pts = chain.compactMap { joint -> CGPoint? in
                                 guard let p = points[joint], p.confidence > 0.3 else { return nil }
                                 return p.location
                             }
                             if !pts.isEmpty { bodyChains.append(pts) }
                         }
                    }
                }
            }
            
            if let handResults = handPoseRequest.results {
                for hand in handResults {
                    if let points = try? hand.recognizedPoints(.all) {
                         let fingers: [[VNHumanHandPoseObservation.JointName]] = [
                             [.thumbTip, .thumbIP, .thumbMP, .thumbCMC, .wrist],
                             [.indexTip, .indexDIP, .indexPIP, .indexMCP, .wrist],
                             [.middleTip, .middleDIP, .middlePIP, .middleMCP, .wrist],
                             [.ringTip, .ringDIP, .ringPIP, .ringMCP, .wrist],
                             [.littleTip, .littleDIP, .littlePIP, .littleMCP, .wrist]
                         ]
                         for finger in fingers {
                             let pts = finger.compactMap { joint -> CGPoint? in
                                 guard let p = points[joint], p.confidence > 0.3 else { return nil }
                                 return p.location
                             }
                             if !pts.isEmpty { handChains.append(pts) }
                         }
                    }
                }
            }
            
            if let faceResults = faceLandmarksRequest.results {
                for face in faceResults {
                    if let landmarks = face.landmarks {
                        let box = face.boundingBox
                        
                        func extract(region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                            guard let r = region else { return [] }
                            return r.normalizedPoints.map { p in
                                CGPoint(
                                    x: box.minX + (CGFloat(p.x) * box.width),
                                    y: box.minY + (CGFloat(p.y) * box.height)
                                )
                            }
                        }
                        
                        if let c = landmarks.faceContour { faceChains.append(.init(points: extract(region: c), isClosed: false)) }
                        if let e = landmarks.leftEye { faceChains.append(.init(points: extract(region: e), isClosed: true)) }
                        if let e = landmarks.rightEye { faceChains.append(.init(points: extract(region: e), isClosed: true)) }
                        if let l = landmarks.outerLips { faceChains.append(.init(points: extract(region: l), isClosed: true)) }
                    }
                }
            }
            
            let data = OverlayData(
                bodyChains: bodyChains,
                handChains: handChains,
                faceChains: faceChains,
                imageSize: size
            )
            
            Task { @MainActor in
                self.overlayView?.update(with: data)
            }
        } catch {
            print("Vision failed: \(error)")
        }
    }
    
    // MARK: - Delegate
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("Error recording: \(error.localizedDescription)")
            }
            self.delegate?.didFinishRecording(url: outputFileURL)
        }
    }
}
