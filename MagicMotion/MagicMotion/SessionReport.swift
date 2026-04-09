// SessionReport.swift
// MagicMotion
//
// Immutable record of one completed controller session.
// Produced by ControllerSession.end() and persisted by SessionReportStore.
//
// Uses plain strings for game name and command labels so this struct stays
// decoupled from GameProfile / GameCommand model types — persisted reports
// remain readable even if the profile model changes.
//
// Schema versioning: new fields use decodeIfPresent with sensible defaults
// so existing persisted reports decode cleanly after an app update.

import Foundation

struct SessionReport: Codable, Identifiable {
    let id: UUID

    /// Wall-clock time the session was activated (not when it ended).
    let date: Date

    /// GameProfile.displayName at the time of play.
    let gameName: String

    /// GameID.rawValue at the time of play. Nil for legacy reports saved before this field existed.
    let gameID: String?

    /// Total active play time in seconds (pauses excluded).
    let duration: TimeInterval

    /// Total AppIntents resolved by InputCoordinator during the session.
    let intentCount: Int

    /// Total GameCommands successfully sent to the band during the session.
    let commandCount: Int

    /// GameCommand.displayName of the last command dispatched, or nil if none were sent.
    let lastCommand: String?

    /// True when the child's body calibration was personalized (not default values).
    let wasPersonalized: Bool

    // MARK: - Per-type breakdowns (key = AppIntent.displayName or GameCommand.displayName)

    /// Resolved intent counts by type. Keys are AppIntent.displayName strings.
    /// Empty dictionary for legacy reports.
    let intentCounts: [String: Int]

    /// Sent command counts by type. Keys are GameCommand.displayName strings.
    /// Empty dictionary for legacy reports.
    let commandCounts: [String: Int]

    // MARK: - Lifecycle event counts

    /// Number of tracking-loss events that occurred while the session was active.
    let trackingLostCount: Int

    /// Number of safety-zone violations that occurred while the session was active.
    let safetyZoneViolationCount: Int

    /// Number of band (M5Gamepad) disconnects observed during the session lifetime.
    let bandDisconnectCount: Int

    /// Number of times the session was paused for any reason.
    let pauseCount: Int

    // MARK: - Memberwise init

    init(
        id: UUID,
        date: Date,
        gameName: String,
        gameID: String? = nil,
        duration: TimeInterval,
        intentCount: Int,
        commandCount: Int,
        lastCommand: String?,
        wasPersonalized: Bool,
        intentCounts: [String: Int] = [:],
        commandCounts: [String: Int] = [:],
        trackingLostCount: Int = 0,
        safetyZoneViolationCount: Int = 0,
        bandDisconnectCount: Int = 0,
        pauseCount: Int = 0
    ) {
        self.id                      = id
        self.date                    = date
        self.gameName                = gameName
        self.gameID                  = gameID
        self.duration                = duration
        self.intentCount             = intentCount
        self.commandCount            = commandCount
        self.lastCommand             = lastCommand
        self.wasPersonalized         = wasPersonalized
        self.intentCounts            = intentCounts
        self.commandCounts           = commandCounts
        self.trackingLostCount       = trackingLostCount
        self.safetyZoneViolationCount = safetyZoneViolationCount
        self.bandDisconnectCount     = bandDisconnectCount
        self.pauseCount              = pauseCount
    }

    // MARK: - Codable (backward-compatible)

    enum CodingKeys: String, CodingKey {
        case id, date, gameName, gameID, duration
        case intentCount, commandCount, lastCommand, wasPersonalized
        case intentCounts, commandCounts
        case trackingLostCount, safetyZoneViolationCount, bandDisconnectCount, pauseCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,         forKey: .id)
        date         = try c.decode(Date.self,         forKey: .date)
        gameName     = try c.decode(String.self,       forKey: .gameName)
        gameID       = try c.decodeIfPresent(String.self, forKey: .gameID)
        duration     = try c.decode(TimeInterval.self, forKey: .duration)
        intentCount  = try c.decode(Int.self,          forKey: .intentCount)
        commandCount = try c.decode(Int.self,          forKey: .commandCount)
        lastCommand  = try c.decodeIfPresent(String.self, forKey: .lastCommand)
        wasPersonalized = try c.decode(Bool.self,      forKey: .wasPersonalized)
        intentCounts             = try c.decodeIfPresent([String: Int].self, forKey: .intentCounts)             ?? [:]
        commandCounts            = try c.decodeIfPresent([String: Int].self, forKey: .commandCounts)            ?? [:]
        trackingLostCount        = try c.decodeIfPresent(Int.self, forKey: .trackingLostCount)        ?? 0
        safetyZoneViolationCount = try c.decodeIfPresent(Int.self, forKey: .safetyZoneViolationCount) ?? 0
        bandDisconnectCount      = try c.decodeIfPresent(Int.self, forKey: .bandDisconnectCount)      ?? 0
        pauseCount               = try c.decodeIfPresent(Int.self, forKey: .pauseCount)               ?? 0
    }
}

// MARK: - Computed display helpers

extension SessionReport {
    var formattedDuration: String {
        let total = Int(duration)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m) min \(s) sec" : "\(s) sec"
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// Approximate gesture success rate: commands sent / intents resolved.
    /// Returns nil when no intents were recorded.
    var gestureSuccessRate: Double? {
        guard intentCount > 0 else { return nil }
        return Double(commandCount) / Double(intentCount)
    }

    /// Validity flag strings included in the session summary.
    var validityFlags: [String] {
        var flags: [String] = []
        if duration < 30          { flags.append("shortSession") }
        if !wasPersonalized       { flags.append("uncalibrated") }
        if trackingLostCount > 3  { flags.append("frequentTrackingLoss") }
        if commandCount == 0      { flags.append("noCommandsSent") }
        return flags
    }
}
