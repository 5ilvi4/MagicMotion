// PoseDetector.swift
// Uses Google's MediaPipe Tasks Vision to detect 33 body landmarks in each camera frame.
// MediaPipe is faster and more detailed than Apple Vision — it tracks fingers, feet, and face.
//
// COORDINATE SYSTEM (MediaPipe):
//   (0, 0) = TOP-LEFT of frame      ← same as the screen, no flip needed!
//   (1, 1) = BOTTOM-RIGHT of frame
//   x: 0.0 (left edge) → 1.0 (right edge)
//   y: 0.0 (top edge)  → 1.0 (bottom edge)

import MediaPipeTasksVision
import AVFoundation

// MARK: - MediaPipe Landmark Indices
// MediaPipe always returns exactly 33 landmarks in a fixed order.
// This enum gives each index a readable name so we don't have to memorise numbers.
enum MPLandmark: Int {
    case nose           = 0
    case leftEyeInner   = 1,  leftEye       = 2,  leftEyeOuter  = 3
    case rightEyeInner  = 4,  rightEye      = 5,  rightEyeOuter = 6
    case leftEar        = 7,  rightEar      = 8
    case mouthLeft      = 9,  mouthRight    = 10
    case leftShoulder   = 11, rightShoulder = 12
    case leftElbow      = 13, rightElbow    = 14
    case leftWrist      = 15, rightWrist    = 16
    case leftPinky      = 17, rightPinky    = 18
    case leftIndex      = 19, rightIndex    = 20
    case leftThumb      = 21, rightThumb    = 22
    case leftHip        = 23, rightHip      = 24
    case leftKnee       = 25, rightKnee     = 26
    case leftAnkle      = 27, rightAnkle    = 28
    case leftHeel       = 29, rightHeel     = 30
    case leftFootIndex  = 31, rightFootIndex = 32
}

// MARK: - Data Structures

/// One landmark point from MediaPipe — position + confidence scores.
struct LandmarkPoint {
    let x: Float           // 0..1, left → right
    let y: Float           // 0..1, top  → bottom
    let z: Float           // Depth (negative = in front of camera)
    let visibility: Float  // How likely this point is visible (0..1)
}

/// All 33 landmarks from one camera frame plus a timestamp.
struct PoseFrame {
    /// Always 33 entries (one per MPLandmark). Empty array = no person detected.
    let landmarks: [LandmarkPoint]
    let timestamp: TimeInterval

    /// Safe subscript: returns nil if the landmark isn't visible enough.
    subscript(_ landmark: MPLandmark) -> LandmarkPoint? {
        guard landmarks.count > landmark.rawValue else { return nil }
        let lm = landmarks[landmark.rawValue]
        // Only return the landmark if MediaPipe is reasonably confident it's visible
        return lm.visibility > 0.5 ? lm : nil
    }

    /// Midpoint between left and right hip — used for lean detection.
    var hipMidpoint: CGPoint? {
        guard let lh = self[.leftHip], let rh = self[.rightHip] else { return nil }
        return CGPoint(x: CGFloat((lh.x + rh.x) / 2),
                       y: CGFloat((lh.y + rh.y) / 2))
    }
}

// MARK: - Skeleton Connections
// Pairs of MPLandmark indices to draw lines between (the "bones").
let skeletonConnections: [(MPLandmark, MPLandmark)] = [
    // Face outline
    (.nose, .leftEyeInner), (.leftEyeInner, .leftEye), (.leftEye, .leftEyeOuter), (.leftEyeOuter, .leftEar),
    (.nose, .rightEyeInner), (.rightEyeInner, .rightEye), (.rightEye, .rightEyeOuter), (.rightEyeOuter, .rightEar),
    // Arms
    (.leftShoulder, .leftElbow),   (.leftElbow, .leftWrist),
    (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
    // Hands (just index finger tip for now)
    (.leftWrist, .leftIndex),  (.rightWrist, .rightIndex),
    // Torso
    (.leftShoulder, .rightShoulder),
    (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
    (.leftHip, .rightHip),
    // Legs
    (.leftHip, .leftKnee),   (.leftKnee, .leftAnkle),   (.leftAnkle, .leftFootIndex),
    (.rightHip, .rightKnee), (.rightKnee, .rightAnkle), (.rightAnkle, .rightFootIndex)
]

// MARK: - PoseDetector

/// Wraps MediaPipe PoseLandmarker and delivers PoseFrames on every camera frame.
class PoseDetector: NSObject {

    // The MediaPipe pose landmarker — the core detection engine
    private var poseLandmarker: PoseLandmarker?

    // Called with a fresh PoseFrame after each processed camera frame
    var onPoseDetected: ((PoseFrame) -> Void)?

    override init() {
        super.init()
        setupMediaPipe()
    }

    // MARK: - Setup

    /// Load the MediaPipe model and configure the landmarker for live camera use.
    private func setupMediaPipe() {
        // Look for the model file we added to the Xcode project bundle
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_full",
                                                ofType: "task") else {
            print("❌ pose_landmarker_full.task not found in bundle. Did you add it to Xcode?")
            return
        }

        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath

        // liveStream mode: MediaPipe calls our delegate asynchronously — best for camera
        options.runningMode = .liveStream
        options.poseLandmarkerLiveStreamDelegate = self

        // Only track one person at a time (the player)
        options.numPoses = 1

        // Confidence thresholds — lower = more detections but more false positives
        options.minPoseDetectionConfidence  = 0.5
        options.minPosePresenceConfidence   = 0.5
        options.minTrackingConfidence       = 0.5

        do {
            poseLandmarker = try PoseLandmarker(options: options)
            print("✅ MediaPipe PoseLandmarker ready")
        } catch {
            print("❌ Failed to create PoseLandmarker: \(error)")
        }
    }

    // MARK: - Public API

    /// Feed a camera frame into MediaPipe. Results come back via the delegate below.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let landmarker = poseLandmarker else { return }

        // Wrap the camera frame in MediaPipe's image format
        guard let mpImage = try? MPImage(sampleBuffer: sampleBuffer) else { return }

        // Timestamp in milliseconds (MediaPipe requires monotonically increasing values)
        let timestampMs = Int(CACurrentMediaTime() * 1000)

        do {
            try landmarker.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
        } catch {
            print("⚠️ MediaPipe detectAsync error: \(error)")
        }
    }
}

// MARK: - PoseLandmarkerLiveStreamDelegate

/// MediaPipe calls this method on a background thread when it finishes processing a frame.
extension PoseDetector: PoseLandmarkerLiveStreamDelegate {

    func poseLandmarker(_ poseLandmarker: PoseLandmarker,
                        didFinishDetection result: PoseLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {

        if let error = error {
            print("⚠️ MediaPipe detection error: \(error)")
            return
        }

        // result.landmarks is an array of people; we only track the first one
        guard let result = result,
              let rawLandmarks = result.landmarks.first else { return }

        // Convert MediaPipe's NormalizedLandmark array into our LandmarkPoint array
        let landmarks: [LandmarkPoint] = rawLandmarks.map { lm in
            LandmarkPoint(
                x:          lm.x,
                y:          lm.y,
                z:          lm.z,
                visibility: lm.visibility ?? 0
            )
        }

        let poseFrame = PoseFrame(landmarks: landmarks,
                                  timestamp: CACurrentMediaTime())
        onPoseDetected?(poseFrame)
    }
}
