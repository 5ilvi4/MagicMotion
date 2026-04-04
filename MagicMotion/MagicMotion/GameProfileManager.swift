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
        log("🎮 Active game: \(profile.displayName) — \(profile.mapping.count) mappings")
    }

    // MARK: - Runtime Mapping

    /// Map a MotionEvent to a GameCommand for the active profile.
    /// Returns nil if no active profile is set or the event is not mapped.
    func mapEvent(_ event: MotionEvent) -> GameCommand? {
        guard let profile = activeProfile else {
            log("⚠️ mapEvent called but no active profile is set")
            return nil
        }
        let command = profile.command(for: event)
        if let command {
            lastMappedCommand = command
            lastUnmappedEvent = nil
        } else if event != .none {
            lastMappedCommand = nil
            lastUnmappedEvent = event
            log("ℹ️ '\(event.displayName)' has no mapping in '\(profile.displayName)'")
        }
        return command
    }

    /// Returns the MotionEvents the active profile can dispatch.
    func getSupportedEvents() -> [MotionEvent] {
        activeProfile?.supportedEvents ?? []
    }

    // MARK: - Logging

    private func log(_ msg: String) {
        #if DEBUG
        print("[GameProfileManager] \(msg)")
        #endif
    }
}
