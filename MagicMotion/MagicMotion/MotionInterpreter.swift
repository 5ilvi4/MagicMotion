// MotionInterpreter.swift
// MagicMotion
//
// Layer 3 — Motion Interpreter.
// Receives PoseSnapshot frames, classifies MotionEvents with smoothing + confidence
// gating, and publishes confirmed events downstream to InputCoordinator.
//
// Body-relative thresholds
// ────────────────────────
// All gesture thresholds are now expressed as:
//
//   effectiveThreshold = profileSensitivity × adaptationFactor × calibrationReference
//
// Where:
//   - profileSensitivity   is set by apply(profile:) from GameProfile recognizerConfig
//   - adaptationFactor     is the runtime multiplier (starts at 1.0, bounded ±30%)
//   - calibrationReference is a body-relative value from BodyCalibration
//     (shoulderWidth for lean, maxJumpRise for jump, torsoLength for hands gestures…)
//
// This means a short child and a tall child at different distances both fire gestures
// at the same perceived effort level, without manually retuning absolute thresholds.
//
// Calibration sources
// ───────────────────
// 1. Personalized (preferred): set by ContentView when CalibrationEngine completes.
//    Supplies all reference values including neutralLeanOffset.
// 2. Auto-lean (fallback): lean neutral is auto-detected from the first 30 reliable
//    frames even without a full calibration session, so lean works immediately.
//
// Adaptive sensitivity
// ────────────────────
// When a gesture candidate repeatedly reaches (confirmationFrames − 1) but then
// breaks before confirmation, a near-miss counter increments. After nearMissThreshold
// consecutive near-misses, the runtime sensitivity multiplier steps down 5%, making
// the gesture slightly easier to trigger. Bounded ±30% of profile default.
// Resets on apply(profile:) so game-switch immediately restores profile defaults.
//
// Safety zone
// ───────────
// If nose.z (depth) exceeds safetyZoneDepthThreshold (more negative = too close),
// onSafetyZoneViolation() is called before any gesture classification proceeds.

import Foundation
import Combine

// MARK: - GestureDebugInfo

/// Raw classifier inputs captured each frame for on-screen debugging.
struct GestureDebugInfo {
    var confidence: Float
    var isReliable: Bool
    var candidate: MotionEvent
    var pendingCount: Int
    var leftWristY: Float?
    var rightWristY: Float?
    var leftShoulderY: Float?
    var rightShoulderY: Float?
    var leftHipY: Float?
    var rightHipY: Float?
    var hipCenterX: Float?
    var shoulderCenterX: Float?
    /// Calibrated lean delta: (hipCenter.x − shoulderCenter.x) − neutralLeanOffset.
    /// Zero = personal neutral. Positive = leaning right.
    var leanDelta: Float?
    var rawLeanDelta: Float?
    var hipRise: Float?
    var hipDrop: Float?
    /// min(leftWristY − leftShoulderY, rightWristY − rightShoulderY).
    /// Negative = wrists above shoulders.
    var handsUpScore: Float?
    var jumpMetric: Float?
    var squatMetric: Float?
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

// MARK: - MotionInterpreter

class MotionInterpreter: ObservableObject, MotionEngineDelegate {

    // MARK: - Published

    /// Display event — auto-clears after 0.8 s. Use for momentary UI flash.
    @Published var currentEvent: MotionEvent = .none

    /// Last confirmed gesture — never auto-clears. Stable state display and transition logs.
    @Published private(set) var confirmedEvent: MotionEvent = .none

    /// Raw classifier inputs from the last classify() call. Updated every frame.
    @Published var debugInfo: GestureDebugInfo = .empty

    // MARK: - Output

    var onMotionEvent: ((MotionEvent) -> Void)?

    // MARK: - Body calibration

    /// Body-relative reference values. Loaded at init from UserDefaults.
    /// Update via applyCalibration(_:) when CalibrationEngine completes.
    var calibration: BodyCalibration = BodyCalibration.load() ?? .uncalibrated

    // MARK: - Safety zone

    /// Nose z-depth threshold (negative = closer to camera).
    /// Trigger onSafetyZoneViolation when nose.z < safetyZoneDepthThreshold.
    var safetyZoneDepthThreshold: Float = -0.5

    /// Called when the player's nose exceeds the safety-zone depth threshold.
    /// ContentView may use this to pause the game or show a "step back" prompt.
    var onSafetyZoneViolation: (() -> Void)?

