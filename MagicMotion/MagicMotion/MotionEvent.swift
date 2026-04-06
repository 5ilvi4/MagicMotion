// MotionEvent.swift
// MotionMind
//
// Vocabulary of body events the Motion Interpreter can fire.
// Used by GameSession and GameView. No MediaPipe dependencies.

import Foundation

enum MotionEvent: Equatable {
    case handsUp
    case handsDown
    case leanLeft
    case leanRight
    case jump
    case squat
    case freeze(duration: TimeInterval)
    case none

    var displayName: String {
        switch self {
        case .handsUp:              return "Hands Up"
        case .handsDown:            return "Hands Down"
        case .leanLeft:             return "Lean Left"
        case .leanRight:            return "Lean Right"
        case .jump:                 return "Jump"
        case .squat:                return "Squat"
        case .freeze(let d):        return "Freeze (\(String(format: "%.1f", d))s)"
        case .none:                 return "neutral"
        }
    }
}
