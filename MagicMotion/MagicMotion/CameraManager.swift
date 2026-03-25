//
//  CameraManager.swift
//  MagicMotion
//
//  Manages the AVCaptureSession and delivers video frames.
//

import AVFoundation
import UIKit

/// Manages camera capture session and delivers video frames for processing.
class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether the camera session is currently running
    @Published var isRunning = false
    
    // MARK: - Properties
    
    /// The AVCaptureSession that coordinates camera input/output
    private let captureSession = AVCaptureSession()
    
    /// The layer that displays the camera preview (used in UIViewRepresentable)
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    /// Callback invoked for each video frame captured
    var onNewFrame: ((CMSampleBuffer, AVCaptureVideoOrientation) -> Void)?
    
    // MARK: - Setup
    
    /// Request camera permission and set up the capture session
    func requestPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupSession()
                }
            }
        default:
            print("Camera access denied")
        }
    }
    
    /// Configure the capture session with camera input and video output
    private func setupSession() {
        captureSession.beginConfiguration()
        
        // Use the front camera for selfie-style pose detection
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("Failed to access front camera")
            captureSession.commitConfiguration()
            return
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        // Add video data output to receive frames
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.queue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // Set session preset for quality
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
        
        captureSession.commitConfiguration()
        
        // Create preview layer
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        previewLayer = preview
        
        // Start the session on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }
    }
    
    /// Stop the capture session
    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        
        // Determine the video orientation based on device orientation
        let orientation: AVCaptureVideoOrientation
        switch UIDevice.current.orientation {
        case .portrait:
            orientation = .portrait
        case .portraitUpsideDown:
            orientation = .portraitUpsideDown
        case .landscapeLeft:
            orientation = .landscapeRight // Counterintuitive but correct!
        case .landscapeRight:
            orientation = .landscapeLeft
        default:
            orientation = .portrait
        }
        
        // Deliver the frame to whoever is listening
        onNewFrame?(sampleBuffer, orientation)
    }
}
