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
