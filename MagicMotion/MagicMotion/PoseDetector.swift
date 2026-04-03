//
//  PoseDetector.swift
//  MagicMotion
//
//  Cross-platform pose detection wrapper
//  Supports: iOS (MediaPipe), Android (MediaPipe), Web (MediaPipe.js), Desktop (C++)
//

import AVFoundation
import Vision
#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

/// Protocol for platform-agnostic pose detection
protocol PoseDetectorDelegate: AnyObject {
    func poseDetector(_ detector: PoseDetector, didDetect frame: PoseFrame)
    func poseDetector(_ detector: PoseDetector, didFailWith error: Error)
}

/// Detects human body pose and converts to cross-platform PoseFrame format
class PoseDetector: PoseDetectorProtocol {
    typealias ImageType = CMSampleBuffer
    
    // MARK: - Properties
    
    weak var delegate: PoseDetectorDelegate?
    
    /// Callback invoked when a pose is successfully detected
    var onPoseDetected: ((PoseFrame) -> Void)?
    
    private var frameCounter = 0
    private var lastTimestamp: TimeInterval = 0
    
    /// MediaPipe integration (when available)
    /// Uncomment when MediaPipe is installed:
    // private var mediaPipePoseDetector: MediaPipePoseDetector?
    
    /// The Vision request that detects body pose (fallback for now)
    private lazy var poseRequest: VNDetectHumanBodyPoseRequest = {
        let request = VNDetectHumanBodyPoseRequest()
        request.revision = VNDetectHumanBodyPoseRequestRevision1
        return request
    }()
    
    // MARK: - Initialization
    
    init(modelPath: String) throws {
        // Initialize with MediaPipe when available
        // TODO: Uncomment when MediaPipe framework is linked:
        // mediaPipePoseDetector = try MediaPipePoseDetector(modelPath: modelPath)
    }
    
    // MARK: - PoseDetectorProtocol Implementation
    
    /// Detect pose synchronously
    func detect(image: CMSampleBuffer) -> PoseFrame? {
        // Try MediaPipe first if available
        // if let mediaPipePoseDetector = mediaPipePoseDetector {
        //     return mediaPipePoseDetector.detect(image: image)
        // }
        
        // Fallback to Vision framework
        return detectWithVision(image)
    }
    
    /// Detect pose asynchronously (preferred for real-time)
    func detectAsync(image: CMSampleBuffer, completion: @escaping (PoseFrame?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.detect(image: image)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    /// Stop detection and clean up resources
    func stop() {
        // Clean up MediaPipe if needed
        // mediaPipePoseDetector?.stop()
    }
    
    // MARK: - Processing
    
    /// Process a video frame and detect body pose (for real-time camera)
    func processFrame(_ sampleBuffer: CMSampleBuffer, orientation: AVCaptureVideoOrientation) {
        frameCounter += 1
        let currentTimestamp = Date().timeIntervalSince1970
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Convert to CGImagePropertyOrientation
        let imageOrientation = cgImageOrientation(from: orientation)
        
        // Create Vision request handler
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: imageOrientation,
            options: [:]
        )
        
        do {
            // Perform pose detection
            try handler.perform([poseRequest])
            
            // Extract the first detected person
            guard let observation = poseRequest.results?.first else {
                return
            }
            
            // Convert to cross-platform PoseFrame
            let poseFrame = convertVisionObservationToPoseFrame(
                observation,
                timestamp: currentTimestamp,
                frameId: frameCounter
            )
            
            // Deliver via callbacks
            onPoseDetected?(poseFrame)
            delegate?.poseDetector(self, didDetect: poseFrame)
            lastTimestamp = currentTimestamp
            
        } catch {
            print("❌ Pose detection failed: \(error)")
            delegate?.poseDetector(self, didFailWith: error)
        }
    }
    
    // MARK: - Vision Framework Integration
    
    private func detectWithVision(_ sampleBuffer: CMSampleBuffer) -> PoseFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )
        
        do {
            try handler.perform([poseRequest])
            guard let observation = poseRequest.results?.first else {
                return nil
            }
            
            frameCounter += 1
            return convertVisionObservationToPoseFrame(
                observation,
                timestamp: Date().timeIntervalSince1970,
                frameId: frameCounter
            )
        } catch {
            print("Vision detection error: \(error)")
            return nil
        }
    }
    
    /// Convert Vision framework observation to cross-platform PoseFrame
    private func convertVisionObservationToPoseFrame(
        _ observation: VNHumanBodyPoseObservation,
        timestamp: TimeInterval,
        frameId: Int
    ) -> PoseFrame {
        var landmarks: [PoseFrame.Landmark] = []
        
        do {
            // Extract all available landmarks from Vision
            let availableJoints = try observation.recognizedPoints(.all)
            
            // Map Vision joints to MediaPipe indices (Vision uses fewer points)
            for (jointName, point) in availableJoints {
                guard point.confidence > 0.5 else { continue }
                
                let index = mapVisionJointToMediaPipeIndex(jointName)
                let landmark = PoseFrame.Landmark(
                    x: Float(point.location.x),
                    y: Float(point.location.y),
                    z: 0.0,  // Vision doesn't provide depth; MediaPipe will
                    visibility: Float(point.confidence),
                    index: index
                )
                landmarks.append(landmark)
            }
        } catch {
            print("Error extracting landmarks: \(error)")
        }
        
        // Pad with invisible landmarks to match MediaPipe's 33 points
        while landmarks.count < 33 {
            landmarks.append(PoseFrame.Landmark(
                x: 0, y: 0, z: 0,
                visibility: 0,
                index: landmarks.count
            ))
        }
        
        // Sort by index
        landmarks.sort { $0.index < $1.index }
        
        let confidence = landmarks
            .filter { $0.visibility > 0.5 }
            .map { $0.visibility }
            .reduce(0, +) / Float(landmarks.count)
        
        return PoseFrame(
            landmarks: Array(landmarks.prefix(33)),
            timestamp: timestamp,
            confidence: confidence,
            isValid: confidence > 0.5,
            frameId: frameId
        )
    }
    
    /// Map Vision joint names to MediaPipe landmark indices
    private func mapVisionJointToMediaPipeIndex(_ jointName: VNHumanBodyPoseObservation.JointName) -> Int {
        switch jointName {
        case .nose: return 0
        case .leftEye: return 2
        case .rightEye: return 5
        case .leftEar: return 7
        case .rightEar: return 8
        case .leftShoulder: return 11
        case .rightShoulder: return 12
        case .leftElbow: return 13
        case .rightElbow: return 14
        case .leftWrist: return 15
        case .rightWrist: return 16
        case .leftHip: return 23
        case .rightHip: return 24
        case .leftKnee: return 25
        case .rightKnee: return 26
        case .leftAnkle: return 27
        case .rightAnkle: return 28
        @unknown default: return 32
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
