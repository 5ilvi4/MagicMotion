// InputCoordinator.swift
// MagicMotion
//
// Layer 3.5 — Combined input policy for body + hand gesture streams.
//
// Receives confirmed events from MotionInterpreter (body) and
// HandGestureInterpreter (hand), applies a simple conflict policy,
// then emits a single resolved AppIntent downstream.
//
// OutputCoordinator knows NOTHING about:
//   • GameCommand / BLE bytes
//   • MediaPipe landmark types
//   • Game-profile JSON structure
//
// Downstream flow:
//   InputCoordinator.onIntent(AppIntent)
//     → GameProfileManager.mapIntent(_:) → GameCommand?
//     → BandBLEManager.send(command:)
//
// Conflict policy:
//   • Body intents always pass through immediately (body is primary).
//   • Hand intents are suppressed if a body intent fired within
//     `conflictWindow` seconds AND both would resolve to the same
//     normalized direction (left/right). Explicit table below.
//   • The hand channel always yields — body is never suppressed by hand.
//
// Explicit conflict pairs:
//   leanLeft  + handSwipeLeft  → same direction → suppress hand
//   leanRight + handSwipeRight → same direction → suppress hand

import Combine
import Foundation

// MARK: - CommandSource (debug HUD)

enum CommandSource {
    case body
    case hand
    case none

    var displayName: String {
        switch self {
        case .body: return "body"
        case .hand: return "hand ✋"
        case .none: return "—"
        }
    }
}

// MARK: - InputCoordinator

final class InputCoordinator: ObservableObject {

    // MARK: - Published (for debug HUD)

    @Published private(set) var lastBodyEvent: MotionEvent = .none
    @Published private(set) var lastHandGesture: HandGesture = .none
    @Published private(set) var lastResolvedIntent: AppIntent = .none
    @Published private(set) var lastCommandSource: CommandSource = .none
    @Published private(set) var suppressionReason: String? = nil

    // MARK: - Output

    /// Single downstream callback. Wired in ContentView.setupLayers to
    /// GameProfileManager.mapIntent → BandBLEManager.send.
    var onIntent: ((AppIntent) -> Void)?

    // MARK: - Conflict tuning

    /// Seconds after a body intent fires during which a conflicting hand
    /// gesture is suppressed.
    var conflictWindow: TimeInterval = 0.5

    // MARK: - Internal state

    private var lastBodyIntent: AppIntent = .none
    private var lastBodyIntentTime: Date = .distantPast
    // Fix 4: Independent body-channel cooldown. MotionInterpreter is the primary gate,
    // but InputCoordinator guards independently so that a spurious double-call to
    // receive(bodyEvent:) (e.g. if onMotionEvent is wired to multiple callers) cannot
    // dispatch two BLE commands for the same gesture onset.
    private var lastBodyReceiveTime: Date = .distantPast
    private let bodyReceiveCooldown: TimeInterval = 0.5

    // MARK: - Input: body

    func receive(bodyEvent: MotionEvent) {
        guard bodyEvent != .none else { return }

        // Fix 4: Cooldown guard — rejects a repeat of the same event within 500ms.
        // This is a secondary gate; MotionInterpreter's confirmation+cooldown is primary.
        let now = Date()
        guard now.timeIntervalSince(lastBodyReceiveTime) >= bodyReceiveCooldown else { return }
        lastBodyReceiveTime = now

        let intent = AppIntent.from(bodyEvent)
        guard intent != .none else { return }

        lastBodyEvent = bodyEvent
        lastBodyIntent = intent
        lastBodyIntentTime = Date()
        suppressionReason = nil
        lastResolvedIntent = intent
        lastCommandSource = .body

        print("🕹️ [Coord] Body: \(intent.displayName)")
        onIntent?(intent)
    }

    // MARK: - Input: hand

    func receive(handGesture: HandGesture) {
        guard handGesture != .none else { return }

        let intent = AppIntent.from(handGesture)
        guard intent != .none else { return }

        lastHandGesture = handGesture

        // ── Conflict check ────────────────────────────────────────────────
        let elapsed = Date().timeIntervalSince(lastBodyIntentTime)
        if elapsed < conflictWindow, conflicts(body: lastBodyIntent, hand: intent) {
            let ms = Int(elapsed * 1000)
            let reason = "\(lastBodyIntent.displayName) fired \(ms)ms ago"
            suppressionReason = reason
            print("🚫 [Coord] Hand suppressed: \(intent.displayName) — \(reason)")
            return
        }

        // ── Fire ──────────────────────────────────────────────────────────
        suppressionReason = nil
        lastResolvedIntent = intent
        lastCommandSource = .hand

        print("🖐️ [Coord] Hand: \(intent.displayName)")
        onIntent?(intent)
    }

    // MARK: - Conflict table

    /// True when both intents imply the same direction and the hand would
    /// send a redundant command within the conflict window.
    private func conflicts(body: AppIntent, hand: AppIntent) -> Bool {
        switch (body, hand) {
        case (.leanLeft,  .handSwipeLeft):  return true
        case (.leanRight, .handSwipeRight): return true
        default:                             return false
        }
    }
}
