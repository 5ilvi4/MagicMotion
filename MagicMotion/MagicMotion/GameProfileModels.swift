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

    /// URL scheme used to deep-link into the game. nil = not installed / unknown.
    ///
    /// Verification status:
    ///   subwaySurfers — "subwaysurfers://" confirmed via App Store listing and community sources.
    ///   templeRun     — "imobi://" is the registered scheme for Temple Run 2 (not "templerun2://").
    ///                   TODO: verify against the actual installed app before shipping.
    ///   crossyRoad    — No public URL scheme documented by Hipster Whale.
    ///                   TODO: verify or remove before shipping — may have no deep-link support.
    var urlScheme: String? {
        switch self {
        case .subwaySurfers: return "subwaysurfers://"
        case .templeRun:     return nil   // TODO: verify Temple Run 2 URL scheme before enabling
        case .crossyRoad:    return nil   // TODO: verify Crossy Road URL scheme before enabling
        }
    }

    /// App Store numeric ID for fallback install prompt.
    ///
    /// Verification status:
    ///   subwaySurfers — 533239571 confirmed.
    ///   templeRun     — 579827023 confirmed (Temple Run 2).
    ///   crossyRoad    — 924979111 confirmed.
    var appStoreID: String {
        switch self {
        case .subwaySurfers: return "533239571"
        case .templeRun:     return "579827023"
        case .crossyRoad:    return "924979111"
        }
    }
}

// MARK: - Game Command
//
// Byte values written to the M5StickC Plus2 CMD characteristic.
// The M5 firmware maps each byte to a BLE HID D-pad (hat switch) direction:
//   0x01 → HAT_LEFT   (lane left)
//   0x02 → HAT_RIGHT  (lane right)
//   0x03 → HAT_UP     (jump)
//   0x04 → HAT_DOWN   (slide / roll)
//   0x00 → HAT_NEUTRAL (release — sent automatically by BandBLEManager after hold)
//
// Case names use their in-game action semantics, not their legacy keyboard names.
// The underlying raw values are stable and must not change — the firmware is keyed on them.

enum GameCommand: UInt8, Codable, CaseIterable {
    case leftArrow  = 0x01   // D-pad left  — move left / lane change left
    case rightArrow = 0x02   // D-pad right — move right / lane change right
    case spacebar   = 0x03   // D-pad up    — jump (legacy name kept for JSON compatibility)
    case downArrow  = 0x04   // D-pad down  — slide / roll / crouch

    /// Short label used in the debug BLE test panel.
    var displayName: String {
        switch self {
        case .leftArrow:  return "LEFT ←"
        case .rightArrow: return "RIGHT →"
        case .spacebar:   return "JUMP ↑"
        case .downArrow:  return "SLIDE ↓"
        }
    }

    /// Human-readable in-game action name shown in the gesture list.
    var gameActionName: String {
        switch self {
        case .leftArrow:  return "Move Left"
        case .rightArrow: return "Move Right"
        case .spacebar:   return "Jump"
        case .downArrow:  return "Slide / Roll"
        }
    }
}

// MARK: - Motion Event Key
// String keys used in profile JSON, covering both body (MotionEvent) and
// hand (HandGesture) intents. Codable so profiles can be stored as JSON.
// Associated-value cases (.freeze, .none) intentionally excluded.

enum MotionEventKey: String, Codable, CaseIterable {
    // Body-sourced
    case handsUp         = "handsUp"
    case handsDown       = "handsDown"
    case leanLeft        = "leanLeft"
    case leanRight       = "leanRight"
    case jump            = "jump"
    case squat           = "squat"
    // Hand-sourced
    case handSwipeLeft   = "handSwipeLeft"
    case handSwipeRight  = "handSwipeRight"

    init?(intent: AppIntent) {
        switch intent {
        case .handsUp:        self = .handsUp
        case .handsDown:      self = .handsDown
        case .leanLeft:       self = .leanLeft
        case .leanRight:      self = .leanRight
        case .jump:           self = .jump
        case .squat:          self = .squat
        case .handSwipeLeft:  self = .handSwipeLeft
        case .handSwipeRight: self = .handSwipeRight
        case .none:           return nil
        }
    }
}

// MARK: - Game Profile

struct GameProfile: Codable {
    let gameID: GameID
    let displayName: String
    /// Keys are MotionEventKey.rawValue strings; values are GameCommand raw bytes.
    let mapping: [String: GameCommand]

    /// Recognizers active for this game. nil = all recognizers enabled (legacy behaviour).
    /// Specify to restrict which gesture classes are checked — useful when a game
    /// should not respond to certain gesture types (e.g. a hand-free game ignoring hand swipes).
    var enabledRecognizers: [RecognizerID]?

    /// Per-recognizer tuning overrides. nil = use each recognizer's built-in defaults.
    /// Keys are RecognizerID.rawValue strings; values are threshold/config dictionaries.
    /// Example JSON:
    ///   "recognizerConfig": { "bodyLean": { "threshold": 0.06 } }
    var recognizerConfig: [String: [String: Double]]?

    // MARK: - Codable (backward-compatible with JSON lacking the new fields)

    enum CodingKeys: String, CodingKey {
        case gameID, displayName, mapping, enabledRecognizers, recognizerConfig
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameID             = try c.decode(GameID.self,              forKey: .gameID)
        displayName        = try c.decode(String.self,              forKey: .displayName)
        mapping            = try c.decode([String: GameCommand].self, forKey: .mapping)
        enabledRecognizers = try c.decodeIfPresent([RecognizerID].self,           forKey: .enabledRecognizers)
        recognizerConfig   = try c.decodeIfPresent([String: [String: Double]].self, forKey: .recognizerConfig)
    }

    // Plain memberwise init for hardcoded fallbacks in GameProfileStore.
    init(gameID: GameID, displayName: String, mapping: [String: GameCommand],
         enabledRecognizers: [RecognizerID]? = nil,
         recognizerConfig: [String: [String: Double]]? = nil) {
        self.gameID             = gameID
        self.displayName        = displayName
        self.mapping            = mapping
        self.enabledRecognizers = enabledRecognizers
        self.recognizerConfig   = recognizerConfig
    }

    // MARK: - Helpers

    /// Returns the GameCommand for a normalized AppIntent, or nil if unmapped.
    func command(for intent: AppIntent) -> GameCommand? {
        guard let key = MotionEventKey(intent: intent) else { return nil }
        return mapping[key.rawValue]
    }

    /// True when the given recognizer should run for this profile.
    /// Returns true for all recognizers when enabledRecognizers is nil (legacy default).
    func isEnabled(_ recognizerID: RecognizerID) -> Bool {
        guard let list = enabledRecognizers else { return true }
        return list.contains(recognizerID)
    }

    /// Returns a RecognizerConfig for the given recognizer, or .empty if none defined.
    func config(for recognizerID: RecognizerID) -> RecognizerConfig {
        guard let dict = recognizerConfig?[recognizerID.rawValue] else { return .empty }
        return RecognizerConfig(values: dict)
    }
}
