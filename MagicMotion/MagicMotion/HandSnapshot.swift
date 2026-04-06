// HandSnapshot.swift
// MagicMotion
//
// App-level hand pose type. NO MediaPipe imports.
// Mirrors PoseSnapshot pattern — only MotionEngine/HandEngine imports MediaPipe.
// Coordinates: normalized 0–1, y=0 is TOP (MediaPipe convention).

import Foundation

/// One detected hand with 21 finger landmarks.
struct HandSnapshot {
    enum Handedness { case left, right, unknown }
    let handedness: Handedness
    let confidence: Float

    struct Landmark {
        let x: Float   // normalized 0–1
        let y: Float   // normalized 0–1, 0 = TOP
        let z: Float
        let visibility: Float
    }

    // 21 MediaPipe hand landmarks (indices 0–20)
    let landmarks: [Landmark?]   // count always == 21; nil = below threshold

    // MARK: - Named convenience accessors

    var wrist:         Landmark? { landmarks[0] }
    var thumbCMC:      Landmark? { landmarks[1] }
    var thumbMCP:      Landmark? { landmarks[2] }
    var thumbIP:       Landmark? { landmarks[3] }
    var thumbTip:      Landmark? { landmarks[4] }
    var indexMCP:      Landmark? { landmarks[5] }
    var indexPIP:      Landmark? { landmarks[6] }
    var indexDIP:      Landmark? { landmarks[7] }
    var indexTip:      Landmark? { landmarks[8] }
    var middleMCP:     Landmark? { landmarks[9] }
    var middlePIP:     Landmark? { landmarks[10] }
    var middleDIP:     Landmark? { landmarks[11] }
    var middleTip:     Landmark? { landmarks[12] }
    var ringMCP:       Landmark? { landmarks[13] }
    var ringPIP:       Landmark? { landmarks[14] }
    var ringDIP:       Landmark? { landmarks[15] }
    var ringTip:       Landmark? { landmarks[16] }
    var pinkyMCP:      Landmark? { landmarks[17] }
    var pinkyPIP:      Landmark? { landmarks[18] }
    var pinkyDIP:      Landmark? { landmarks[19] }
    var pinkyTip:      Landmark? { landmarks[20] }
}

// Standard MediaPipe hand connections (index pairs)
let handConnections: [(Int, Int)] = [
    // Palm
    (0,1),(1,2),(2,3),(3,4),    // thumb
    (0,5),(5,6),(6,7),(7,8),    // index
    (0,9),(9,10),(10,11),(11,12), // middle
    (0,13),(13,14),(14,15),(15,16), // ring
    (0,17),(17,18),(18,19),(19,20), // pinky
    (5,9),(9,13),(13,17)        // knuckle row
]
