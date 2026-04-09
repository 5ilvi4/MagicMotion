// ReportDashboard.swift
// MagicMotion
//
// Observable state model for the reports dashboard.
// Reads from SessionReportStore and produces ready-to-display MetricCardState values
// for each of the 8 initial target metrics.
//
// Metric grounding (what's real vs blocked):
//
//   sessionDuration      A — computableNow   last session's duration from SessionReport.duration
//   weeklyStreak         A — computableNow   streak via SessionAggregator.streakDays
//   activeMinutes        A — computableNow   proxy: sum of session durations / 60
//                                            (not the same as precise body-movement minutes,
//                                             which would require per-frame amplitude — B)
//   grossMotorCount      A — computableNow   SessionReport.commandCount + commandCounts
//   handUsageCount       A — computableNow   intentCounts[handSwipeLeft/Right]
//   gestureSuccessRate   A/C — computableNow if ≥ 3 sessions; moreSessionsNeeded below that
//   hesitationScore      B — blockedByMissingTelemetry (no per-attempt timestamp stream)
//   persistenceScore     B — blockedByMissingTelemetry (no retry/abandon event stream)
//
// This class does not perform I/O. Call refresh(from:) whenever the report list changes.

import Combine
import Foundation

@MainActor
final class ReportDashboard: ObservableObject {

    // MARK: - Published metric states

    @Published private(set) var sessionDuration:    MetricCardState = .moreSessionsNeeded(minimum: 1)
    @Published private(set) var weeklyStreak:        MetricCardState = .moreSessionsNeeded(minimum: 1)
    @Published private(set) var activeMinutes:       MetricCardState = .moreSessionsNeeded(minimum: 1)
    @Published private(set) var grossMotorCount:     MetricCardState = .moreSessionsNeeded(minimum: 1)
    @Published private(set) var handUsageCount:      MetricCardState = .moreSessionsNeeded(minimum: 1)
    @Published private(set) var gestureSuccessRate:  MetricCardState = .moreSessionsNeeded(minimum: 3)

    /// B — blocked. Requires per-attempt onset timestamps not currently captured.
    @Published private(set) var hesitationScore: MetricCardState =
        .enhancedTrackingComingSoon

    /// B — blocked. Requires a retry/abandon event stream not currently instrumented.
    @Published private(set) var persistenceScore: MetricCardState =
        .enhancedTrackingComingSoon

    // MARK: - Refresh

    /// Recompute all metric states from the current report list.
    /// Call whenever SessionReportStore.reports changes (e.g. from onReceive in ReportsView).
    func refresh(from reports: [SessionReport]) {
        guard !reports.isEmpty else {
            applyEmpty()
            return
        }

        // -- Session duration (most recent session) --
        if let last = reports.first {
            sessionDuration = .value(.duration(last.duration))
        }

        // -- Weekly streak --
        let streak = SessionAggregator.streakDays(from: reports)
        weeklyStreak = streak > 0
            ? .value(.integer(streak))
            : .moreSessionsNeeded(minimum: 1)

        // -- Active minutes (proxy: sum of session durations) --
        let totalMin = SessionAggregator.totalActiveMinutes(from: reports)
        activeMinutes = .value(.decimal(totalMin, fractionDigits: 1))

        // -- Gross motor action count --
        let gmc = reports.reduce(0) { $0 + $1.commandCount }
        grossMotorCount = .value(.integer(gmc))

        // -- Hand usage count --
        let huc = SessionAggregator.handUsageCount(from: reports)
        // If the current game profile doesn't map hand gestures, zero is real.
        handUsageCount = .value(.integer(huc))

        // -- Gesture success rate (needs ≥ 3 sessions for a stable average) --
        if reports.count < 3 {
            gestureSuccessRate = .moreSessionsNeeded(minimum: 3)
        } else if let rate = SessionAggregator.overallGestureSuccessRate(from: reports) {
            // Surface as researchPreview: the metric is a simple count ratio,
            // not a validated gesture-quality score.
            gestureSuccessRate = .researchPreview(.percentage(rate))
        } else {
            gestureSuccessRate = .unavailable(reason: "No intent data in recorded sessions.")
        }

        // -- Hesitation + Persistence always blocked --
        hesitationScore  = .enhancedTrackingComingSoon
        persistenceScore = .enhancedTrackingComingSoon
    }

    // MARK: - Helpers

    private func applyEmpty() {
        sessionDuration   = .moreSessionsNeeded(minimum: 1)
        weeklyStreak      = .moreSessionsNeeded(minimum: 1)
        activeMinutes     = .moreSessionsNeeded(minimum: 1)
        grossMotorCount   = .moreSessionsNeeded(minimum: 1)
        handUsageCount    = .moreSessionsNeeded(minimum: 1)
        gestureSuccessRate = .moreSessionsNeeded(minimum: 3)
        hesitationScore   = .enhancedTrackingComingSoon
        persistenceScore  = .enhancedTrackingComingSoon
    }
}
