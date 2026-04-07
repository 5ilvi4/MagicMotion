// CalibrationEngine.swift
// MagicMotion
//
// Owns the staged body-calibration flow: neutral stance → jump → squat.
// Produces a BodyCalibration that MotionInterpreter uses for body-relative thresholds.
//
// Responsibilities:
//   - Phase state machine and per-phase countdown timers
//   - Collecting and averaging PoseSnapshot measurements during each phase
//   - Computing body-relative reference values (shoulderWidth, torsoLength, motion ranges)
//   - Persisting the resulting BodyCalibration to UserDefaults
//   - Degrading gracefully when frame quality is poor
//
// NOT responsible for:
//   - Classifying gameplay gestures
//   - Directly mutating MotionInterpreter
//   - Displaying UI (CalibrationOverlayView observes `phase` for that)
//
// Thread safety:
//   All methods must be called from the main thread.
//   Timer callbacks fire on the main run loop.
//   motionEngine.onPoseSnapshot delivers on the main thread, so feed() is safe.

import Foundation
import Combine

// MARK: - CalibrationPhase

enum CalibrationPhase: Equatable {
    case idle
    case neutralStance(secondsRemaining: Int)
    case jump(secondsRemaining: Int)
    case squat(secondsRemaining: Int)
    case complete(BodyCalibration)
    case failed(reason: String)

    // Equatable: .complete compares equal regardless of associated BodyCalibration payload.
    // This lets SwiftUI's onChange(of:) detect the transition without requiring
    // BodyCalibration to implement a field-by-field comparison in the switch.
    static func == (lhs: CalibrationPhase, rhs: CalibrationPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle,                   .idle):                   return true
        case (.neutralStance(let a),   .neutralStance(let b)):   return a == b
        case (.jump(let a),            .jump(let b)):             return a == b
        case (.squat(let a),           .squat(let b)):            return a == b
        case (.complete,               .complete):               return true
        case (.failed(let a),          .failed(let b)):           return a == b
        default:                                                 return false
        }
    }

    // MARK: - Display helpers (consumed by CalibrationOverlayView)

    var displayName: String {
        switch self {
        case .idle:          return "Ready"
        case .neutralStance: return "Stand Tall"
        case .jump:          return "Jump!"
        case .squat:         return "Duck!"
        case .complete:      return "Done!"
        case .failed:        return "Oops"
        }
    }

    var instruction: String {
        switch self {
        case .idle:                return ""
        case .neutralStance:       return "Stand tall like a hero!"
        case .jump:                return "Jump as high as you can!"
        case .squat:               return "Duck from the dragon!"
        case .complete:            return "You're ready!"
        case .failed(let reason):  return reason
        }
    }

    /// 1-based index for the three active phases; 0 outside of active phases.
    var phaseIndex: Int {
        switch self {
        case .neutralStance: return 1
        case .jump:          return 2
        case .squat:         return 3
        default:             return 0
        }
    }

    var secondsRemaining: Int? {
        switch self {
        case .neutralStance(let s), .jump(let s), .squat(let s): return s
        default: return nil
        }
    }

    /// True during any active calibration phase (including complete/failed before auto-dismiss).
    var isActive: Bool {
        if case .idle = self { return false }
        return true
    }
}

// MARK: - CalibrationEngine

final class CalibrationEngine: ObservableObject {

    @Published private(set) var phase: CalibrationPhase = .idle

    // MARK: - Tuning

    private let phaseDurationSeconds = 3
    private let minReliableFrames    = 10
    private let confidenceGate: Float = 0.6

    // MARK: - Per-phase sample storage

    private struct NeutralSample {
        let hipX:          Float
        let hipY:          Float
        let shoulderX:     Float
        let leanOffset:    Float   // hipCenter.x − shoulderCenter.x
        let shoulderWidth: Float   // |rightShoulder.x − leftShoulder.x|
        let torsoLength:   Float   // |hipCenter.y − shoulderCenter.y|
    }

    private var neutralSamples:   [NeutralSample] = []
    private var jumpHipYSamples:  [Float] = []
    private var squatHipYSamples: [Float] = []

    /// hipCenter.y averaged over neutral phase; baseline for jump/squat range computation.
    private var neutralHipY: Float = BodyCalibration.uncalibrated.neutralHipY

    // MARK: - Countdown timer

    private var countdownTimer:          Timer?
    private var currentSecondsRemaining: Int = 0

    // MARK: - Public API

    var isActive: Bool { phase.isActive }

    /// Begin the 3-phase calibration flow. Cancels any in-progress session first.
    func startCalibration() {
        resetState()
        enterPhase(.neutralStance(secondsRemaining: phaseDurationSeconds))
    }

    /// Abort calibration and return to idle.
    func cancelCalibration() {
        resetState()
    }

    /// Feed one PoseSnapshot into the active phase. No-op when idle or already complete.
    /// Call from motionEngine.onPoseSnapshot — it arrives on the main thread.
    func feed(snapshot: PoseSnapshot) {
        switch phase {
        case .neutralStance: collectNeutralSample(snapshot)
        case .jump:          collectJumpSample(snapshot)
        case .squat:         collectSquatSample(snapshot)
        default:             break
        }
    }

    // MARK: - State machine

    private func resetState() {
        countdownTimer?.invalidate()
        countdownTimer   = nil
        neutralSamples   = []
        jumpHipYSamples  = []
        squatHipYSamples = []
        neutralHipY      = BodyCalibration.uncalibrated.neutralHipY
        phase            = .idle
    }

