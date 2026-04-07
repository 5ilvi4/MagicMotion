// GameProfileManager.swift
// MagicMotion
//
// Layer 3.5 — sits between MotionInterpreter and BandBLEManager.
// Converts MotionEvent → GameCommand using the active game profile.
//
// Data flow:
//   MotionInterpreter.onMotionEvent (MotionEvent, fires on MainActor)
//     → GameProfileManager.mapEvent(_:) → GameCommand?
//         → BandBLEManager.send(command:)
//
// Storage is delegated entirely to GameProfileStore.
// This class owns SwiftUI-facing @Published state and the runtime mapping.

import Combine
import Foundation

@MainActor
final class GameProfileManager: ObservableObject {

    // MARK: - Published (SwiftUI reactivity)

    @Published private(set) var activeProfile: GameProfile?
    @Published private(set) var activeGameID: GameID?
    /// Last GameCommand produced by mapEvent(_:). Nil until first successful mapping.
    @Published private(set) var lastMappedCommand: GameCommand?
    /// Last MotionEvent that had no mapping in the active profile. Nil until first miss.
    @Published private(set) var lastUnmappedEvent: MotionEvent?

    /// Called on MainActor whenever the active profile changes via setActiveGame(_:).
    var onProfileChanged: ((GameProfile) -> Void)?

    // MARK: - Storage

    private let store = GameProfileStore()

    // MARK: - Init

    init() {
        // Log any bundle load errors surfaced by the store.
        for error in store.loadErrors {
            log("⚠️ \(error.localizedDescription)")
        }
        // Restore the last selected profile from UserDefaults.
        if let restoredID = store.getActiveProfileID(),
           let restoredProfile = store.loadProfile(gameID: restoredID) {
            activeGameID = restoredID
            activeProfile = restoredProfile
            log("♻️ Restored active game: \(restoredProfile.displayName)")
        }
    }

    // MARK: - Public API

    /// Set and persist the active game profile.
    func setActiveProfile(_ gameID: GameID) {
        setActiveGame(gameID)  // single implementation; setActiveGame also persists
    }

    /// Returns the currently active profile, or nil if none is set.
    func getActiveProfile() -> GameProfile? { activeProfile }

    /// Returns the currently active game ID, or nil if none is set.
    func getActiveProfileID() -> GameID? { activeGameID }

    /// Returns all profiles that loaded successfully.
    func availableProfiles() -> [GameProfile] { store.availableProfiles() }

    /// Returns all loaded profiles (alias for availableProfiles).
    func loadAllProfiles() -> [GameProfile] { store.loadAllProfiles() }

    /// Returns a single profile by game ID, or nil if unavailable.
    func loadProfile(gameID: GameID) -> GameProfile? { store.loadProfile(gameID: gameID) }

    // MARK: - Backward-compatible API (used by ContentView.setupLayers)

    /// Select and persist the active game. Logs a warning if the profile isn't available.
    func setActiveGame(_ gameID: GameID) {
        guard let profile = store.loadProfile(gameID: gameID) else {
            log("⚠️ No profile available for \(gameID.rawValue)")
            return
        }
        activeGameID = gameID
        activeProfile = profile
        lastMappedCommand = nil
        lastUnmappedEvent = nil
        store.setActiveProfile(gameID: gameID)
        onProfileChanged?(profile)
        log("🎮 Active game: \(profile.displayName) — \(profile.mapping.count) mappings")
    }

    // MARK: - Runtime Mapping

    /// Map a normalized AppIntent to a GameCommand for the active profile.
    /// Returns nil if no active profile is set or the intent is not mapped.
    func mapIntent(_ intent: AppIntent) -> GameCommand? {
        guard let profile = activeProfile else {
            log("⚠️ mapIntent called but no active profile is set")
            return nil
        }
        let command = profile.command(for: intent)
        if let command {
            lastMappedCommand = command
            lastUnmappedEvent = nil
        } else if intent != .none {
            lastMappedCommand = nil
            // Keep lastUnmappedEvent as MotionEvent for existing HUD — only set for body intents.
            log("ℹ️ '\(intent.displayName)' has no mapping in '\(profile.displayName)'")
        }
        return command
    }

    /// Convenience bridge: converts MotionEvent → AppIntent → GameCommand.
    /// Used by existing callers during migration.
    func mapEvent(_ event: MotionEvent) -> GameCommand? {
        mapIntent(AppIntent.from(event))
    }

    /// Returns all AppIntents mapped in the active profile.
    func getSupportedIntents() -> [AppIntent] {
        guard let profile = activeProfile else { return [] }
        return profile.mapping.keys.compactMap { MotionEventKey(rawValue: $0).flatMap { AppIntent.from($0) } }
    }

    // MARK: - Logging

    private func log(_ msg: String) {
        #if DEBUG
        print("[GameProfileManager] \(msg)")
        #endif
    }
}
