// MotionInterpreter.swift
// MotionMind
//
// Layer 3 — Motion Interpreter.
// Receives PoseSnapshot stream, classifies MotionEvents with smoothing + confidence gating.
// NO MediaPipeTasksVision import.

import Foundation
import Combine

// MARK: - GestureDebugInfo

/// Raw classifier inputs captured each frame for on-screen debugging.
struct GestureDebugInfo {
    var confidence: Float
    var isReliable: Bool
    var candidate: MotionEvent      // what classify() decided this frame (pre-confirmation)
    var pendingCount: Int           // frames accumulated toward confirmation
    // Raw landmark values (nil = landmark not visible)
    var leftWristY: Float?
    var rightWristY: Float?
    var leftShoulderY: Float?
    var rightShoulderY: Float?
    var leftHipY: Float?
    var rightHipY: Float?
    var hipCenterX: Float?
    var shoulderCenterX: Float?
    var leanDelta: Float?           // calibrated: hipCenter.x - shoulderCenter.x - neutralOffset (0 = personal neutral)
    var rawLeanDelta: Float?        // raw hip.x - shoulder.x before calibration
    var hipRise: Float?             // relative to oldest frame in buffer
    var hipDrop: Float?
    /// min(leftWristY - leftShoulderY, rightWristY - rightShoulderY)
    /// Negative means wrists ABOVE shoulders. More negative = higher hands.
    var handsUpScore: Float?
    var jumpMetric: Float?          // hipRise used by jump check (positive = up)
    var squatMetric: Float?         // hipDrop used by squat check (positive = down)
    var timestamp: Date

    static var empty: GestureDebugInfo {
        GestureDebugInfo(confidence: 0, isReliable: false, candidate: .none,
                         pendingCount: 0, leftWristY: nil, rightWristY: nil,
                         leftShoulderY: nil, rightShoulderY: nil,
                         leftHipY: nil, rightHipY: nil,
                         hipCenterX: nil, shoulderCenterX: nil,
                         leanDelta: nil, rawLeanDelta: nil,
                         hipRise: nil, hipDrop: nil,
                         handsUpScore: nil, jumpMetric: nil, squatMetric: nil,
                         timestamp: .distantPast)
    }
}

class MotionInterpreter: ObservableObject, MotionEngineDelegate {

    // MARK: - Published

    /// Display event — auto-clears after 0.8s. Use for momentary UI flash.
    @Published var currentEvent: MotionEvent = .none

    /// Last confirmed gesture — never auto-clears. Use for stable state display and transition logging.
    @Published private(set) var confirmedEvent: MotionEvent = .none

    /// Raw landmark values used by the last classify() call. Updated every frame.
    @Published var debugInfo: GestureDebugInfo = .empty

    // MARK: - Output

    var onMotionEvent: ((MotionEvent) -> Void)?

    // MARK: - Tuning (can be driven by AppSessionState in future)

    var confidenceGate: Float = 0.5        // snapshots below this are treated as .none
    var leanThreshold: Float = 0.10        // calibrated lean metric required to call a lean
    /// Wrists must be this far ABOVE shoulders (in y, where y=0 is TOP) to fire handsUp.
    /// 0.20 requires clearly raised arms; 0.05 was too easy to trigger accidentally.
    var handsUpMargin: Float = 0.20
    /// Hip vertical displacement (relative to oldest buffer frame) required for jump/squat.
    /// 0.15 reduces false fires from postural sway and camera wobble during standing.
    var verticalJumpThreshold: Float = 0.15
    var freezeSDThreshold: Float = 0.02    // std-dev of hipCenter.x across buffer
    /// Wrists must be this far BELOW hips (normalized) to fire handsDown.
    /// Natural arm-at-sides sits ~0.05–0.10 below hip; 0.15 requires a deliberate downward reach.
    var handsDownMargin: Float = 0.15

    /// Debug: when true, only lean/neutral is classified. Use to verify lean sign in isolation.
    @Published var debugLeanOnly: Bool = false

    // MARK: - Private state

    private var buffer = RingBuffer<PoseSnapshot>(capacity: 15)

    // Confirmation gate: event must appear this many consecutive frames before firing
    private var pendingEvent: MotionEvent = .none
    private var pendingCount: Int = 0
    private let confirmationFrames = 3

    // Cooldown between fired events
    private var lastEventTime: Date = .distantPast
    private let cooldown: TimeInterval = 0.5

    // Last confirmed event — separate from currentEvent which auto-clears for display.
    // Transition logging uses this so "– → gesture" doesn't repeat after every 0.8s reset.
    private var lastConfirmedEvent: MotionEvent = .none