    // MARK: - Tracking loss / recovery

    /// Called (on main thread) when tracking is lost — confidence gate fails
    /// consistently enough for MotionEngine to declare `motionEngineDidLoseTracking`.
    /// Wire to `controllerSession.pause(reason: .trackingLost)` in ContentView.
    var onTrackingLost: (() -> Void)?

    /// Called (on main thread) when the first high-confidence frame arrives after
    /// a period of lost tracking. Auto-resume is safe only when the prior pause reason
    /// was `.trackingLost` — callers must verify the reason before resuming.
    var onTrackingRestored: (() -> Void)?

    /// True between `motionEngineDidLoseTracking` and the next good frame.
    /// Used to fire `onTrackingRestored` exactly once per loss/recovery cycle.
    private var isTrackingLost: Bool = false

    // MARK: - Profile-driven sensitivity defaults
    // Set by apply(profile:) from recognizerConfig["sensitivity"].
    // Represent the fraction of the calibration reference value required for a gesture.
    //   effectiveThreshold = sensitivity × adaptationFactor × calibrationReference
    // E.g. leanSensitivity 0.40 × shoulderWidth 0.20 = threshold 0.08 (8 % of frame width).

    private var leanSensitivity:      Float = 0.40
    private var jumpSensitivity:      Float = 0.55
    private var squatSensitivity:     Float = 0.55
    private var handsUpSensitivity:   Float = 0.30
    private var handsDownSensitivity: Float = 0.25

    // MARK: - Adaptive sensitivity runtime state
    // sensitivityMultipliers stores per-recognizer fractional adjustments relative to
    // profile defaults.  A delta of −0.05 reduces the effective threshold by 5 %,
    // making the gesture easier to trigger.  Clamped to [−adaptiveClampMax, +adaptiveClampMax].
    // Reset on every apply(profile:) so game-switching restores profile defaults.

    private var sensitivityMultipliers: [RecognizerID: Float] = [:]
    private var nearMissCount:          [RecognizerID: Int]   = [:]

    private let nearMissThreshold: Int   = 5       // near-misses before adapting
    private let adaptiveStep:      Float = 0.05    // per-adaptation reduction
    private let adaptiveClampMax:  Float = 0.30    // max ±30 % deviation from default

    // MARK: - Profile-driven recognizer gating

    /// Which recognizers are active for the current game. nil = all enabled (default).
    private var enabledRecognizers: Set<RecognizerID>? = nil

    // MARK: - Tuning (non-gesture specific)

    var confidenceGate: Float    = 0.6   // frames at or below this are discarded
    var freezeSDThreshold: Float = 0.02  // std-dev of hipCenter.x for freeze detection

    /// Debug: when true, only lean / neutral is classified. Verifies lean sign in isolation.
    @Published var debugLeanOnly: Bool = false

    // MARK: - Ring buffer

    private var buffer = RingBuffer<PoseSnapshot>(capacity: 15)

    // MARK: - Confirmation gate

    private var pendingEvent:        MotionEvent = .none
    private var pendingCount:        Int         = 0
    private let confirmationFrames:  Int         = 3

    // MARK: - Cooldown

    private var lastEventTime: Date = .distantPast
    private let cooldown: TimeInterval = 0.5

    // MARK: - Transition logging (separate from auto-clearing currentEvent)

    private var lastConfirmedEvent: MotionEvent = .none

    // MARK: - Freeze tracking

    private var freezeStartTime: Date? = nil

    // MARK: - Lean calibration

    /// True when lean neutral is known (either from personalized calibration or auto-detection).
    /// Lean classification is gated on this flag to prevent false fires with a 0.0 neutral
    /// during the first frames before the player's posture has been measured.
    private(set) var isLeanCalibrated: Bool = false

    private var autoLeanSamples:       [Float] = []
    private let leanCalibrationTarget: Int     = 30   // ~1 s at 30 fps

    /// Current lean neutral offset (sourced from calibration or auto-detection).
    /// Exposed for the debug HUD in ContentView.
    var leanNeutralOffset: Float { calibration.neutralLeanOffset }

    // MARK: - Apply calibration (called by ContentView when CalibrationEngine finishes)

