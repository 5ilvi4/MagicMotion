// HandEngine.swift
// MagicMotion
//
// Parallel pipeline: runs MediaPipe HandLandmarker on the same camera frames
// as MotionEngine, without touching the pose pipeline.
// RULE: this is the ONLY file that uses HandLandmarker.

import AVFoundation
import Combine
import Foundation

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

final class HandEngine: NSObject, ObservableObject {

    /// Up to 2 detected hands per frame. Empty when no hands visible.
    @Published private(set) var latestHands: [HandSnapshot] = []

    // MARK: - Private

    #if canImport(MediaPipeTasksVision)
    private var handLandmarker: HandLandmarker?
    #endif

    override init() {
        super.init()
        setup()
    }

    private func setup() {
        #if canImport(MediaPipeTasksVision)
        guard let modelPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") else {
            print("⚠️ HandEngine: hand_landmarker.task not found in bundle — download from mediapipe.dev")
            return
        }
        do {
            let options = HandLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .liveStream
            options.numHands = 2
            options.minHandDetectionConfidence = 0.5
            options.minHandPresenceConfidence  = 0.5
            options.minTrackingConfidence      = 0.5
            options.handLandmarkerLiveStreamDelegate = self
            handLandmarker = try HandLandmarker(options: options)
            print("✅ HandEngine: HandLandmarker ready")
        } catch {
            print("❌ HandEngine: init failed — \(error)")
        }
        #endif
    }

    /// Call this with every frame — same call site as MotionEngine.processFrame.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        #if canImport(MediaPipeTasksVision)
        guard let landmarker = handLandmarker,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let mpImage = try? MPImage(pixelBuffer: pixelBuffer) else { return }
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        try? landmarker.detectAsync(image: mpImage, timestampInMilliseconds: ts)
        #endif
    }
}

// MARK: - HandLandmarkerLiveStreamDelegate

#if canImport(MediaPipeTasksVision)
extension HandEngine: HandLandmarkerLiveStreamDelegate {

    func handLandmarker(_ handLandmarker: HandLandmarker,
                        didFinishDetection result: HandLandmarkerResult?,
                        timestampInMilliseconds timestamp: Int,
                        error: Error?) {
        if let error { print("HandEngine error: \(error)"); return }
        guard let result else { return }

        let hands: [HandSnapshot] = result.landmarks.enumerated().compactMap { (i, lmArray) in
            // handedness: result.handedness[i][0].categoryName == "Left"/"Right"
            let handednessLabel = result.handedness[safe: i]?.first?.categoryName ?? ""
            let handedness: HandSnapshot.Handedness = handednessLabel == "Left" ? .left :
                            handednessLabel == "Right" ? .right : .unknown
            let conf = result.handedness[safe: i]?.first?.score ?? 0

            // Build 21-element array; coordinates are normalized, visibility not always provided
            let landmarks: [HandSnapshot.Landmark?] = (0..<21).map { idx in
                guard idx < lmArray.count else { return nil }
                let l = lmArray[idx]
                return HandSnapshot.Landmark(x: l.x, y: l.y, z: l.z,
                                             visibility: l.visibility?.floatValue ?? 1.0)
            }
            return HandSnapshot(handedness: handedness, confidence: Float(conf), landmarks: landmarks)
        }

        DispatchQueue.main.async { [weak self] in
            self?.latestHands = hands
        }
    }
}
#endif

// MARK: - Safe array subscript (local)

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
