// MotionEngine.swift
// MotionMind
//
// Wraps MediaPipe PoseLandmarker and exposes only app-level PoseSnapshot types.
// RULE: This is the ONLY file in the project that imports MediaPipeTasksVision.

import Combine
import Foundation
import AVFoundation
import UIKit

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

// MARK: - Delegate protocol (no MediaPipe types exposed)

protocol MotionEngineDelegate: AnyObject {
    func motionEngine(_ engine: MotionEngine, didOutput snapshot: PoseSnapshot)
    func motionEngineDidLoseTracking(_ engine: MotionEngine)
}

// MARK: - MotionEngine

/// Processes raw CMSampleBuffers through MediaPipe and emits PoseSnapshots.
class MotionEngine: NSObject, ObservableObject {

    weak var delegate: MotionEngineDelegate?

    /// Optional secondary callback for every emitted PoseSnapshot (e.g. session logger).
    var onPoseSnapshot: ((PoseSnapshot) -> Void)?

    /// Latest snapshot — published for overlay views that need direct access.
    @Published private(set) var latestSnapshot: PoseSnapshot?

    /// Rolling FPS measured over 1-second windows.
    @Published private(set) var fps: Double = 0
    private var fpsFrameCount = 0
    private var fpsWindowStart = Date()

    // MARK: - Private

    #if canImport(MediaPipeTasksVision)
    private var poseLandmarker: PoseLandmarker?
    #endif

    private var consecutiveMisses = 0
    private let maxMissesBeforeLost = 5
    private var isSetUp = false

    // MARK: - Init

    override init() {
        super.init()
        setupMediaPipe()
    }

    func setupMediaPipe() {
        guard !isSetUp else { return }
        #if canImport(MediaPipeTasksVision)
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") else {
            print("⚠️ MotionEngine: pose_landmarker_full.task not found in bundle")
            return  // not marked as set up — allows retry if bundle changes
        }
        do {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .liveStream
            options.minPoseDetectionConfidence = 0.5
            options.minPosePresenceConfidence  = 0.5
            options.minTrackingConfidence      = 0.5
            options.poseLandmarkerLiveStreamDelegate = self
            poseLandmarker = try PoseLandmarker(options: options)
            isSetUp = true  // only set on successful detector creation
            print("✅ MotionEngine: MediaPipe PoseLandmarker ready")
        } catch {
            print("❌ MotionEngine: Failed to init PoseLandmarker — \(error)")
            // not marked as set up — allows retry after transient failures
        }
        #else
        isSetUp = true  // no detector to create; mark done to suppress repeated prints
        print("⚠️ MotionEngine: MediaPipeTasksVision not available in this build")
        #endif
    }

    // MARK: - Frame processing

    /// Call this from the FrameSource callback.
    func processFrame(_ sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        #if canImport(MediaPipeTasksVision)
        guard let landmarker = poseLandmarker else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let mpImage: MPImage
        do {
            mpImage = try MPImage(pixelBuffer: pixelBuffer)
        } catch {
            return
        }

        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)
        do {
            try landmarker.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
        } catch {
            print("MotionEngine detectAsync error: \(error)")
        }
        #endif
    }
}

// MARK: - PoseLandmarkerLiveStreamDelegate

#if canImport(MediaPipeTasksVision)
extension MotionEngine: PoseLandmarkerLiveStreamDelegate {

    func poseLandmarker(_ poseLandmarker: PoseLandmarker,
                        didFinishDetection result: PoseLandmarkerResult?,
                        timestampInMilliseconds timestamp: Int,
                        error: Error?) {

        if let error = error {
            print("MotionEngine delegate error: \(error)")
            handleMiss()
            return
        }

        guard let result = result, let pose = result.landmarks.first else {
            handleMiss()
            return
        }

        consecutiveMisses = 0

        let landmarks = pose  // [NormalizedLandmark]
        func lm(_ idx: Int) -> PoseSnapshot.Landmark? {
            guard idx < landmarks.count else { return nil }
            let l = landmarks[idx]
            let vis = l.visibility ?? 0
            guard let vis = l.visibility?.floatValue, vis > 0.3 else { return nil }
            return PoseSnapshot.Landmark(
                x: l.x,
                y: l.y,
                z: l.z,
                visibility: vis
            )
        }
        // Compute overall confidence as average visibility of key landmarks
        let keyIndices = [11, 12, 23, 24, 25, 26, 27, 28]
        let visibilities = keyIndices.compactMap { i -> Float? in
            guard i < landmarks.count else { return nil }
            return landmarks[i].visibility?.floatValue
        }
        // Divide by actual visible count, not keyIndices.count.
        // Previously dividing by 8 always deflated confidence when landmarks
        // were partially occluded, producing values of 0.18–0.20 even during
        // normal tracking and causing the confidence gate to reject all frames.
        let avgVis = visibilities.isEmpty ? 0 : visibilities.reduce(0, +) / Float(visibilities.count)

        let snapshot = PoseSnapshot(
            timestamp:          Date(),
            trackingConfidence: avgVis,
            nose:           lm(0),
            leftEye:        lm(2),
            rightEye:       lm(5),
            leftEar:        lm(7),
            rightEar:       lm(8),
            leftShoulder:   lm(11),
            rightShoulder:  lm(12),
            leftElbow:      lm(13),
            rightElbow:     lm(14),
            leftWrist:      lm(15),
            rightWrist:     lm(16),
            leftHip:        lm(23),
            rightHip:       lm(24),
            leftKnee:       lm(25),
            rightKnee:      lm(26),
            leftAnkle:      lm(27),
            rightAnkle:     lm(28),
            leftHeel:       lm(29),
            rightHeel:      lm(30),
            leftFootIndex:  lm(31),
            rightFootIndex: lm(32)
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.latestSnapshot = snapshot
            self.delegate?.motionEngine(self, didOutput: snapshot)
            self.onPoseSnapshot?(snapshot)
            // Rolling FPS
            self.fpsFrameCount += 1
            let elapsed = Date().timeIntervalSince(self.fpsWindowStart)
            if elapsed >= 1.0 {
                self.fps = Double(self.fpsFrameCount) / elapsed
                self.fpsFrameCount = 0
                self.fpsWindowStart = Date()
            }
        }
    }

    private func handleMiss() {
        consecutiveMisses += 1
        if consecutiveMisses >= maxMissesBeforeLost {
            consecutiveMisses = 0
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.motionEngineDidLoseTracking(self)
            }
        }
    }
}
#endif
