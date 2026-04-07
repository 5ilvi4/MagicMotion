// ControllerSession.swift
// MagicMotion
//
// Runtime center for MagicMotion Home controller mode.
// This replaces GameSession as the primary session object for active play.
//
// Responsibilities:
//   - Own the ControllerSessionState state machine
//   - Hold the current ActiveControlProfile (game + child calibration combination)
//   - Track session-level activity: resolved intents, mapped commands, elapsed time
//
// NOT responsible for:
//   - Game loop simulation (no CADisplayLink, no obstacle/coin spawning)
//   - Motion event interpretation (MotionInterpreter owns that)
//   - BLE command dispatch (BandBLEManager owns that)
//   - Body calibration execution (CalibrationEngine owns that)
//   - Reading/writing UserDefaults (callers supply explicit GameProfile + BodyCalibration)
//
// Wiring (done in ContentView.setupLayers):
//   CalibrationEngine .complete(cal)   → controllerSession.prepare(gameProfile:calibration:)
//   profileManager.onProfileChanged    → controllerSession.prepare(gameProfile:calibration:)
//   coordinator.onIntent               → controllerSession.handle(intent:)
//                                      → controllerSession.recordMappedCommand(_:)  (after BLE send)
//   interpreter.onSafetyZoneViolation  → controllerSession.pause(reason: .safetyZoneViolation)
//   gameLauncher "Play Game"           → controllerSession.activate()
//   gameLauncher "Return from game"    → controllerSession.end()
//   onSessionEnded                     → SessionReportStore.save(_:)

import Foundation
import Combine

final class ControllerSession: ObservableObject {

    // MARK: - Callbacks

    /// Called when a session ends with recordable activity (duration > 1 s or commands sent).
    /// Wire to SessionReportStore.save(_:) in ContentView.setupLayers().
    var onSessionEnded: ((SessionReport) -> Void)?

    // MARK: - Published

    @Published private(set) var state: ControllerSessionState = .idle
    @Published private(set) var activeProfile: ActiveControlProfile? = nil

    /// Last raw AppIntent resolved by InputCoordinator this session.
    @Published private(set) var lastIntent: AppIntent = .none

    /// Last GameCommand successfully mapped and sent to the band this session.
    @Published private(set) var lastMappedCommand: GameCommand? = nil

    /// Total intents received while active (counts every resolved motion / hand input).
    @Published private(set) var intentCount: Int = 0

    /// Total commands sent to the band while active (subset of intents that had a mapping).
    @Published private(set) var commandCount: Int = 0

    /// Elapsed seconds since activate() was called (pauses do not accumulate).
    @Published private(set) var sessionDuration: TimeInterval = 0

    // MARK: - State transitions

    /// Assemble an ActiveControlProfile from explicit components and move to
    /// .ready (personalized calibration) or .needsCalibration (uncalibrated defaults).
    /// Call whenever the game selection or body calibration changes.
    func prepare(gameProfile: GameProfile, calibration: BodyCalibration) {
        let profile = ActiveControlProfile(gameProfile: gameProfile, calibration: calibration)
        activeProfile = profile
        let next: ControllerSessionState = profile.isPersonalized ? .ready : .needsCalibration
        transition(to: next)
        print("🕹️ [ControllerSession] Prepared — game: \(profile.displayName) personalized: \(profile.isPersonalized) → \(next)")
    }

    /// Begin the active controller session. Valid only from .ready.
    func activate() {
        guard case .ready = state else { return }
        intentCount     = 0
        commandCount    = 0
        lastIntent      = .none
        lastMappedCommand = nil
        sessionDuration = 0
        sessionStartDate = Date()
        startDurationTimer()
        transition(to: .active)
        print("🕹️ [ControllerSession] Activated — \(activeProfile?.displayName ?? "no profile")")
    }

    /// Pause an active session for a named reason.
    func pause(reason: ControllerPauseReason) {
        guard case .active = state else { return }
        stopDurationTimer()
        transition(to: .paused(reason: reason))
        print("🕹️ [ControllerSession] Paused — reason: \(reason)")
    }

    /// Resume from a pause. Continues accumulating duration from where it left off.
    func resume() {
        guard case .paused = state else { return }
        // Shift the start date back so elapsed time is preserved across the pause.
        sessionStartDate = Date().addingTimeInterval(-sessionDuration)
        startDurationTimer()
        transition(to: .active)
        print("🕹️ [ControllerSession] Resumed")
    }

    /// End the session cleanly. Call when the user returns from the external game.
    /// Fires onSessionEnded with a SessionReport when the session had recordable activity.
    func end() {
        stopDurationTimer()

        // Only persist sessions with real activity: at least 1 second active
        // or at least one command sent.
        if sessionDuration > 1.0 || commandCount > 0 {
            let report = SessionReport(
                id:             UUID(),
                date:           sessionStartDate ?? Date(),
                gameName:       activeProfile?.displayName ?? "Unknown",
                duration:       sessionDuration,
                intentCount:    intentCount,
                commandCount:   commandCount,
                lastCommand:    lastMappedCommand?.displayName,
                wasPersonalized: activeProfile?.isPersonalized ?? false
            )
            onSessionEnded?(report)
        }

        transition(to: .ended)
        print("🕹️ [ControllerSession] Ended — intents: \(intentCount) commands: \(commandCount) duration: \(Int(sessionDuration))s")
    }

    /// Reset to idle, clearing all session data. Safe to call from any state.
    func reset() {
        stopDurationTimer()
        sessionStartDate  = nil
        intentCount       = 0
        commandCount      = 0
        lastIntent        = .none
        lastMappedCommand = nil
        sessionDuration   = 0
        activeProfile     = nil
        transition(to: .idle)
        print("🕹️ [ControllerSession] Reset")
    }

    // MARK: - Activity recording

    /// Record a raw resolved intent from InputCoordinator. No-op when not active.
    /// Call this before mapping to a GameCommand so every resolved motion is captured.
    func handle(intent: AppIntent) {
        guard case .active = state else { return }
        lastIntent  = intent
        intentCount += 1
    }

    /// Record that a GameCommand was successfully mapped and sent to the band.
    /// No-op when not active. Call this after BandBLEManager.send(command:).
    func recordMappedCommand(_ command: GameCommand) {
        guard case .active = state else { return }
        lastMappedCommand = command
        commandCount     += 1
    }

    // MARK: - Private

    private var sessionStartDate: Date? = nil
    private var durationTimer: Timer?   = nil

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.sessionStartDate else { return }
            self.sessionDuration = Date().timeIntervalSince(start)
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func transition(to newState: ControllerSessionState) {
        state = newState
    }
}