    // Freeze tracking
    private var freezeStartTime: Date? = nil

    // MARK: - Lean calibration
    // Records the natural hip-to-shoulder x offset of the person's standing posture
    // so threshold is applied relative to their individual neutral, not absolute zero.

    /// Auto-calibrated from the first `leanCalibrationTarget` reliable frames.
    /// Subtracted from raw leanDelta before threshold comparison.
    private(set) var leanNeutralOffset: Float = 0
    private var leanCalibrationSamples: [Float] = []
    private let leanCalibrationTarget = 30   // ~1 second at 30fps
    private(set) var isLeanCalibrated = false

    /// Clears the lean baseline so the next ~1s of reliable frames re-calibrates neutral.
    /// Call when the user taps "Recalibrate Lean" or changes position significantly.
    func resetLeanCalibration() {
        leanNeutralOffset = 0
        leanCalibrationSamples = []
        isLeanCalibrated = false
        print("🕹️ [Lean] Calibration reset — collecting new baseline")
    }

    // MARK: - MotionEngineDelegate

    func motionEngine(_ engine: MotionEngine, didOutput snapshot: PoseSnapshot) {
        addSnapshot(snapshot)
    }

    func motionEngineDidLoseTracking(_ engine: MotionEngine) {
        pushConfirmation(.none)
    }

    // MARK: - Core

    func addSnapshot(_ snapshot: PoseSnapshot) {
        buffer.push(snapshot)

        // Accumulate calibration samples during the first ~1s of reliable tracking.
        if !isLeanCalibrated, snapshot.isReliable,
           let hip = snapshot.hipCenter, let shoulder = snapshot.shoulderCenter {
            leanCalibrationSamples.append(hip.x - shoulder.x)
            if leanCalibrationSamples.count >= leanCalibrationTarget {
                leanNeutralOffset = leanCalibrationSamples.reduce(0, +) / Float(leanCalibrationSamples.count)
                isLeanCalibrated = true
                print("🕹️ [Lean] Calibrated neutral offset: \(String(format: "%+.3f", leanNeutralOffset))")
            }
        }

        guard buffer.count >= 5 else { return }

        let classified: MotionEvent
        if !snapshot.isReliable {
            classified = .none
        } else {
            classified = classify(latest: snapshot)
        }

        pushConfirmation(classified)

        // Publish raw debug info every frame (on main actor via DispatchQueue.main).
        let frames = buffer.elements
        let oldHip = frames.first?.hipCenter
        let nowHip = snapshot.hipCenter
        let rawLean: Float? = {
            guard let h = snapshot.hipCenter, let s = snapshot.shoulderCenter else { return nil }
            return h.x - s.x
        }()
        let calibLean: Float? = rawLean.map { $0 - leanNeutralOffset }
        let handsUpScore: Float? = {
            guard let lw = snapshot.leftWrist,  let ls = snapshot.leftShoulder,
                  let rw = snapshot.rightWrist, let rs = snapshot.rightShoulder else { return nil }
            // Both wrists vs their respective shoulders. Negative = wrists above shoulders.
            return min(lw.y - ls.y, rw.y - rs.y)
        }()
        let jumpMetric: Float?  = (oldHip != nil && nowHip != nil) ? oldHip!.y - nowHip!.y : nil
        let squatMetric: Float? = (oldHip != nil && nowHip != nil) ? nowHip!.y - oldHip!.y : nil
        let info = GestureDebugInfo(
            confidence: snapshot.trackingConfidence,
            isReliable: snapshot.isReliable,
            candidate: classified,
            pendingCount: pendingCount,
            leftWristY: snapshot.leftWrist?.y,
            rightWristY: snapshot.rightWrist?.y,
            leftShoulderY: snapshot.leftShoulder?.y,
            rightShoulderY: snapshot.rightShoulder?.y,
            leftHipY: snapshot.leftHip?.y,
            rightHipY: snapshot.rightHip?.y,
            hipCenterX: snapshot.hipCenter?.x,
            shoulderCenterX: snapshot.shoulderCenter?.x,
            leanDelta: calibLean,
            rawLeanDelta: rawLean,
            hipRise: jumpMetric,
            hipDrop: squatMetric,
            handsUpScore: handsUpScore,
            jumpMetric: jumpMetric,
            squatMetric: squatMetric,
            timestamp: snapshot.timestamp
        )
        DispatchQueue.main.async { [weak self] in self?.debugInfo = info }
    }

    // MARK: - Classifiers

