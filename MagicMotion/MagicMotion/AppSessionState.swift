// AppSessionState.swift
// MagicMotion
//
// Canonical app-level state for camera, tracking, calibration, and errors

import Foundation
import Combine

/// Enum for calibration state
enum CalibrationState: Equatable {
    case notStarted
    case inProgress
    case complete
}

/// Enum for tracking state
enum TrackingState: Equatable {
    case notReady
    case searching
    case tracking(confidence: Float)
    case lost
}

/// Canonical app session state (observable)
class AppSessionState: ObservableObject {
    @Published var cameraAuthorized: Bool = false
    @Published var cameraRunning: Bool = false
    @Published var calibrationState: CalibrationState = .notStarted
    @Published var trackingState: TrackingState = .notReady
    @Published var error: String? = nil
    var cancellables = Set<AnyCancellable>()

    // --- Tuning thresholds (operator adjustable in debug) ---
    @Published var confidenceThreshold: Float = 0.5
    @Published var calibrationFramesRequired: Int = 30
    @Published var overlayDwellSeconds: Double = 1.0
    @Published var gestureSensitivity: Float = 0.15

    // --- Diagnostics (read-only for operator panel) ---
    struct Diagnostics {
        let calibrationState: CalibrationState
        let trackingState: TrackingState
        let trackingConfidence: Float
        let overlayReason: String
        let error: String?
    }
    var diagnostics: Diagnostics {
        Diagnostics(
            calibrationState: calibrationState,
            trackingState: trackingState,
            trackingConfidence: {
                if case let .tracking(conf) = trackingState { return conf } else { return 0 }
            }(),
            overlayReason: overlayReason,
            error: error
        )
    }

    // For overlay diagnostics
    @Published var overlayReason: String = ""

    // --- Dwell debounce state (private) ---
    /// Timestamp when the raw tracking state last changed direction
    private var trackingStateChangeTime: Date = .distantPast
    /// Last raw tracking state before the dwell debounce is applied
    private var lastRawTrackingState: TrackingState = .notReady

    // For wiring: update from camera, pose, calibration, etc.
    func updateCamera(authorized: Bool, running: Bool) {
        cameraAuthorized = authorized
        cameraRunning = running
    }

    /// Update tracking from a new confidence value.
    /// Applies a dwell-timer debounce so the "tracking lost" overlay
    /// does not flicker when confidence hovers near the threshold.
    func updateTracking(confidence: Float) {
        let threshold = confidenceThreshold
        let now = Date()
        let newRawState: TrackingState = confidence >= threshold
            ? .tracking(confidence: confidence)
            : .lost

        // Record when the raw direction changes
        let rawChanged: Bool
        switch (lastRawTrackingState, newRawState) {
        case (.lost, .tracking), (.tracking, .lost),
             (.notReady, .tracking), (.notReady, .lost):
            rawChanged = true
        default:
            rawChanged = false
        }
        if rawChanged {
            lastRawTrackingState = newRawState
            trackingStateChangeTime = now
        } else {
            lastRawTrackingState = newRawState // keep confidence value fresh
        }

        // Only commit state change after the dwell window has elapsed
        let shouldTransition: Bool
        switch (trackingState, newRawState) {
        case (.lost, .tracking), (.tracking, .lost),
             (.notReady, .tracking), (.notReady, .lost),
             (.searching, .tracking), (.searching, .lost):
            shouldTransition = now.timeIntervalSince(trackingStateChangeTime) >= overlayDwellSeconds
        default:
            shouldTransition = true // same direction — always update (e.g. confidence value)
        }

        if shouldTransition {
            trackingState = newRawState
        }
    }

    func setCalibration(_ state: CalibrationState) {
        calibrationState = state
    }

    func setError(_ message: String?) {
        error = message
    }

    func reset() {
        calibrationState = .notStarted
        trackingState = .notReady
        error = nil
        overlayReason = ""
    }
}
