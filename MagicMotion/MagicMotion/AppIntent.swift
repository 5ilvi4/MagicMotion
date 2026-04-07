// AppIntent.swift
// MagicMotion
//
// Normalized input intent — the single type emitted by InputCoordinator
// and consumed by GameProfileManager.
//
// Both body gestures and hand gestures produce an AppIntent.
// GameProfileManager maps AppIntent → GameCommand.
// Neither InputCoordinator nor hand-gesture code knows about GameCommand.
//
// Cases mirror MotionEventKey exactly for body intents.
// Hand-sourced intents are distinguished by name but may map to the same
// GameCommand as body intents (e.g. swipeLeft → leftArrow, same as leanLeft).
// That equivalence is defined in the profile JSON / GameProfile, not here.

import Foundation

enum AppIntent: Equatable {
    // ── Body-sourced ──────────────────────────────────────────────────────
    case handsUp
    case handsDown
    case leanLeft
    case leanRight
    case jump
    case squat

    // ── Hand-sourced ──────────────────────────────────────────────────────
    case handSwipeLeft
    case handSwipeRight

    // ── Internal ──────────────────────────────────────────────────────────
    case none

    var displayName: String {
        switch self {
        case .handsUp:        return "Hands Up"
        case .handsDown:      return "Hands Down"
        case .leanLeft:       return "Lean Left"
        case .leanRight:      return "Lean Right"
        case .jump:           return "Jump"
        case .squat:          return "Squat"
        case .handSwipeLeft:  return "Hand Swipe ←"
        case .handSwipeRight: return "Hand Swipe →"
        case .none:           return "—"
        }
    }

    /// Plain-English description of the physical motion. Shown in the gesture list.
    var motionDescription: String {
        switch self {
        case .handsUp:        return "Raise both hands above your shoulders"
        case .handsDown:      return "Lower both hands to your sides"
        case .leanLeft:       return "Shift your weight to the left"
        case .leanRight:      return "Shift your weight to the right"
        case .jump:           return "Jump up"
        case .squat:          return "Bend your knees and squat down"
        case .handSwipeLeft:  return "Swipe your hand to the left"
        case .handSwipeRight: return "Swipe your hand to the right"
        case .none:           return "—"
        }
    }

    /// SF Symbol name representing the motion. Used in GestureListView.
    var symbolName: String {
        switch self {
        case .handsUp:        return "arrow.up.to.line"
        case .handsDown:      return "arrow.down.to.line"
        case .leanLeft:       return "arrow.left"
        case .leanRight:      return "arrow.right"
        case .jump:           return "figure.jumprope"
        case .squat:          return "arrow.down.circle"
        case .handSwipeLeft:  return "hand.draw"
        case .handSwipeRight: return "hand.draw"
        case .none:           return "minus"
        }
    }

    /// Display order in the gesture list (body gestures before hand gestures).
    var sortOrder: Int {
        switch self {
        case .leanLeft:       return 0
        case .leanRight:      return 1
        case .jump:           return 2
        case .squat:          return 3
        case .handsUp:        return 4
        case .handsDown:      return 5
        case .handSwipeLeft:  return 6
        case .handSwipeRight: return 7
        case .none:           return 99
        }
    }

    // MARK: - Conversions from existing types

    static func from(_ event: MotionEvent) -> AppIntent {
        switch event {
        case .handsUp:    return .handsUp
        case .handsDown:  return .handsDown
        case .leanLeft:   return .leanLeft
        case .leanRight:  return .leanRight
        case .jump:       return .jump
        case .squat:      return .squat
        case .freeze, .none: return .none
        }
    }

    /// Reverse lookup from profile key back to AppIntent (for getSupportedIntents).
    static func from(_ key: MotionEventKey) -> AppIntent? {
        switch key {
        case .handsUp:        return .handsUp
        case .handsDown:      return .handsDown
        case .leanLeft:       return .leanLeft
        case .leanRight:      return .leanRight
        case .jump:           return .jump
        case .squat:          return .squat
        case .handSwipeLeft:  return .handSwipeLeft
        case .handSwipeRight: return .handSwipeRight
        }
    }

    static func from(_ gesture: HandGesture) -> AppIntent {
        switch gesture {
        case .swipeLeft:  return .handSwipeLeft
        case .swipeRight: return .handSwipeRight
        case .none:       return .none
        }
    }
}
