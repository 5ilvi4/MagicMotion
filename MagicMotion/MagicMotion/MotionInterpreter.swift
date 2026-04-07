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

    var confidenceGate: Float = 0.6        // entry and classify gate; 0.6 > isReliable's hardcoded 0.5
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

    // MARK: - Profile-driven configuration

    /// Which recognizers are active for the current game. nil = all enabled (default).
    private var enabledRecognizers: Set<RecognizerID>? = nil

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

    func apply(profile: GameProfile) {
        if let list = profile.enabledRecognizers {
            enabledRecognizers = Set(list)
        } else {
            enabledRecognizers = nil
        }

        let leanCfg      = profile.config(for: .bodyLean)
        let jumpCfg      = profile.config(for: .bodyJump)
        let squatCfg     = profile.config(for: .bodySquat)
        let handsUpCfg   = profile.config(for: .bodyHandsUp)
        let handsDownCfg = profile.config(for: .bodyHandsDown)

        if let v = leanCfg["threshold"]    { leanThreshold         = Float(v) }
        if let v = jumpCfg["threshold"]    { verticalJumpThreshold = Float(v) }
        if let v = squatCfg["threshold"]   { verticalJumpThreshold = Float(v) }
        if let v = handsUpCfg["margin"]    { handsUpMargin         = Float(v) }
        if let v = handsDownCfg["margin"]  { handsDownMargin       = Float(v) }

        let label = enabledRecognizers.map { $0.map(\.rawValue).sorted().joined(separator: ",") } ?? "all"
        print("🕹️ [MotionInterpreter] Applied profile '\(profile.displayName)' — enabled: \(label)")
    }

    private func isEnabled(_ id: RecognizerID) -> Bool {
        guard let set = enabledRecognizers else { return true }
        return set.contains(id)
    }

    // MARK: - MotionEngineDelegate

    func motionEngine(_ engine: MotionEngine, didOutput snapshot: PoseSnapshot) {
        // Confidence gate — frames at or below confidenceGate are discarded before
        // entering the pipeline. Prevents partial/corrupt-landmark frames from
        // accumulating in the ring buffer, building up pending counts, or skewing
        // lean calibration samples.
        guard snapshot.trackingConfidence > confidenceGate else {
            #if DEBUG
            print("🕹️ [MotionInterpreter] Frame rejected: confidence \(String(format: "%.2f", snapshot.trackingConfidence)) ≤ \(confidenceGate)")
            #endif
            return
        }

        // Core landmark bounds gate — rejects off-frame coordinates (e.g. y < 0) that
        // pass MediaPipe's visibility threshold but carry geometrically invalid values.
        // All four core landmarks must be present and within normalized [0, 1] space
        // before the frame is allowed to affect buffer state or calibration.
        guard let ls = snapshot.leftShoulder,  let rs = snapshot.rightShoulder,
              let lh = snapshot.leftHip,       let rh = snapshot.rightHip,
              ls.x >= 0, ls.x <= 1, ls.y >= 0, ls.y <= 1,
              rs.x >= 0, rs.x <= 1, rs.y >= 0, rs.y <= 1,
              lh.x >= 0, lh.x <= 1, lh.y >= 0, lh.y <= 1,
              rh.x >= 0, rh.x <= 1, rh.y >= 0, rh.y <= 1 else {
            #if DEBUG
            let coords = [snapshot.leftShoulder, snapshot.rightShoulder,
                          snapshot.leftHip, snapshot.rightHip]
                .map { lm -> String in
                    guard let lm else { return "nil" }
                    return "(\(String(format: "%.3f", lm.x)),\(String(format: "%.3f", lm.y)))"
                }
            print("🕹️ [MotionInterpreter] Frame rejected: core landmark out of bounds — LS:\(coords[0]) RS:\(coords[1]) LH:\(coords[2]) RH:\(coords[3])")
            #endif
            return
        }

        addSnapshot(snapshot)
    }

    func motionEngineDidLoseTracking(_ engine: MotionEngine) {
        // Hard reset on tracking loss — clears buffer, pending confirmation state, freeze
        // timer, and lean calibration so no stale gesture state survives into the next
        // tracking session. pushConfirmation(.none) alone was insufficient: it only sets
        // pendingCount = 1, which never reaches confirmationFrames (3) when no further
        // frames arrive while tracking is lost.
        buffer = RingBuffer<PoseSnapshot>(capacity: buffer.capacity)
        pendingEvent = .none
        pendingCount = 0
        freezeStartTime = nil
        resetLeanCalibration()
        print("🕹️ [MotionInterpreter] Tracking lost — full state reset")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastConfirmedEvent = .none
            self.confirmedEvent = .none
            self.currentEvent = .none
        }
    }

    // MARK: - Core

    func addSnapshot(_ snapshot: PoseSnapshot) {
        buffer.push(snapshot)

        // Accumulate calibration samples during the first ~1s of reliable tracking.
        // confidenceGate replaces PoseSnapshot.isReliable's hardcoded 0.5 so this
        // threshold is tunable from the same knob as the entry gate.
        if !isLeanCalibrated, snapshot.trackingConfidence > confidenceGate,
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
        // confidenceGate replaces PoseSnapshot.isReliable's hardcoded 0.5 threshold.
        if snapshot.trackingConfidence <= confidenceGate {
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

        // STEP 1 — Core landmark guard.
        // Redundant with entry guard but defensive — classify() is also callable
        // from tests with synthetic snapshots that bypass motionEngine(_:didOutput:).
        // ls, rs, lh, rh remain in scope for all subsequent steps.
        guard let ls = latest.leftShoulder,  let rs = latest.rightShoulder,
              let lh = latest.leftHip,       let rh = latest.rightHip,
              ls.x >= 0, ls.x <= 1, ls.y >= 0, ls.y <= 1,
              rs.x >= 0, rs.x <= 1, rs.y >= 0, rs.y <= 1,
              lh.x >= 0, lh.x <= 1, lh.y >= 0, lh.y <= 1,
              rh.x >= 0, rh.x <= 1, rh.y >= 0, rh.y <= 1 else {
            return .none
        }

        // STEP 2 — Lean left / lean right.
        // Gated: no lean fires until calibration has completed (~1s of reliable frames).
        // calibrated = (hipCenter.x - shoulderCenter.x) - leanNeutralOffset
        // leanThreshold = 0.10: deadzone of ±10% of frame width around personal neutral.
        if isLeanCalibrated, isEnabled(.bodyLean),
           let hip = latest.hipCenter, let shoulder = latest.shoulderCenter {
            let rawDelta   = hip.x - shoulder.x
            let calibrated = rawDelta - leanNeutralOffset
            if calibrated < -leanThreshold { return .leanLeft  }   // hip left of shoulder
            if calibrated >  leanThreshold { return .leanRight }   // hip right of shoulder
        }

        // STEP 3 — Lean-only debug mode: skip all remaining recognizers.
        // Enables verifying lean sign convention without interference from other gestures.
        if debugLeanOnly { return .none }

        // STEP 4 — Hands up.
        // y=0 is TOP of frame: wrist.y < shoulder.y means the wrist is physically above
        // the shoulder. handsUpMargin = 0.20 requires clearly raised arms — 0.05 was
        // too easily triggered by natural arm elevation during walking or gesturing.
        // Wrist landmarks are bounds-checked to prevent an off-frame wrist (y < 0 from
        // partial occlusion) from producing a falsely large negative margin.
        // ls and rs are already guaranteed non-nil and in-bounds by STEP 1.
        if isEnabled(.bodyHandsUp),
           let lw = latest.leftWrist, let rw = latest.rightWrist,
           lw.x >= 0, lw.x <= 1, lw.y >= 0, lw.y <= 1,
           rw.x >= 0, rw.x <= 1, rw.y >= 0, rw.y <= 1 {
            if lw.y < ls.y - handsUpMargin && rw.y < rs.y - handsUpMargin {
                return .handsUp
            }
        }

        // STEP 5 — Jump (hip rose relative to oldest frame in buffer).
        // Requires 11 frames so the reference hip position is ~367ms old at 30fps.
        // hipRise > 0: y decreased, meaning the hip moved upward (y=0 is top).
        // verticalJumpThreshold = 0.15: reduces false fires from postural sway and
        // camera wobble that can produce ~0.08 variation during normal standing.
        if isEnabled(.bodyJump), frames.count >= 11,
           let oldHip = frames[0].hipCenter,
           let nowHip = latest.hipCenter {
            let hipRise = oldHip.y - nowHip.y   // positive = hip moved up
            if hipRise > verticalJumpThreshold { return .jump }
        }

        // STEP 6 — Squat (hip dropped relative to oldest frame in buffer).
        // Same buffer depth as jump; opposite sign on the delta.
        if isEnabled(.bodySquat), frames.count >= 11,
           let oldHip = frames[0].hipCenter,
           let nowHip = latest.hipCenter {
            let hipDrop = nowHip.y - oldHip.y   // positive = hip moved down
            if hipDrop > verticalJumpThreshold { return .squat }
        }

        // STEP 7 — Hands down.
        // Checked last among arm events. handsDownMargin = 0.15 requires a deliberate
        // downward reach: natural arm-at-sides sits only ~0.05–0.10 below the hip.
        // Wrist landmarks are bounds-checked so a wrist below the bottom of the frame
        // (y > 1) does not falsely satisfy lw.y > lh.y + margin.
        // lh and rh are already guaranteed non-nil and in-bounds by STEP 1.
        if isEnabled(.bodyHandsDown),
           let lw = latest.leftWrist, let rw = latest.rightWrist,
           lw.x >= 0, lw.x <= 1, lw.y >= 0, lw.y <= 1,
           rw.x >= 0, rw.x <= 1, rw.y >= 0, rw.y <= 1 {
            if lw.y > lh.y + handsDownMargin && rw.y > rh.y + handsDownMargin {
                return .handsDown
            }
        }

        // STEP 8 — Freeze (std-dev of hipCenter.x across full buffer < threshold).
        // Only evaluated when the buffer is completely full (15 frames = ~0.5s at 30fps)
        // to ensure a stable positional baseline.
        // freezeSDThreshold = 0.02: ~2% of frame width; body must be essentially still.
        if frames.count == buffer.capacity {
            let xs = frames.compactMap { $0.hipCenter?.x }
            if xs.count == buffer.capacity {
                let mean     = xs.reduce(0, +) / Float(xs.count)
                let variance = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(xs.count)
                let sd       = sqrt(variance)
                if sd < freezeSDThreshold {
                    let now = Date()
                    if freezeStartTime == nil { freezeStartTime = now }
                    let duration = now.timeIntervalSince(freezeStartTime!)
                    return .freeze(duration: duration)
                }
            }
        }

        // Reset freeze timer whenever the body is in motion.
        freezeStartTime = nil

        // STEP 9 — No gesture detected.
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
