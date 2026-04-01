//
//  CameraManager.swift
//  MotionMind
//
//  Manages the AVCaptureSession and delivers video frames.
//  Conforms to FrameSource so it can be swapped for SyntheticFrameSource in tests.
//

import AVFoundation
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
    @Published var frameCount: Int = 0

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
    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Private

    private let captureSession = AVCaptureSession()

    private func setupSession() {
        captureSession.beginConfiguration()

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("Failed to access front camera")
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.queue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }

        if captureSession.canSetSessionPreset(.high) { captureSession.sessionPreset = .high }

        captureSession.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
                self?.isCameraActive = true
                self?.frameCount = 0
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
        DispatchQueue.main.async { self.frameCount += 1 }
        onNewFrame?(sampleBuffer, orientation)
    }
}
