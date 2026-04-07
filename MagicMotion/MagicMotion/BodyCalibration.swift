// BodyCalibration.swift
// MagicMotion
//
// Body-relative reference values captured during the staged calibration flow.
// Persisted to UserDefaults so calibration survives app restarts.
//
// MotionInterpreter reads this to compute gesture thresholds that are proportional
// to the player's own body dimensions and personal motion range, rather than
// absolute normalized image coordinates.
//
// Design intent:
//   A short child standing 1 m away and a tall child standing 2 m away will have
//   very different absolute landmark positions.  Expressing thresholds as multiples
//   of shoulderWidth, torsoLength, maxJumpRise, etc. makes the same sensitivity
//   multiplier produce the same *physical effort* for both players.
//
// .uncalibrated provides safe defaults that let the system function without a
// calibration session — short players or unusual distances are less precise but
// the app remains usable.

import Foundation

struct BodyCalibration: Codable, Equatable {

    // MARK: - Neutral-stance references

    /// Vertical span |hipCenter.y − shoulderCenter.y| in normalized coords.
    /// Scales arm-gesture thresholds (handsUp, handsDown) so raising/lowering arms
    /// by a fixed fraction of torso length feels consistent across body sizes.
    var torsoLength: Float

    /// Horizontal span |rightShoulder.x − leftShoulder.x|.
    /// Scales lean thresholds so a wider torso requires proportionally more lean.
    var shoulderWidth: Float

    /// hipCenter.y at rest in neutral standing pose (y = 0 is top of frame).
    /// Reference baseline for jump (hip rises above this) and squat (drops below).
    var neutralHipY: Float

    /// shoulderCenter.x at rest.
    /// Reserved for future forward-lean / depth-axis compensation.
    var neutralShoulderX: Float

    /// (hipCenter.x − shoulderCenter.x) at rest.
    /// Subtracted from the raw lean metric so the threshold is relative to the
    /// player's personal neutral alignment rather than perfect symmetry.
    var neutralLeanOffset: Float

    // MARK: - Calibrated motion ranges

    /// Maximum hip rise (neutralHipY − minHipY during jump phase).
    /// Anchors the jump threshold so the gesture fires at a consistent effort level.
    var maxJumpRise: Float

    /// Maximum hip drop (maxHipY − neutralHipY during squat phase).
    /// Anchors the squat threshold the same way.
    var maxCrouchDrop: Float

    // MARK: - Quality flag

    /// True only after a real CalibrationEngine session completes.
    /// False for .uncalibrated or during the lean auto-detection window.
    /// MotionInterpreter uses this to decide whether to skip lean auto-detection.
    var isPersonalized: Bool

    // MARK: - Default (uncalibrated)

    /// Safe fallback used when no calibration has been performed.
    /// Values represent a typical child-sized posture at ~1.5 m from the iPad.
    /// The system is functional but thresholds are not tuned to the specific player.
    static let uncalibrated = BodyCalibration(
        torsoLength:       0.25,
        shoulderWidth:     0.20,
        neutralHipY:       0.65,
        neutralShoulderX:  0.50,
        neutralLeanOffset: 0.0,
        maxJumpRise:       0.15,
        maxCrouchDrop:     0.15,
        isPersonalized:    false
    )

    // MARK: - Persistence

    private static let defaultsKey = "com.magicmotion.bodyCalibration"

    /// Encodes and stores this calibration in UserDefaults. Silent on encode failure.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    /// Returns a previously saved calibration, or nil if none exists or decoding fails.
    static func load() -> BodyCalibration? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let cal  = try? JSONDecoder().decode(BodyCalibration.self, from: data) else {
            return nil
        }
        return cal
    }
}
