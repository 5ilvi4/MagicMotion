// CameraManager.swift
// Sets up the iPad's FRONT camera using AVFoundation.
// Think of AVCaptureSession as a "pipeline": camera → processing → screen.

import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // The main capture session — the pipeline that connects camera to output
    let captureSession = AVCaptureSession()

    // The layer that displays the live camera feed on screen (UIKit-based)
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    // Background queues keep camera work off the main (UI) thread
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let outputQueue  = DispatchQueue(label: "camera.output.queue")

    // Called every time a new video frame arrives — connect this to PoseDetector
    var onNewFrame: ((CMSampleBuffer, CGImagePropertyOrientation) -> Void)?

    // SwiftUI can observe these to show status in the UI
    @Published var isRunning          = false
    @Published var permissionGranted  = false

    // MARK: - Public API

    /// Ask the user for camera access, then start the camera.
    func requestPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // User already said yes
            permissionGranted = true
            setupSession()
        case .notDetermined:
            // First time asking — show the system dialog
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted { self?.setupSession() }
                }
            }
        default:
            // User previously said no — direct them to Settings
            permissionGranted = false
        }
    }

    /// Stop the camera (call when the view disappears to save battery).
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    // MARK: - Private Setup

    /// Wire up the front camera → AVCaptureSession → video output.
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()
            // 720p is a good balance: high enough for pose detection, not too heavy
            self.captureSession.sessionPreset = .hd1280x720

            // ── Step 1: Find the front camera ──
            guard let frontCamera = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .front
            ) else {
                print("❌ No front camera found on this device")
                self.captureSession.commitConfiguration()
                return
            }

            // ── Step 2: Create an input from the camera ──
            guard let videoInput = try? AVCaptureDeviceInput(device: frontCamera),
                  self.captureSession.canAddInput(videoInput) else {
                print("❌ Could not create video input")
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(videoInput)

            // ── Step 3: Create a video output to receive raw pixel buffers ──
            let videoOutput = AVCaptureVideoDataOutput()
            // Drop frames we can't process fast enough (better than building a queue backlog)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: self.outputQueue)

            guard self.captureSession.canAddOutput(videoOutput) else {
                print("❌ Could not add video output")
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addOutput(videoOutput)

            // ── Step 4: Set orientation and mirroring ──
            if let connection = videoOutput.connection(with: .video) {
                // Portrait: person stands upright in the frame
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                // Mirror the front camera so it feels like a mirror (natural)
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }

            self.captureSession.commitConfiguration()

            // ── Step 5: Create the preview layer (must be on main thread) ──
            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                layer.videoGravity = .resizeAspectFill  // Fill the screen, crop edges
                self.previewLayer = layer
            }

            // ── Step 6: Start! ──
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    /// Called automatically ~30 times per second with a new camera frame.
    /// We forward it straight to whoever is listening (the PoseDetector).
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // We set portrait + mirrored above, so Vision should receive it upright
        onNewFrame?(sampleBuffer, .up)
    }
}
