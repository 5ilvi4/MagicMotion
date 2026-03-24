// PoseDetector.swift
// Uses Apple's Vision framework to find a person's body joints in each camera frame.
// Vision gives us 19 landmark points (joints) with X/Y positions and confidence scores.

import Vision
import CoreImage

// MARK: - Data Structures

/// The position of one body joint in a single frame.
struct JointPoint {
    let name: VNHumanBodyPoseObservation.JointName
    /// Normalised position: x and y are both 0.0 – 1.0.
    /// IMPORTANT: Vision uses bottom-left as origin (y=0 = bottom of frame).
    /// You must flip Y when drawing on screen (screen origin is top-left).
    let location: CGPoint
    /// How confident Vision is that this joint is correctly placed (0 = low, 1 = high)
    let confidence: Float
}

/// All detected joints from one camera frame, plus a timestamp.
struct PoseFrame {
    let joints:    [VNHumanBodyPoseObservation.JointName: JointPoint]
    let timestamp: TimeInterval   // Seconds since app launched (from CACurrentMediaTime)

    // Convenience shortcuts for the joints we use in gesture detection
    var leftHip:    JointPoint? { joints[.leftHip]    }
    var rightHip:   JointPoint? { joints[.rightHip]   }
    var leftAnkle:  JointPoint? { joints[.leftAnkle]  }
    var rightAnkle: JointPoint? { joints[.rightAnkle] }
    var leftWrist:  JointPoint? { joints[.leftWrist]  }
    var rightWrist: JointPoint? { joints[.rightWrist] }

    /// Midpoint between both hips — used to detect left/right lean.
    var hipMidpoint: CGPoint? {
        guard let lh = leftHip, let rh = rightHip else { return nil }
        return CGPoint(
            x: (lh.location.x + rh.location.x) / 2,
            y: (lh.location.y + rh.location.y) / 2
        )
    }
}

// MARK: - PoseDetector

/// Runs VNDetectHumanBodyPoseRequest on every camera frame and delivers PoseFrames.
class PoseDetector {

    // The Vision request object — reused every frame (more efficient than creating new ones)
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()

    // Called with a fresh PoseFrame after every processed camera frame
    var onPoseDetected: ((PoseFrame) -> Void)?

    // MARK: All 19 joints Vision can detect (used for skeleton overlay)
    static let allJoints: [VNHumanBodyPoseObservation.JointName] = [
        .nose,
        .leftEye,        .rightEye,
        .leftEar,        .rightEar,
        .neck,
        .leftShoulder,   .rightShoulder,
        .leftElbow,      .rightElbow,
        .leftWrist,      .rightWrist,
        .leftHip,        .rightHip,
        .leftKnee,       .rightKnee,
        .leftAnkle,      .rightAnkle,
        .root                                    // "root" = mid-pelvis point
    ]

    // MARK: Skeleton connections (pairs of joints to draw lines between)
    // Each tuple is (jointA, jointB) — draw a line from A to B.
    static let skeletonConnections: [(VNHumanBodyPoseObservation.JointName,
                                      VNHumanBodyPoseObservation.JointName)] = [
        // Face
        (.nose,          .leftEye),
        (.nose,          .rightEye),
        (.leftEye,       .leftEar),
        (.rightEye,      .rightEar),
        (.neck,          .nose),
        // Upper body
        (.neck,          .leftShoulder),
        (.neck,          .rightShoulder),
        (.leftShoulder,  .leftElbow),
        (.leftElbow,     .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow,    .rightWrist),
        // Torso
        (.neck,          .root),
        (.root,          .leftHip),
        (.root,          .rightHip),
        // Legs
        (.leftHip,       .leftKnee),
        (.leftKnee,      .leftAnkle),
        (.rightHip,      .rightKnee),
        (.rightKnee,     .rightAnkle)
    ]

    init() {
        // Limit to 1 person — we only want to track the player, not bystanders
        bodyPoseRequest.maximumHandCount = 1
    }

    // MARK: - Public API

    /// Process one camera frame.  Runs Vision synchronously on whatever thread calls this.
    /// - Parameter sampleBuffer: Raw video frame from AVFoundation
    /// - Parameter orientation:  Tells Vision which way is "up" in the image
    func processFrame(_ sampleBuffer: CMSampleBuffer,
                      orientation: CGImagePropertyOrientation) {
        // Extract the pixel buffer (raw image data) from the camera frame
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // VNImageRequestHandler wraps the image and runs Vision requests on it
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation:   orientation,
            options:       [:]
        )

        do {
            // Run body pose detection (~5–15 ms on modern iPad)
            try handler.perform([bodyPoseRequest])

            // bodyPoseRequest.results is an array of detected people — we want the first one
            guard let observations = bodyPoseRequest.results,
                  let bestPose = observations.first else {
                return   // No person in frame — skip this frame silently
            }

            let poseFrame = extractJoints(from: bestPose)
            onPoseDetected?(poseFrame)

        } catch {
            // Vision errors are usually non-fatal (e.g. blurry frame) — just log them
            print("⚠️ Vision error: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Pull each joint's screen position out of the Vision observation.
    private func extractJoints(
        from observation: VNHumanBodyPoseObservation
    ) -> PoseFrame {
        var joints: [VNHumanBodyPoseObservation.JointName: JointPoint] = [:]

        for jointName in Self.allJoints {
            // recognizedPoint can throw if the joint name is unsupported — guard against that
            guard let point = try? observation.recognizedPoint(jointName) else { continue }

            // Only keep joints Vision is reasonably confident about
            // 0.3 = 30% confidence threshold — lower this if skeleton is too sparse
            guard point.confidence > 0.3 else { continue }

            joints[jointName] = JointPoint(
                name:       jointName,
                location:   point.location,   // (0,0) = bottom-left in Vision space
                confidence: point.confidence
            )
        }

        return PoseFrame(joints: joints, timestamp: CACurrentMediaTime())
    }
}
