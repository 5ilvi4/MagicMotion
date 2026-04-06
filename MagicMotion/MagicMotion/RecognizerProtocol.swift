// RecognizerProtocol.swift
// MagicMotion
//
// Shared protocol foundation for the Recognizer Library.
//
// A recognizer is a focused, reusable gesture detector with a single
// responsibility: given sensor input, return an AppIntent or nil.
//
// What recognizers do NOT own:
//   • confirmation gating (N consecutive frames required)
//   • cooldown between firings
//   • conflict arbitration (that is InputCoordinator's job)
//   • BLE / game-profile knowledge
//
// Those concerns stay in the interpreter/coordinator layer above.
//
// Adding a new gesture for an existing sensor type:
//   1. Add a RecognizerID case.
//   2. Implement BodyRecognizer or HandRecognizer.
//   3. Add the recognizer ID to the relevant game profile JSON.
//
// Adding a gesture for a new sensor type:
//   Define a new protocol alongside BodyRecognizer / HandRecognizer.

import Foundation

// MARK: - RecognizerID

/// Unique stable identifier for each recognizer class.
/// Used in GameProfile.enabledRecognizers to select which recognizers are
/// active for a given game — without hard-coding gesture logic in profiles.
enum RecognizerID: String, Codable, Hashable, CaseIterable {
    // Body recognizers
    case bodyLean      = "bodyLean"
    case bodyJump      = "bodyJump"
    case bodySquat     = "bodySquat"
    case bodyHandsUp   = "bodyHandsUp"
    case bodyHandsDown = "bodyHandsDown"
    // Hand recognizers
    case handSwipe     = "handSwipe"
}

// MARK: - RecognizerConfig

/// Key-value configuration bag passed from GameProfile to a recognizer.
/// All values are Double so JSON profiles can tune thresholds without code changes.
///
/// Example JSON snippet:
///   "recognizerConfig": {
///     "bodyLean": { "threshold": 0.06 },
///     "handSwipe": { "graceFrames": 3 }
///   }
struct RecognizerConfig {
    let values: [String: Double]

    static let empty = RecognizerConfig(values: [:])

    subscript(_ key: String) -> Double? { values[key] }
    subscript(_ key: String, default fallback: Double) -> Double { values[key] ?? fallback }
}

// MARK: - BodyRecognizer

/// Processes one PoseSnapshot per call.
/// Returns the recognized AppIntent, or nil if no gesture was detected this frame.
/// Implementations may be stateful (e.g. maintain a history buffer).
/// The caller is responsible for confirmation gating and cooldown.
protocol BodyRecognizer: AnyObject {
    var id: RecognizerID { get }
    func process(snapshot: PoseSnapshot) -> AppIntent?
    func configure(with config: RecognizerConfig)
    func reset()
}

extension BodyRecognizer {
    func configure(with config: RecognizerConfig) {}
    func reset() {}
}

// MARK: - HandRecognizer

/// Processes one HandSnapshot per call.
/// Returns the recognized AppIntent, or nil if no gesture was detected this frame.
/// Implementations may be stateful (e.g. PointHistoryBuffer for swipe detection).
/// The caller is responsible for confirmation gating and cooldown.
protocol HandRecognizer: AnyObject {
    var id: RecognizerID { get }
    func process(hand: HandSnapshot) -> AppIntent?
    func configure(with config: RecognizerConfig)
    func reset()
}

extension HandRecognizer {
    func configure(with config: RecognizerConfig) {}
    func reset() {}
}
