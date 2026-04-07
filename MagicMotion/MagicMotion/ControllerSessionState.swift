// ControllerSessionState.swift
// MagicMotion
//
// State model for the MagicMotion Home controller session runtime.
// ControllerSession owns the state machine transitions.
// This file contains only type definitions — no business logic.
//
// State flow (happy path):
//   idle → ready → active → ended
//
// Detours:
//   idle → needsCalibration  (no personalized body calibration found)
//   active → paused → active (tracking loss, safety zone, app background)
//   any → idle               (reset)

import Foundation
import SwiftUI

enum ControllerSessionState: Equatable {
    /// No game selected or session not yet prepared.
    case idle

    /// A game is selected but no personalized body calibration exists.
    /// App should prompt the user to run the body calibration flow.
    case needsCalibration

    /// Game and calibration are both loaded. Ready to activate.
    case ready

    /// Controller is active — motion input is being interpreted and dispatched.
    case active

    /// Session is temporarily suspended.
    case paused(reason: ControllerPauseReason)

    /// Session has ended normally (user returned from game or tapped Stop).
    case ended
}

enum ControllerPauseReason: Equatable {
    /// MediaPipe stopped detecting the player reliably.
    case trackingLost

    /// The player moved too close to the camera (nose.z exceeded safety threshold).
    case safetyZoneViolation

    /// The app moved to the background (e.g. home button press).
    case appBackgrounded
}

// MARK: - Display helpers (consumed by ControllerModeView, HomeMonitorView, SetupView)

extension ControllerSessionState {
    var displayLabel: String {
        switch self {
        case .idle:             return "Idle"
        case .needsCalibration: return "Needs Calibration"
        case .ready:            return "Ready"
        case .active:           return "Controller Active"
        case .paused(let r):
            switch r {
            case .trackingLost:        return "Tracking Lost"
            case .safetyZoneViolation: return "Step Back"
            case .appBackgrounded:     return "Backgrounded"
            }
        case .ended:            return "Session Ended"
        }
    }

    var displayColor: Color {
        switch self {
        case .active:           return .green
        case .paused:           return .orange
        case .needsCalibration: return .yellow
        case .ready:            return .white
        case .idle, .ended:     return .gray
        }
    }
}
