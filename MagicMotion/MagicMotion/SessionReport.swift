// SessionReport.swift
// MagicMotion
//
// Immutable record of one completed controller session.
// Produced by ControllerSession.end() and persisted by SessionReportStore.
//
// Uses plain strings for game name and last command so this struct stays
// decoupled from GameProfile and GameCommand model types — persisted reports
// remain readable even if the profile model changes.

import Foundation

struct SessionReport: Codable, Identifiable {
    let id: UUID

    /// Wall-clock time the session was activated (not when it ended).
    let date: Date

    /// GameProfile.displayName at the time of play.
    let gameName: String

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
}
