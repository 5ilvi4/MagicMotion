// FakeMotionSource.swift
// MotionMind
//
// Layer 6 — Diagnostics.
// Drives MotionInterpreter with scripted PoseSnapshots — no camera, no MediaPipe.

import Foundation
import Combine

/// A scripted pose replayer. Zero camera / MediaPipe dependencies.
class FakeMotionSource {

    weak var delegate: MotionEngineDelegate?

    private var workItem: DispatchWorkItem?

    // MARK: - Playback

    typealias Script = [(delay: TimeInterval, snapshot: PoseSnapshot)]

    func replay(script: Script) {
        stop()
        var cumulativeDelay: TimeInterval = 0
        let item = DispatchWorkItem {}
        workItem = item

        for entry in script {
            cumulativeDelay += entry.delay
            let snap = entry.snapshot
            DispatchQueue.main.asyncAfter(deadline: .now() + cumulativeDelay) { [weak self] in
                guard let self = self, !(self.workItem?.isCancelled ?? true) else { return }
                self.delegate?.motionEngine(
                    // FakeMotionSource is not a MotionEngine — pass a stub that satisfies the protocol
                    MotionEngineStub(), didOutput: snap)
            }
        }
    }

    func stop() {
        workItem?.cancel()
        workItem = nil
    }

    /// Convenience: emit a single MotionEvent directly by building a snapshot that will classify to it.
    func emit(event: MotionEvent) {
        let snap: PoseSnapshot
        switch event {
        case .handsUp:   snap = FakeMotionSource.handsUpScript.last?.snapshot ?? .empty()
        case .leanLeft:  snap = FakeMotionSource.leanLeftScript.last?.snapshot ?? .empty()
        case .leanRight: snap = FakeMotionSource.leanRightScript.last?.snapshot ?? .empty()
        case .jump:      snap = FakeMotionSource.jumpScript.last?.snapshot ?? .empty()
        case .squat:     snap = FakeMotionSource.squatScript.last?.snapshot ?? .empty()
        default:         snap = .empty()
        }
        delegate?.motionEngine(MotionEngineStub(), didOutput: snap)
    }

    // MARK: - Static fixture scripts

    /// Demo script cycling through all gestures — used as default for DEBUG mode.
    static let demoScript: Script = {
        handsUpScript + jumpScript + leanLeftScript + leanRightScript + squatScript + freezeScript
    }()

    /// 10 frames: both wrists raised above shoulders
    static let handsUpScript: Script = {
        let snap = standingPose(leftWristY: 0.10, rightWristY: 0.10)
        return Array(repeating: (delay: 0.033, snapshot: snap), count: 10)
    }()

    /// 10 frames: hip rises then falls (jump)
    static let jumpScript: Script = {
        var frames: Script = []
        // 5 frames rising
        for i in 0..<5 {
            let hipY = 0.60 - Float(i) * 0.04
            frames.append((delay: 0.033, snapshot: standingPose(hipY: hipY)))
        }
        // 5 frames falling
        for i in 0..<5 {
            let hipY = 0.40 + Float(i) * 0.04
            frames.append((delay: 0.033, snapshot: standingPose(hipY: hipY)))
        }
        return frames
    }()

    /// 10 frames: body leans left (hip shifts left of shoulder)
    static let leanLeftScript: Script = {
        let snap = standingPose(hipCenterX: 0.35, shoulderCenterX: 0.50)
        return Array(repeating: (delay: 0.033, snapshot: snap), count: 10)
    }()

    /// 10 frames: body leans right
    static let leanRightScript: Script = {
        let snap = standingPose(hipCenterX: 0.65, shoulderCenterX: 0.50)
        return Array(repeating: (delay: 0.033, snapshot: snap), count: 10)
    }()

    /// 10 frames: squat (hips drop)
    static let squatScript: Script = {
        var frames: Script = []
        for i in 0..<10 {
            let hipY = 0.60 + Float(i) * 0.01
            frames.append((delay: 0.033, snapshot: standingPose(hipY: hipY)))
        }
        return frames
    }()

    /// 30 frames: body completely still (freeze)
    static let freezeScript: Script = {
        let snap = standingPose()
        return Array(repeating: (delay: 0.033, snapshot: snap), count: 30)
    }()

    // MARK: - Pose factory

    /// Build a PoseSnapshot for a standing adult in normalized 0-1 space.
    /// Override specific coordinates to simulate motion.
    static func standingPose(
        hipCenterX:      Float = 0.50,
        shoulderCenterX: Float = 0.50,
        hipY:            Float = 0.60,
        leftWristY:      Float = 0.65,
        rightWristY:     Float = 0.65,
        confidence:      Float = 0.85
    ) -> PoseSnapshot {
        func lm(_ x: Float, _ y: Float) -> PoseSnapshot.Landmark {
            PoseSnapshot.Landmark(x: x, y: y, z: 0, visibility: confidence)
        }
        let lHipX  = hipCenterX - 0.07
        let rHipX  = hipCenterX + 0.07
        let lShX   = shoulderCenterX - 0.10
        let rShX   = shoulderCenterX + 0.10
        let shY: Float = 0.35

        return PoseSnapshot(
            timestamp:          Date(),
            trackingConfidence: confidence,
            nose:           lm(shoulderCenterX, 0.08),
            leftEye:        lm(shoulderCenterX - 0.02, 0.07),
            rightEye:       lm(shoulderCenterX + 0.02, 0.07),
            leftEar:        lm(shoulderCenterX - 0.06, 0.10),
            rightEar:       lm(shoulderCenterX + 0.06, 0.10),
            leftShoulder:   lm(lShX, shY),
            rightShoulder:  lm(rShX, shY),
            leftElbow:      lm(lShX - 0.06, 0.50),
            rightElbow:     lm(rShX + 0.06, 0.50),
            leftWrist:      lm(lShX - 0.07, leftWristY),
            rightWrist:     lm(rShX + 0.07, rightWristY),
            leftHip:        lm(lHipX, hipY),
            rightHip:       lm(rHipX, hipY),
            leftKnee:       lm(lHipX, hipY + 0.18),
            rightKnee:      lm(rHipX, hipY + 0.18),
            leftAnkle:      lm(lHipX, hipY + 0.35),
            rightAnkle:     lm(rHipX, hipY + 0.35),
            leftHeel:       lm(lHipX, hipY + 0.37),
            rightHeel:      lm(rHipX, hipY + 0.37),
            leftFootIndex:  lm(lHipX + 0.02, hipY + 0.38),
            rightFootIndex: lm(rHipX - 0.02, hipY + 0.38)
        )
    }
}

// MARK: - MotionEngineStub
// A dummy MotionEngine stand-in used so FakeMotionSource can call delegate methods
// without importing or constructing a real MotionEngine.
private class MotionEngineStub: MotionEngine {}