    private func enterPhase(_ newPhase: CalibrationPhase) {
        phase                    = newPhase
        currentSecondsRemaining  = phaseDurationSeconds

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.handleCountdownTick(timer: timer)
        }
    }

    private func handleCountdownTick(timer: Timer) {
        currentSecondsRemaining -= 1
        guard currentSecondsRemaining > 0 else {
            timer.invalidate()
            advanceFromCurrentPhase()
            return
        }
        // Publish updated secondsRemaining without changing which phase we're in.
        switch phase {
        case .neutralStance: phase = .neutralStance(secondsRemaining: currentSecondsRemaining)
        case .jump:          phase = .jump(secondsRemaining: currentSecondsRemaining)
        case .squat:         phase = .squat(secondsRemaining: currentSecondsRemaining)
        default:             timer.invalidate()
        }
    }

    private func advanceFromCurrentPhase() {
        switch phase {
        case .neutralStance: finishNeutralPhase()
        case .jump:          enterPhase(.squat(secondsRemaining: phaseDurationSeconds))
        case .squat:         finishSquatPhase()
        default:             break
        }
    }

    // MARK: - Frame collection

    private func collectNeutralSample(_ snapshot: PoseSnapshot) {
        guard isReliable(snapshot),
              let ls = snapshot.leftShoulder,  let rs = snapshot.rightShoulder,
              let lh = snapshot.leftHip,       let rh = snapshot.rightHip,
              let hip      = snapshot.hipCenter,
              let shoulder = snapshot.shoulderCenter,
              allInBounds(ls, rs, lh, rh) else { return }

        neutralSamples.append(NeutralSample(
            hipX:          hip.x,
            hipY:          hip.y,
            shoulderX:     shoulder.x,
            leanOffset:    hip.x - shoulder.x,
            shoulderWidth: abs(rs.x - ls.x),
            torsoLength:   abs(hip.y - shoulder.y)
        ))
    }

    private func collectJumpSample(_ snapshot: PoseSnapshot) {
        guard isReliable(snapshot), let hip = snapshot.hipCenter else { return }
        jumpHipYSamples.append(hip.y)
    }

    private func collectSquatSample(_ snapshot: PoseSnapshot) {
        guard isReliable(snapshot), let hip = snapshot.hipCenter else { return }
        squatHipYSamples.append(hip.y)
    }

    // MARK: - Phase completion

    private func finishNeutralPhase() {
        guard neutralSamples.count >= minReliableFrames else {
            fail(reason: "Stand in front of the camera and try again!")
            return
        }
        let n = Float(neutralSamples.count)
        neutralHipY = neutralSamples.map { $0.hipY }.reduce(0, +) / n
        enterPhase(.jump(secondsRemaining: phaseDurationSeconds))
    }

    private func finishSquatPhase() {
        guard neutralSamples.count >= minReliableFrames else {
            fail(reason: "Not enough frames captured. Please try again!")
            return
        }

        let n = Float(neutralSamples.count)
        let avgHipY      = neutralSamples.map { $0.hipY        }.reduce(0, +) / n
        let avgShoulderX = neutralSamples.map { $0.shoulderX   }.reduce(0, +) / n
        let avgLeanOff   = neutralSamples.map { $0.leanOffset   }.reduce(0, +) / n
        let avgSwWidth   = neutralSamples.map { $0.shoulderWidth }.reduce(0, +) / n
        let avgTorso     = neutralSamples.map { $0.torsoLength  }.reduce(0, +) / n

        // Jump: max hip rise = neutralHipY − minHipY (y=0 is top; smaller y = higher up).
        let jumpRise: Float
        if let minJumpY = jumpHipYSamples.min(), avgHipY - minJumpY > 0.02 {
            jumpRise = avgHipY - minJumpY
        } else {
            jumpRise = BodyCalibration.uncalibrated.maxJumpRise
        }

        // Squat: max hip drop = maxHipY − neutralHipY.
        let squatDrop: Float
        if let maxSquatY = squatHipYSamples.max(), maxSquatY - avgHipY > 0.02 {
            squatDrop = maxSquatY - avgHipY
        } else {
            squatDrop = BodyCalibration.uncalibrated.maxCrouchDrop
        }

        let cal = BodyCalibration(
            torsoLength:       max(avgTorso,   0.10),
            shoulderWidth:     max(avgSwWidth,  0.10),
            neutralHipY:       avgHipY,
            neutralShoulderX:  avgShoulderX,
            neutralLeanOffset: avgLeanOff,
            maxJumpRise:       max(jumpRise,   0.05),
            maxCrouchDrop:     max(squatDrop,  0.05),
            isPersonalized:    true
        )
        cal.save()

        print("✅ [CalibrationEngine] Complete: torso=\(String(format: "%.3f", cal.torsoLength)) sw=\(String(format: "%.3f", cal.shoulderWidth)) leanOff=\(String(format: "%+.3f", cal.neutralLeanOffset)) jumpRise=\(String(format: "%.3f", cal.maxJumpRise)) squatDrop=\(String(format: "%.3f", cal.maxCrouchDrop))")

        phase = .complete(cal)
        // Auto-dismiss after 2 s so the overlay clears without user interaction.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, case .complete = self.phase else { return }
            self.phase = .idle
        }
    }

    private func fail(reason: String) {
        print("❌ [CalibrationEngine] Failed: \(reason)")
        countdownTimer?.invalidate()
        countdownTimer = nil
        phase = .failed(reason: reason)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, case .failed = self.phase else { return }
            self.phase = .idle
        }
    }

    // MARK: - Helpers

    private func isReliable(_ snapshot: PoseSnapshot) -> Bool {
        snapshot.trackingConfidence > confidenceGate
    }

    private func allInBounds(_ landmarks: PoseSnapshot.Landmark...) -> Bool {
        landmarks.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 }
    }
}
