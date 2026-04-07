// ControllerReadiness.swift
// MagicMotion
//
// Lightweight value type that computes whether ControllerModeView can start a
// controller session. Evaluated inline from observable state — no ObservableObject
// needed here. Views read this via a computed property.
//
// Blocking conditions (canStart = false when any is missing):
//   • game selected and a profile is loaded
//   • body calibration available (personalized or defaults loaded)
//   • camera running
//
// Advisory condition (surfaced as a warning but does not block start):
//   • wearable connected — commands won't reach the game without it, but
//     the controller session can still track gestures for testing/demo.

import Foundation

struct ControllerReadiness {

    let gameSelected: Bool
    /// False when ControllerSession is in .needsCalibration or .idle with no profile.
    let calibrationAvailable: Bool
    let cameraActive: Bool
    let wearableConnected: Bool

    /// True when all hard requirements are met and Start can be tapped.
    var canStart: Bool {
        gameSelected && calibrationAvailable && cameraActive
    }

    /// Human-readable descriptions of the conditions blocking start, in priority order.
    var blockingItems: [String] {
        var items: [String] = []
        if !gameSelected         { items.append("Select a game") }
        if !calibrationAvailable { items.append("Run body calibration first") }
        if !cameraActive         { items.append("Camera not ready") }
        return items
    }

    /// Advisory items that don't block start but the user should know about.
    var advisoryItems: [String] {
        guard !wearableConnected else { return [] }
        return ["Band not connected — gestures will be tracked but not sent"]
    }

    /// A single concise string for a compact inline hint, or nil when fully ready.
    var primaryBlockMessage: String? {
        blockingItems.first
    }
}
