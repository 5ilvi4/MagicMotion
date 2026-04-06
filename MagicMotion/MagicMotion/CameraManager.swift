//
//  CameraManager.swift
//  MotionMind
//
//  Manages the AVCaptureSession and delivers video frames.
//  Conforms to FrameSource so it can be swapped for SyntheticFrameSource in tests.
//

import AVFoundation
import Combine
import UIKit

/// Manages camera capture session and delivers video frames for processing.
class CameraManager: NSObject, ObservableObject, FrameSource {

    // MARK: - FrameSource

    /// Called for every new frame; delivered on the camera serial queue.
    var onNewFrame: ((CMSampleBuffer, CGImagePropertyOrientation) -> Void)?

    /// Whether the camera session is currently running.
    @Published var isRunning = false

    /// Explicit active flag — survives background transitions.
    @Published var isCameraActive = false

    /// Total frames delivered since last start (diagnostics).
    /// NOT @Published — updating this at 30fps forces ContentView to re-render at 30fps,
    /// which causes updateUIView to run 30x/sec and thrash the AVCaptureVideoPreviewLayer.
    private(set) var frameCount: Int = 0

    /// Diagnostic: one UIImage per second so we can verify the camera produces real content.
    /// Nil until the first frame arrives. Show this in SwiftUI to confirm feed isn't black.
    @Published var diagnosticFrame: UIImage?
    private var lastDiagnosticTime: TimeInterval = 0
    // Reuse CIContext — creating one per frame is expensive.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Begin requesting permission and running the capture session.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.setupSession() }
            }
        default:
            print("Camera access denied")
        }
    }

    /// Stop the capture session.
    /// NOTE: Do NOT call this when the app backgrounds — the camera must
    /// keep running so MediaPipe can continue gesture detection.
    func stop() {
        // Guard: never stop while a background task is active
        if BackgroundTaskManager.shared.isInBackground {
            print("📷 CameraManager: stop() ignored — background task is active")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isCameraActive = false
            }
        }
    }

    // MARK: - Preview layer (CameraManager-specific, not in protocol)

    /// The layer that displays the camera preview (used in UIViewRepresentable).
    /// @Published so SwiftUI re-renders when the session is ready asynchronously.
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Private

    private let captureSession = AVCaptureSession()

    private func setupSession() {
        captureSession.beginConfiguration()

        // --- Device selection ---
        let position: AVCaptureDevice.Position = .front
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("❌ CameraManager: camera not available for position \(position.rawValue)")
            captureSession.commitConfiguration()
            return
        }
        print("📷 CameraManager: using '\(camera.localizedName)' position=\(position == .front ? "front" : "back")")

        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            print("❌ CameraManager: AVCaptureDeviceInput creation failed")
            captureSession.commitConfiguration()
            return
        }
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        } else {
            print("❌ CameraManager: cannot add camera input")
        }

        // --- Preset (set before output to avoid format conflicts) ---
        if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
        } else if captureSession.canSetSessionPreset(.medium) {
            captureSession.sessionPreset = .medium
        }
        print("📷 CameraManager: sessionPreset=\(captureSession.sessionPreset.rawValue)")

        // --- Video output ---
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let frameQueue = DispatchQueue(label: "com.magicmotion.camera.frames", qos: .userInitiated)
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            print("❌ CameraManager: cannot add video output")
        }

        captureSession.commitConfiguration()

        // --- Preview layer (after commitConfiguration, before startRunning) ---
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        print("📷 CameraManager: previewLayer.session isNil=\(preview.session == nil)")
        DispatchQueue.main.async { self.previewLayer = preview }

        // --- Start session ---
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.captureSession.startRunning()
            print("📷 CameraManager: captureSession.isRunning=\(self.captureSession.isRunning)")
            DispatchQueue.main.async {
                self.isRunning = true
                self.isCameraActive = true
                self.frameCount = 0
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let orientation: CGImagePropertyOrientation
        switch UIDevice.current.orientation {
        case .portrait:            orientation = .up
        case .portraitUpsideDown:  orientation = .down
        case .landscapeLeft:       orientation = .right
        case .landscapeRight:      orientation = .left
        default:                   orientation = .up
        }
        let isFirst = frameCount == 0
        frameCount += 1
        if isFirst { print("📷 CameraManager: first frame received") }

        // Diagnostic: capture one UIImage/sec to verify real camera content.
        // UIImage(ciImage:) is lazy and may render black — must use CIContext to materialize.
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastDiagnosticTime > 1.0,
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            lastDiagnosticTime = now
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
            print("📷 frame: \(w)×\(h) fmt=\(fmt) (BGRA=\(kCVPixelFormatType_32BGRA))")

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            // createCGImage renders pixels immediately — avoids lazy black UIImage
            if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                print("📷 diagnosticFrame created: \(uiImage.size)")
                DispatchQueue.main.async { self.diagnosticFrame = uiImage }
            } else {
                print("❌ CIContext.createCGImage failed")
            }
        }

        onNewFrame?(sampleBuffer, orientation)
    }
}
