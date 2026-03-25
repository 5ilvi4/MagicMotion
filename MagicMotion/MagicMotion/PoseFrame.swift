//
//  PoseFrame.swift
//  MagicMotion
//
//  A single frame of pose/skeleton data from Vision framework.
//

import Foundation
import Vision

/// Represents a single frame of detected body pose data.
struct PoseFrame {
    /// The detected body pose observation from Vision framework
    let observation: VNHumanBodyPoseObservation
    
    /// Timestamp when this frame was captured
    let timestamp: Date
    
    /// Normalized point (0...1) for a specific joint, or nil if not detected
    func point(for jointName: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        guard let recognizedPoint = try? observation.recognizedPoint(jointName),
              recognizedPoint.confidence > 0.1 else {
            return nil
        }
        return CGPoint(x: recognizedPoint.location.x, y: recognizedPoint.location.y)
    }
    
    /// Check if a specific joint is visible with good confidence
    func hasJoint(_ jointName: VNHumanBodyPoseObservation.JointName) -> Bool {
        return point(for: jointName) != nil
    }
}
