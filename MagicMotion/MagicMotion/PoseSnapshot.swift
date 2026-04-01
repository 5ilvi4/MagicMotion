// PoseSnapshot.swift
// MotionMind
//
// App-level pose type. NO MediaPipe imports.
// All layers above MotionEngine use this type only.

import Foundation

/// A single frame of pose data expressed entirely in app-level types.
/// Coordinates are normalized 0–1. In MediaPipe: y=0 is the TOP of the frame.
struct PoseSnapshot {
    let timestamp: Date
    /// Overall detection confidence (0–1). Use isReliable before classifying gestures.
    let trackingConfidence: Float

    struct Landmark {
        let x: Float       // normalized 0–1, 0 = left
        let y: Float       // normalized 0–1, 0 = TOP
        let z: Float       // depth, negative = closer to camera
        let visibility: Float  // 0–1
    }

    // All 33 MediaPipe landmarks as named optionals.
    // nil means the landmark was not present / below visibility threshold.
    var nose:           Landmark?
    var leftEye:        Landmark?
    var rightEye:       Landmark?
    var leftEar:        Landmark?
    var rightEar:       Landmark?
    var leftShoulder:   Landmark?
    var rightShoulder:  Landmark?
    var leftElbow:      Landmark?
    var rightElbow:     Landmark?
    var leftWrist:      Landmark?
    var rightWrist:     Landmark?
    var leftHip:        Landmark?
    var rightHip:       Landmark?
    var leftKnee:       Landmark?
    var rightKnee:      Landmark?
    var leftAnkle:      Landmark?
    var rightAnkle:     Landmark?
    var leftHeel:       Landmark?
    var rightHeel:      Landmark?
    var leftFootIndex:  Landmark?
    var rightFootIndex: Landmark?

    // MARK: - Convenience

    /// Snapshot is trustworthy enough to classify gestures.
    var isReliable: Bool { trackingConfidence > 0.5 }

    /// Mid-point between both hips. Nil if either hip is missing.
    var hipCenter: (x: Float, y: Float)? {
        guard let l = leftHip, let r = rightHip else { return nil }
        return ((l.x + r.x) / 2, (l.y + r.y) / 2)
    }

    /// Mid-point between both shoulders. Nil if either shoulder is missing.
    var shoulderCenter: (x: Float, y: Float)? {
        guard let l = leftShoulder, let r = rightShoulder else { return nil }
        return ((l.x + r.x) / 2, (l.y + r.y) / 2)
    }

    // MARK: - Empty snapshot (tracking lost)

    static func empty() -> PoseSnapshot {
        PoseSnapshot(timestamp: Date(), trackingConfidence: 0,
                     nose: nil, leftEye: nil, rightEye: nil,
                     leftEar: nil, rightEar: nil,
                     leftShoulder: nil, rightShoulder: nil,
                     leftElbow: nil, rightElbow: nil,
                     leftWrist: nil, rightWrist: nil,
                     leftHip: nil, rightHip: nil,
                     leftKnee: nil, rightKnee: nil,
                     leftAnkle: nil, rightAnkle: nil,
                     leftHeel: nil, rightHeel: nil,
                     leftFootIndex: nil, rightFootIndex: nil)
    }
}
