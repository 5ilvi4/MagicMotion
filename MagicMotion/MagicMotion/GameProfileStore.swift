// GameProfileStore.swift
// MagicMotion
//
// Pure storage layer for game profiles.
// Responsibilities:
//   - Load GameProfile JSON files from the app bundle.
//   - Cache loaded profiles in memory.
//   - Persist and restore the selected active profile ID via UserDefaults.
//   - Surface load errors without crashing the app.
//
// This class has no knowledge of BLE, gesture mapping, or SwiftUI.
// GameProfileManager owns it and bridges it to the rest of the app.
//
// To add a new game:
//   1. Add a case to GameID (with a bundleFileName).
//   2. Add a JSON file named <bundleFileName>.json to the app bundle.
//   3. Optionally add a hardcodedFallback case below so the app works offline.

import Foundation

// MARK: - Load Error

enum ProfileLoadError: Error {
    case fileNotFound(GameID)
    case decodingFailed(GameID, underlyingError: Error)

    var localizedDescription: String {
        switch self {
        case .fileNotFound(let id):
            return "Profile file '\(id.bundleFileName).json' not found in bundle."
        case .decodingFailed(let id, let error):
            return "Failed to decode '\(id.bundleFileName).json': \(error.localizedDescription)"
        }
    }
}

// MARK: - GameProfileStore

final class GameProfileStore {

    // MARK: - Constants

    private static let activeProfileKey = "com.magicmotion.activeProfileID"

    // MARK: - State

    /// All successfully loaded profiles, keyed by GameID.
    private(set) var cache: [GameID: GameProfile] = [:]

    /// Any errors that occurred during load. Populated in init; safe to inspect later.
    private(set) var loadErrors: [ProfileLoadError] = []

    // MARK: - Init
    // Eagerly loads all known profiles so queries are synchronous.

    init() {
        loadAll()
    }

    // MARK: - Public API

    /// Returns all profiles that loaded successfully.
    func availableProfiles() -> [GameProfile] {
        Array(cache.values).sorted { $0.displayName < $1.displayName }
    }

    /// Returns a single profile by game ID, or nil if it failed to load.
    func loadProfile(gameID: GameID) -> GameProfile? {
        cache[gameID]
    }

    /// Convenience: returns all loaded profiles (alias for availableProfiles).
    func loadAllProfiles() -> [GameProfile] {
        availableProfiles()
    }

    // MARK: - Active Profile Persistence

    /// Persists the selected game ID to UserDefaults.
    func setActiveProfile(gameID: GameID) {
        UserDefaults.standard.set(gameID.rawValue, forKey: Self.activeProfileKey)
    }

    /// Returns the last persisted game ID, or nil if none has been set.
    func getActiveProfileID() -> GameID? {
        guard let raw = UserDefaults.standard.string(forKey: Self.activeProfileKey) else {
            return nil
        }
        return GameID(rawValue: raw)
    }

    /// Returns the full profile for the last persisted game ID, or nil.
    func getActiveProfile() -> GameProfile? {
        guard let id = getActiveProfileID() else { return nil }
        return cache[id]
    }

    // MARK: - Bundle Loading

    private func loadAll() {
        for gameID in GameID.allCases {
            switch loadFromBundle(gameID) {
            case .success(let profile):
                cache[gameID] = profile
            case .failure(let error):
                loadErrors.append(error)
                // Bad or missing JSON → fall back to hardcoded default so the app
                // works without resource files (useful in tests and first launches).
                if let fallback = hardcodedFallback(for: gameID) {
                    cache[gameID] = fallback
                    debugLog("⚠️ Using hardcoded fallback for \(gameID.rawValue): \(error.localizedDescription)")
                } else {
                    debugLog("❌ No profile available for \(gameID.rawValue): \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadFromBundle(_ gameID: GameID) -> Result<GameProfile, ProfileLoadError> {
        // Try GameProfiles subfolder first, then flat bundle root.
        let url = Bundle.main.url(forResource: gameID.bundleFileName,
                                  withExtension: "json",
                                  subdirectory: "GameProfiles")
            ?? Bundle.main.url(forResource: gameID.bundleFileName,
                               withExtension: "json")

        guard let url else {
            return .failure(.fileNotFound(gameID))
        }

        do {
            let data = try Data(contentsOf: url)
            let profile = try JSONDecoder().decode(GameProfile.self, from: data)
            debugLog("📄 Loaded \(gameID.bundleFileName).json")
            return .success(profile)
        } catch {
            return .failure(.decodingFailed(gameID, underlyingError: error))
        }
    }

    // MARK: - Hardcoded Fallbacks
    // These mirror band-firmware/Config.h byte values.
    // They are the last resort — prefer keeping JSON files up to date.

    private func hardcodedFallback(for gameID: GameID) -> GameProfile? {
        switch gameID {
        case .subwaySurfers:
            return GameProfile(
                gameID: .subwaySurfers,
                displayName: "Subway Surfers",
                mapping: [
                    "leanLeft":  .leftArrow,
                    "leanRight": .rightArrow,
                    "jump":      .spacebar,
                    "squat":     .downArrow
                ]
            )
        case .templeRun:
            // Temple Run: player raises hands to jump rather than physically jumping.
            // "jump" (hip-rise) is intentionally unmapped here.
            return GameProfile(
                gameID: .templeRun,
                displayName: "Temple Run",
                mapping: [
                    "leanLeft":  .leftArrow,
                    "leanRight": .rightArrow,
                    "handsUp":   .spacebar,
                    "squat":     .downArrow
                ]
            )
        case .crossyRoad:
            // Crossy Road: hop forward with hands-up, step back with hands-down.
            // Physical jump and squat are not used — road-crossing is arm-gesture driven.
            // First profile to use "handsDown", exercising the full MotionEventKey vocabulary.
            return GameProfile(
                gameID: .crossyRoad,
                displayName: "Crossy Road",
                mapping: [
                    "leanLeft":  .leftArrow,
                    "leanRight": .rightArrow,
                    "handsUp":   .spacebar,
                    "handsDown": .downArrow
                ]
            )
        }
    }

    // MARK: - Debug Logging

    private func debugLog(_ msg: String) {
        #if DEBUG
        print("[GameProfileStore] \(msg)")
        #endif
    }
}
