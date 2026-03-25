//
//  PoseDetector.swift
//  MagicMotion
//
//  Uses Vision framework to detect body pose from camera frames.
//

import AVFoundation
import Vision

/// Detects human body pose using Vision framework.
class PoseDetector {
    
    // MARK: - Properties
    
    /// Callback invoked when a pose is successfully detected
    var onPoseDetected: ((PoseFrame) -> Void)?
    
    /// The Vision request that detects body pose
    private lazy var poseRequest: VNDetectHumanBodyPoseRequest = {
        let request = VNDetectHumanBodyPoseRequest()
        request.revision = VNDetectHumanBodyPoseRequestRevision1
        return request
    }()
    
    // MARK: - Processing
    
    /// Process a video frame and detect body pose
    func processFrame(_ sampleBuffer: CMSampleBuffer, orientation: AVCaptureVideoOrientation) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Convert AVCaptureVideoOrientation to CGImagePropertyOrientation
        let imageOrientation = cgImageOrientation(from: orientation)
        
        // Create a Vision request handler
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: imageOrientation,
            options: [:]
        )
        
        do {
            // Perform the pose detection
            try handler.perform([poseRequest])
            
            // Extract the first detected person
            guard let observation = poseRequest.results?.first else {
                return
            }
            
            // Create a PoseFrame and deliver it
            let poseFrame = PoseFrame(observation: observation, timestamp: Date())
            onPoseDetected?(poseFrame)
            
        } catch {
            print("Pose detection failed: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    /// Convert AVCaptureVideoOrientation to CGImagePropertyOrientation
    private func cgImageOrientation(from videoOrientation: AVCaptureVideoOrientation) -> CGImagePropertyOrientation {
        switch videoOrientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeRight:
            return .up
        case .landscapeLeft:
            return .down
        @unknown default:
            return .right
        }
    }
}