    /// Replace the current BodyCalibration with a freshly completed personalized one.
    /// Clears adaptive state so runtime adjustments start fresh for the new body reference.
    func applyCalibration(_ cal: BodyCalibration) {
        calibration             = cal
        isLeanCalibrated        = true   // personalized calibration provides neutralLeanOffset
        autoLeanSamples         = []
        sensitivityMultipliers  = [:]    // reset adaptation — body reference has changed
        nearMissCount           = [:]
        print("🕹️ [MotionInterpreter] Body calibration applied — torso:\(String(format: "%.3f", cal.torsoLength)) sw:\(String(format: "%.3f", cal.shoulderWidth)) leanOff:\(String(format: "%+.3f", cal.neutralLeanOffset))")
    }

    /// Resets lean calibration state.
    /// If a personalized calibration is loaded, lean remains immediately valid.
    /// Otherwise, restarts the 30-frame auto-detection window.
    func resetLeanCalibration() {
        autoLeanSamples = []
        if calibration.isPersonalized {
            isLeanCalibrated = true
            print("🕹️ [Lean] Personalized calibration retained: \(String(format: "%+.3f", calibration.neutralLeanOffset))")
        } else {
            calibration.neutralLeanOffset = 0
            isLeanCalibrated = false
            print("🕹️ [Lean] Auto-calibration reset — collecting new baseline")
        }
    }

    // MARK: - Profile application

    /// Apply per-game recognizer config and enabled-recognizer list.
    /// config["sensitivity"] values are multipliers on the calibration reference:
    ///   effectiveThreshold = sensitivity × adaptationFactor × calibrationReference
    /// Resets runtime adaptive state so each game starts at its profile-defined sensitivity.
    func apply(profile: GameProfile) {
        if let list = profile.enabledRecognizers {
            enabledRecognizers = Set(list)
        } else {
            enabledRecognizers = nil
        }

        // Read sensitivity multipliers from profile config.
        // Keys: "sensitivity" (new). Legacy "threshold"/"margin" keys are not honoured
        // because their absolute semantics are incompatible with the body-relative system.
        if let v = profile.config(for: .bodyLean)["sensitivity"]      { leanSensitivity      = Float(v) }
        if let v = profile.config(for: .bodyJump)["sensitivity"]      { jumpSensitivity      = Float(v) }
        if let v = profile.config(for: .bodySquat)["sensitivity"]     { squatSensitivity     = Float(v) }
        if let v = profile.config(for: .bodyHandsUp)["sensitivity"]   { handsUpSensitivity   = Float(v) }
        if let v = profile.config(for: .bodyHandsDown)["sensitivity"] { handsDownSensitivity = Float(v) }

        // Reset adaptive deltas — game switch restores profile defaults immediately.
        sensitivityMultipliers = [:]
        nearMissCount          = [:]

        let label = enabledRecognizers.map { $0.map(\.rawValue).sorted().joined(separator: ",") } ?? "all"
        print("🕹️ [MotionInterpreter] Applied profile '\(profile.displayName)' — enabled: \(label)")
    }

    // MARK: - MotionEngineDelegate

    func motionEngine(_ engine: MotionEngine, didOutput snapshot: PoseSnapshot) {

        // Safety zone: check nose depth before any classification.
        if let noseZ = snapshot.nose?.z, noseZ < safetyZoneDepthThreshold {
            onSafetyZoneViolation?()
        }

        // Confidence gate: discard frames at or below threshold before they can
        // accumulate in the ring buffer, affect calibration, or skew pending counts.
        guard snapshot.trackingConfidence > confidenceGate else {
            #if DEBUG
            print("🕹️ [MotionInterpreter] Frame rejected: confidence \(String(format: "%.2f", snapshot.trackingConfidence)) ≤ \(confidenceGate)")
            #endif
            return
        }

        // Core landmark bounds gate: rejects off-frame coordinates (e.g. y < 0) that
        // pass MediaPipe's visibility check but carry geometrically invalid values.
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
            print("🕹️ [MotionInterpreter] Frame rejected: landmark out of bounds — LS:\(coords[0]) RS:\(coords[1]) LH:\(coords[2]) RH:\(coords[3])")
            #endif
            return
        }

        // Tracking recovery: first good frame after a loss cycle.
        if isTrackingLost {
            isTrackingLost = false
            DispatchQueue.main.async { [weak self] in
                self?.onTrackingRestored?()
            }
        }

        addSnapshot(snapshot)
    }

