// GameProfileModels.swift
// MagicMotion
//
// Data model layer for game profile management.
// These types are Codable so profiles can be stored as JSON in the app bundle
// or fetched from a remote config endpoint in a future iteration.

import Foundation

// MARK: - Game Identifier

enum GameID: String, Codable, CaseIterable {
    case subwaySurfers = "subwaySurfers"
    case templeRun     = "templeRun"
    case crossyRoad    = "crossyRoad"

    /// Snake-case filename used for the bundled JSON resource (without extension).
    /// Kept separate from rawValue so the Codable key ("subwaySurfers") and the
    /// file name ("subway_surfers") can differ without breaking JSON decoding.
    var bundleFileName: String {
        switch self {
        case .subwaySurfers: return "subway_surfers"
        case .templeRun:     return "temple_run"
        case .crossyRoad:    return "crossy_road"
        }
    }
}

// MARK: - Game Command
// Maps 1:1 to the firmware HID byte values defined in band-firmware/Config.h.
// The byte → key mapping is fixed by firmware; these names document what each byte does.

enum GameCommand: UInt8, Codable, CaseIterable {
    case leftArrow  = 0x01
    case rightArrow = 0x02
    case spacebar   = 0x03
    case downArrow  = 0x04

    var displayName: String {
        switch self {
        case .leftArrow:  return "LEFT ←"
        case .rightArrow: return "RIGHT →"
        case .spacebar:   return "SPACE"
        case .downArrow:  return "DOWN ↓"
        }
    }
}

// MARK: - Motion Event Key
// String keys used in profile JSON, one per named MotionEvent case.
// Associated-value cases (.freeze, .none) intentionally excluded — they are
// not dispatchable game commands.

enum MotionEventKey: String, Codable, CaseIterable {
    case handsUp    = "handsUp"
    case handsDown  = "handsDown"
    case leanLeft   = "leanLeft"
    case leanRight  = "leanRight"
    case jump       = "jump"
    case squat      = "squat"

    init?(motionEvent: MotionEvent) {
        switch motionEvent {
        case .handsUp:           self = .handsUp
        case .handsDown:         self = .handsDown
        case .leanLeft:          self = .leanLeft
        case .leanRight:         self = .leanRight
        case .jump:              self = .jump
        case .squat:             self = .squat
        case .freeze, .none:     return nil
        }
    }

    var asMotionEvent: MotionEvent {
        switch self {
        case .handsUp:    return .handsUp
        case .handsDown:  return .handsDown
        case .leanLeft:   return .leanLeft
        case .leanRight:  return .leanRight
        case .jump:       return .jump
        case .squat:      return .squat
        }
    }
}

// MARK: - Game Profile

struct GameProfile: Codable {
    let gameID: GameID
    let displayName: String
    /// Keys are MotionEventKey.rawValue strings; values are GameCommand raw bytes.
    let mapping: [String: GameCommand]

    /// Returns the GameCommand for a MotionEvent, or nil if unmapped.
    func command(for event: MotionEvent) -> GameCommand? {
        guard let key = MotionEventKey(motionEvent: event) else { return nil }
        return mapping[key.rawValue]
    }

    /// The MotionEvents that have a mapping in this profile.
    var supportedEvents: [MotionEvent] {
        mapping.keys.compactMap { MotionEventKey(rawValue: $0)?.asMotionEvent }
    }
}
