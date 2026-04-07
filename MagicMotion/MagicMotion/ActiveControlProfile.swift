// ActiveControlProfile.swift
// MagicMotion
//
// The explicit combination of a selected GameProfile and a child's BodyCalibration.
// This is the runtime configuration object that ControllerSession holds while active.
//
// Responsibilities:
//   - Be the named combination: "which game" + "which child's body"
//   - Expose convenience accessors for the most-used fields
//   - Provide a factory that assembles from the current persisted state
//
// NOT responsible for:
//   - Persisting either component (GameProfileStore / BodyCalibration.save() own that)
//   - Interpreting motion events (MotionInterpreter owns that)
//   - Sending BLE commands (BandBLEManager owns that)
//
// MotionInterpreter consumes GameProfile (via apply(profile:)) and BodyCalibration
// (via applyCalibration(_:)) separately. ActiveControlProfile is the object that
// keeps them co-located at the ControllerSession level so state is explicit.
//
// Construction: callers must supply both components explicitly.
//   ControllerSession.prepare(gameProfile:calibration:) is the preferred construction site.
//   Do NOT add factory methods that read UserDefaults or other persistence here —
//   persistence belongs to the layer that owns each component.

import Foundation

struct ActiveControlProfile: Equatable {
    let gameProfile: GameProfile
    let calibration: BodyCalibration

    // MARK: - Convenience accessors

    var gameID: GameID { gameProfile.gameID }
    var displayName: String { gameProfile.displayName }

    /// True when the child's body calibration came from a real calibration session.
    /// False means uncalibrated defaults are in use.
    var isPersonalized: Bool { calibration.isPersonalized }
}