    func motionEngineDidLoseTracking(_ engine: MotionEngine) {
        buffer          = RingBuffer<PoseSnapshot>(capacity: buffer.capacity)
        pendingEvent    = .none
        pendingCount    = 0
        freezeStartTime = nil
        resetLeanCalibration()
        isTrackingLost  = true
        print("🕹️ [MotionInterpreter] Tracking lost — full state reset")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastConfirmedEvent = .none
            self.confirmedEvent     = .none
            self.currentEvent       = .none
            self.onTrackingLost?()
        }
    }

    // MARK: - Core pipeline

    func addSnapshot(_ snapshot: PoseSnapshot) {
        buffer.push(snapshot)

        // Lean neutral detection.
        // If personalized calibration is available, lean is immediately calibrated.
        // Otherwise auto-detect neutral from the first 30 reliable frames, mirroring
        // the pre-calibration behaviour so lean works without a full calibration session.
        if !isLeanCalibrated {
            if calibration.isPersonalized {
                isLeanCalibrated = true
            } else if snapshot.trackingConfidence > confidenceGate,
                      let hip = snapshot.hipCenter, let shoulder = snapshot.shoulderCenter {
                autoLeanSamples.append(hip.x - shoulder.x)
                if autoLeanSamples.count >= leanCalibrationTarget {
                    calibration.neutralLeanOffset =
                        autoLeanSamples.reduce(0, +) / Float(autoLeanSamples.count)
                    isLeanCalibrated = true
                    print("🕹️ [Lean] Auto-calibrated neutral: \(String(format: "%+.3f", calibration.neutralLeanOffset))")
                }
            }
        }

        guard buffer.count >= 5 else { return }

        let classified: MotionEvent = snapshot.trackingConfidence <= confidenceGate
            ? .none
            : classify(latest: snapshot)

        pushConfirmation(classified)

        // Publish debug info (must be on main actor).
        let frames      = buffer.elements
        let oldHip      = frames.first?.hipCenter
        let nowHip      = snapshot.hipCenter
        let rawLean: Float? = {
            guard let h = snapshot.hipCenter, let s = snapshot.shoulderCenter else { return nil }
            return h.x - s.x
        }()
        let calibLean: Float? = rawLean.map { $0 - calibration.neutralLeanOffset }
        let handsUpScore: Float? = {
            guard let lw = snapshot.leftWrist,  let ls = snapshot.leftShoulder,
                  let rw = snapshot.rightWrist, let rs = snapshot.rightShoulder else { return nil }
            return min(lw.y - ls.y, rw.y - rs.y)
        }()
        let jumpMetric:  Float? = (oldHip != nil && nowHip != nil) ? oldHip!.y - nowHip!.y : nil
        let squatMetric: Float? = (oldHip != nil && nowHip != nil) ? nowHip!.y - oldHip!.y : nil

        let info = GestureDebugInfo(
            confidence:       snapshot.trackingConfidence,
            isReliable:       snapshot.isReliable,
            candidate:        classified,
            pendingCount:     pendingCount,
            leftWristY:       snapshot.leftWrist?.y,
            rightWristY:      snapshot.rightWrist?.y,
            leftShoulderY:    snapshot.leftShoulder?.y,
            rightShoulderY:   snapshot.rightShoulder?.y,
            leftHipY:         snapshot.leftHip?.y,
            rightHipY:        snapshot.rightHip?.y,
            hipCenterX:       snapshot.hipCenter?.x,
            shoulderCenterX:  snapshot.shoulderCenter?.x,
            leanDelta:        calibLean,
            rawLeanDelta:     rawLean,
            hipRise:          jumpMetric,
            hipDrop:          squatMetric,
            handsUpScore:     handsUpScore,
            jumpMetric:       jumpMetric,
            squatMetric:      squatMetric,
            timestamp:        snapshot.timestamp
        )
        DispatchQueue.main.async { [weak self] in self?.debugInfo = info }
    }

    // MARK: - Body-relative threshold helpers

    /// Returns the effective sensitivity for a recognizer, incorporating the runtime
    /// adaptive delta.  Clamped so the result stays within ±adaptiveClampMax of base.
    private func effectiveSensitivity(base: Float, id: RecognizerID) -> Float {
        let delta = sensitivityMultipliers[id] ?? 0
        let clamped = min(max(delta, -adaptiveClampMax), adaptiveClampMax)
        return base * (1.0 + clamped)
    }

    // MARK: - Classifier

    private func classify(latest: PoseSnapshot) -> MotionEvent {
        let frames = buffer.elements

        // STEP 1 — Core landmark guard.
        // Redundant with the entry guard but defensive — classify() can be called
        // from unit tests with synthetic snapshots that bypass motionEngine(_:didOutput:).
        guard let ls = latest.leftShoulder,  let rs = latest.rightShoulder,
              let lh = latest.leftHip,       let rh = latest.rightHip,
              ls.x >= 0, ls.x <= 1, ls.y >= 0, ls.y <= 1,
              rs.x >= 0, rs.x <= 1, rs.y >= 0, rs.y <= 1,
              lh.x >= 0, lh.x <= 1, lh.y >= 0, lh.y <= 1,
              rh.x >= 0, rh.x <= 1, rh.y >= 0, rh.y <= 1 else {
            return .none
        }

        // Pre-compute body-relative thresholds for this frame.
        // effectiveSensitivity incorporates the adaptive runtime delta (±30 % of profile default).
        let leanThresh      = effectiveSensitivity(base: leanSensitivity,      id: .bodyLean)      * calibration.shoulderWidth
        let jumpThresh      = effectiveSensitivity(base: jumpSensitivity,      id: .bodyJump)      * calibration.maxJumpRise
        let squatThresh     = effectiveSensitivity(base: squatSensitivity,     id: .bodySquat)     * calibration.maxCrouchDrop
        let handsUpThresh   = effectiveSensitivity(base: handsUpSensitivity,   id: .bodyHandsUp)   * calibration.torsoLength
        let handsDownThresh = effectiveSensitivity(base: handsDownSensitivity, id: .bodyHandsDown) * calibration.torsoLength

        // STEP 2 — Lean left / lean right.
        // Gated on isLeanCalibrated so lean never fires on a 0.0 neutral before
        // auto-detection has had at least 30 reliable frames to estimate it.
        // calibrated = (hipCenter.x − shoulderCenter.x) − calibration.neutralLeanOffset
        if isLeanCalibrated, isEnabled(.bodyLean),
           let hip = latest.hipCenter, let shoulder = latest.shoulderCenter {
            let rawDelta   = hip.x - shoulder.x
            let calibrated = rawDelta - calibration.neutralLeanOffset
            if calibrated < -leanThresh { return .leanLeft  }
            if calibrated >  leanThresh { return .leanRight }
        }

        // STEP 3 — Lean-only debug mode: skip all remaining recognizers.
        if debugLeanOnly { return .none }

        // STEP 4 — Hands up.
        // y = 0 is TOP of frame; wrist.y < shoulder.y means wrist is physically higher.
        // handsUpThresh = handsUpSensitivity × torsoLength (fraction of torso height).
        // Wrists are bounds-checked so an off-frame wrist (y < 0) cannot produce a
        // falsely large negative margin.
        if isEnabled(.bodyHandsUp),
           let lw = latest.leftWrist, let rw = latest.rightWrist,
           lw.x >= 0, lw.x <= 1, lw.y >= 0, lw.y <= 1,
           rw.x >= 0, rw.x <= 1, rw.y >= 0, rw.y <= 1 {
            if lw.y < ls.y - handsUpThresh && rw.y < rs.y - handsUpThresh {
                return .handsUp
            }
        }

        // STEP 5 — Jump (hip rose relative to oldest frame in buffer).
        // Requires 11 frames so the reference is ~367 ms old at 30 fps.
        // jumpThresh = jumpSensitivity × maxJumpRise (fraction of the player's
        // personal best jump — a consistent effort level regardless of height).
        if isEnabled(.bodyJump), frames.count >= 11,
           let oldHip = frames[0].hipCenter,
           let nowHip = latest.hipCenter {
            let hipRise = oldHip.y - nowHip.y   // positive = hip moved up
            if hipRise > jumpThresh { return .jump }
        }

        // STEP 6 — Squat (hip dropped relative to oldest frame in buffer).
        if isEnabled(.bodySquat), frames.count >= 11,
           let oldHip = frames[0].hipCenter,
           let nowHip = latest.hipCenter {
            let hipDrop = nowHip.y - oldHip.y   // positive = hip moved down
            if hipDrop > squatThresh { return .squat }
        }

        // STEP 7 — Hands down.
        // handsDownThresh = handsDownSensitivity × torsoLength.
        // Bounds-checked so a wrist below the frame bottom (y > 1) cannot falsely satisfy
        // lw.y > lh.y + margin.
        if isEnabled(.bodyHandsDown),
           let lw = latest.leftWrist, let rw = latest.rightWrist,
           lw.x >= 0, lw.x <= 1, lw.y >= 0, lw.y <= 1,
           rw.x >= 0, rw.x <= 1, rw.y >= 0, rw.y <= 1 {
            if lw.y > lh.y + handsDownThresh && rw.y > rh.y + handsDownThresh {
                return .handsDown
            }
        }

        // STEP 8 — Freeze (std-dev of hipCenter.x across full buffer < threshold).
        if frames.count == buffer.capacity {
            let xs = frames.compactMap { $0.hipCenter?.x }
            if xs.count == buffer.capacity {
                let mean     = xs.reduce(0, +) / Float(xs.count)
                let variance = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(xs.count)
                if sqrt(variance) < freezeSDThreshold {
                    let now = Date()
                    if freezeStartTime == nil { freezeStartTime = now }
                    let duration = now.timeIntervalSince(freezeStartTime!)
                    return .freeze(duration: duration)
                }
            }
        }
        freezeStartTime = nil

        // STEP 9 — No gesture detected.
        return .none
    }

    // MARK: - Recognizer gating

    private func isEnabled(_ id: RecognizerID) -> Bool {
        guard let set = enabledRecognizers else { return true }
        return set.contains(id)
    }

    // MARK: - Adaptive sensitivity

    /// Returns the RecognizerID governing a given MotionEvent, or nil for events
    /// that don't have a corresponding body recognizer (freeze, none, hand gestures).
    private func recognizerID(for event: MotionEvent) -> RecognizerID? {
        switch event {
        case .leanLeft, .leanRight: return .bodyLean
        case .jump:                 return .bodyJump
        case .squat:                return .bodySquat
        case .handsUp:              return .bodyHandsUp
        case .handsDown:            return .bodyHandsDown
        default:                    return nil
        }
    }

    /// Called when a gesture candidate reached (confirmationFrames − 1) consecutive
    /// frames but then broke before confirming.  After nearMissThreshold such events
    /// the sensitivity multiplier steps down by adaptiveStep (threshold gets smaller =
    /// gesture is easier to trigger), clamped at −adaptiveClampMax.
    private func recordNearMiss(for id: RecognizerID) {
        nearMissCount[id, default: 0] += 1
        guard (nearMissCount[id] ?? 0) >= nearMissThreshold else { return }
        nearMissCount[id] = 0
        let current = sensitivityMultipliers[id] ?? 0
        sensitivityMultipliers[id] = max(current - adaptiveStep, -adaptiveClampMax)
        #if DEBUG
        print("🕹️ [Adaptive] \(id.rawValue) near-miss ×\(nearMissThreshold) → multiplier: \(String(format: "%+.2f", sensitivityMultipliers[id]!))")
        #endif
    }

    // MARK: - Confirmation + cooldown

    private func pushConfirmation(_ event: MotionEvent) {
        if event == pendingEvent {
            pendingCount += 1
        } else {
            // Near-miss detection: gesture was one frame from confirmation but broke.
            if pendingCount == confirmationFrames - 1,
               let id = recognizerID(for: pendingEvent) {
                recordNearMiss(for: id)
            }
            pendingEvent = event
            pendingCount = 1
        }

        guard pendingCount >= confirmationFrames else { return }
        guard event != .none else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.lastConfirmedEvent != .none {
                    print("🕹️ Gesture: \(self.lastConfirmedEvent.displayName) → neutral")
                    self.lastConfirmedEvent = .none
                    self.confirmedEvent     = .none
                }
                self.currentEvent = .none
            }
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastEventTime) >= cooldown else { return }

        lastEventTime = now
        pendingCount  = 0   // reset so the same event can re-fire after cooldown

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.lastConfirmedEvent != event {
                print("🕹️ Gesture: \(self.lastConfirmedEvent.displayName) → \(event.displayName)")
                self.lastConfirmedEvent = event
                self.confirmedEvent     = event
                self.onMotionEvent?(event)
            }
            self.currentEvent = event
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.currentEvent = .none
        }
    }
}
