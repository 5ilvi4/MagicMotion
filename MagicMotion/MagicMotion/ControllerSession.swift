// ControllerSession.swift
// MagicMotion
//
// Runtime center for MagicMotion Home controller mode.
// Owns the ControllerSessionState state machine, the current ActiveControlProfile,
// and all session-level activity counters used to produce the SessionReport.
//
// NOT responsible for:
//   - Game loop simulation
//   - Motion event interpretation (MotionInterpreter owns that)
//   - BLE command dispatch (BandBLEManager owns that)
//   - Body calibration (CalibrationEngine owns that)
//   - Reading/writing UserDefaults (callers supply explicit GameProfile + BodyCalibration)
//
// Wiring (done in ContentView.setupLayers):
//   CalibrationEngine .complete(cal)   → prepare(gameProfile:calibration:)
//   profileManager.onProfileChanged    → prepare(gameProfile:calibration:)
//   coordinator.onIntent               → handle(intent:)
//                                      → recordMappedCommand(_:)  (after BLE send)
//   interpreter.onSafetyZoneViolation  → recordSafetyZoneViolation() then pause(.safetyZoneViolation)
//   interpreter.onTrackingLost         → recordTrackingLost() then pause(.trackingLost)
//   band.onDisconnect                  → recordBandDisconnect()
//   gameLauncher "Play Game"           → activate()
//   gameLauncher "Return from game"    → end()
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
        resetCounters()
        sessionStartDate = Date()
        startDurationTimer()
        transition(to: .active)
        print("🕹️ [ControllerSession] Activated — \(activeProfile?.displayName ?? "no profile")")
    }

    /// Pause an active session for a named reason.
    func pause(reason: ControllerPauseReason) {
        guard case .active = state else { return }
        stopDurationTimer()
        pauseCount += 1
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
                id:                      UUID(),
                date:                    sessionStartDate ?? Date(),
                gameName:                activeProfile?.displayName ?? "Unknown",
                gameID:                  activeProfile?.gameID.rawValue,
                duration:                sessionDuration,
                intentCount:             intentCount,
                commandCount:            commandCount,
                lastCommand:             lastMappedCommand?.displayName,
                wasPersonalized:         activeProfile?.isPersonalized ?? false,
                intentCounts:            intentTypeCounts,
                commandCounts:           commandTypeCounts,
                trackingLostCount:       trackingLostCount,
                safetyZoneViolationCount: safetyZoneViolationCount,
                bandDisconnectCount:     bandDisconnectCount,
                pauseCount:              pauseCount
            )
            onSessionEnded?(report)
        }

        transition(to: .ended)
        print("🕹️ [ControllerSession] Ended — intents:\(intentCount) cmds:\(commandCount) dur:\(Int(sessionDuration))s trackingLost:\(trackingLostCount) safetyZone:\(safetyZoneViolationCount) pauses:\(pauseCount)")
    }

    /// Reset to idle, clearing all session data. Safe to call from any state.
    func reset() {
        stopDurationTimer()
        sessionStartDate = nil
        resetCounters()
        activeProfile = nil
        transition(to: .idle)
        print("🕹️ [ControllerSession] Reset")
    }

    // MARK: - Activity recording

    /// Record a raw resolved intent from InputCoordinator. No-op when not active.
    func handle(intent: AppIntent) {
        guard case .active = state else { return }
        lastIntent  = intent
        intentCount += 1
        intentTypeCounts[intent.displayName, default: 0] += 1
    }

    /// Record that a GameCommand was successfully mapped and sent to the band.
    /// No-op when not active. Call this after BandBLEManager.send(command:).
    func recordMappedCommand(_ command: GameCommand) {
        guard case .active = state else { return }
        lastMappedCommand = command
        commandCount     += 1
        commandTypeCounts[command.displayName, default: 0] += 1
    }

    // MARK: - Lifecycle event recording
    // These must be called from ContentView.setupLayers() BEFORE the paired
    // pause() / state transition so the count is always included in the report.

    /// Increment the tracking-loss counter. Call immediately before pause(.trackingLost).
    func recordTrackingLost() {
        guard case .active = state else { return }
        trackingLostCount += 1
    }

    /// Increment the safety-zone violation counter. Call immediately before pause(.safetyZoneViolation).
    func recordSafetyZoneViolation() {
        guard case .active = state else { return }
        safetyZoneViolationCount += 1
    }

    /// Increment the band-disconnect counter. Called by ContentView when BandBLEManager fires onDisconnect.
    /// Not gated on session state — disconnects are meaningful regardless of whether the session is active.
    func recordBandDisconnect() {
        bandDisconnectCount += 1
    }

    // MARK: - Private counters

    private var intentTypeCounts:       [String: Int] = [:]
    private var commandTypeCounts:      [String: Int] = [:]
    private var trackingLostCount:      Int = 0
    private var safetyZoneViolationCount: Int = 0
    private var bandDisconnectCount:    Int = 0
    private var pauseCount:             Int = 0

    private var sessionStartDate: Date? = nil
    private var durationTimer: Timer?   = nil

    private func resetCounters() {
        intentCount            = 0
        commandCount           = 0
        lastIntent             = .none
        lastMappedCommand      = nil
        sessionDuration        = 0
        intentTypeCounts       = [:]
        commandTypeCounts      = [:]
        trackingLostCount      = 0
        safetyZoneViolationCount = 0
        bandDisconnectCount    = 0
        pauseCount             = 0
    }

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