    private func classify(latest: PoseSnapshot) -> MotionEvent {
        let frames = buffer.elements

        // --- leanLeft / leanRight ---
        // Gated: no lean fires until calibration has completed (~1s of reliable frames).
        // Uses calibrated metric: raw delta minus the person's natural standing offset.
        // abs(calibrated) < leanThreshold => neutral deadzone.
        if isLeanCalibrated,
           let hip = latest.hipCenter, let shoulder = latest.shoulderCenter {
            let rawDelta = hip.x - shoulder.x
            let calibrated = rawDelta - leanNeutralOffset
            if calibrated < -leanThreshold { return .leanLeft  }
            if calibrated >  leanThreshold { return .leanRight }
        }

        // debugLeanOnly: skip all other recognizers — use to verify lean sign in isolation.
        if debugLeanOnly { return .none }

        // --- handsUp ---
        // Requires wrists clearly above shoulders (handsUpMargin = 0.20).
        // y=0 is top: wrist y < shoulder y - margin means wrist is well ABOVE shoulder.
        if let lw = latest.leftWrist, let rw = latest.rightWrist,
           let ls = latest.leftShoulder, let rs = latest.rightShoulder {
            if lw.y < ls.y - handsUpMargin && rw.y < rs.y - handsUpMargin {
                return .handsUp
            }
        }

        // --- jump (hip rose relative to oldest frame in buffer) ---
        if frames.count >= 11,
           let oldHip = frames[0].hipCenter,
           let nowHip = latest.hipCenter {
            // y decreases upward in MediaPipe
            let hipRise = oldHip.y - nowHip.y  // positive = moved up
            if hipRise > verticalJumpThreshold {
                return .jump
            }
        }

        // --- squat (hip dropped relative to oldest frame) ---
        if frames.count >= 11,
           let oldHip = frames[0].hipCenter,
           let nowHip = latest.hipCenter {
            let hipDrop = nowHip.y - oldHip.y  // positive = moved down
            if hipDrop > verticalJumpThreshold {
                return .squat
            }
        }

        // --- handsDown ---
        // Checked last among arm/body events. Requires handsDownMargin below hips to avoid
        // firing in neutral arm-at-sides posture (~0.05–0.10 below hip in practice).
        if let lw = latest.leftWrist, let rw = latest.rightWrist,
           let lh = latest.leftHip, let rh = latest.rightHip {
            if lw.y > lh.y + handsDownMargin && rw.y > rh.y + handsDownMargin {
                return .handsDown
            }
        }

        // --- freeze (std-dev of hipCenter.x < threshold) ---
        if frames.count == buffer.capacity {
            let xs = frames.compactMap { $0.hipCenter?.x }
            if xs.count == buffer.capacity {
                let mean = xs.reduce(0, +) / Float(xs.count)
                let variance = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(xs.count)
                let sd = sqrt(variance)
                if sd < freezeSDThreshold {
                    let now = Date()
                    if freezeStartTime == nil { freezeStartTime = now }
                    let duration = now.timeIntervalSince(freezeStartTime!)
                    return .freeze(duration: duration)
                }
            }
        }

        // Reset freeze timer when body moves
        freezeStartTime = nil

        return .none
    }

    // MARK: - Confirmation + cooldown

    private func pushConfirmation(_ event: MotionEvent) {
        if event == pendingEvent {
            pendingCount += 1
        } else {
            pendingEvent = event
            pendingCount = 1
        }

        guard pendingCount >= confirmationFrames else { return }
        guard event != .none else {
            // Publish .none immediately (clears display).
            // Also reset lastConfirmedEvent so the next real gesture logs a clean transition.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.lastConfirmedEvent != .none {
                    print("🕹️ Gesture: \(self.lastConfirmedEvent.displayName) → neutral")
                    self.lastConfirmedEvent = .none
                    self.confirmedEvent = .none
                }
                self.currentEvent = .none
            }
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastEventTime) >= cooldown else { return }

        lastEventTime = now
        pendingCount = 0  // reset so the same event can re-fire after cooldown

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Log and forward only on state transition — prevents repeated BLE commands
            // and coordinator spam while the user holds the same gesture.
            if self.lastConfirmedEvent != event {
                print("🕹️ Gesture: \(self.lastConfirmedEvent.displayName) → \(event.displayName)")
                self.lastConfirmedEvent = event
                self.confirmedEvent = event
                self.onMotionEvent?(event)
            }
            self.currentEvent = event
        }

        // Auto-clear display after 0.8s (does not affect lastConfirmedEvent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.currentEvent = .none
        }
    }
}
