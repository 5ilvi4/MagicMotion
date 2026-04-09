// SessionAggregator.swift
// MagicMotion
//
// Pure calculation layer. Consumes [SessionReport] and produces rollups and
// metric values. No I/O, no side effects, no dependencies on ObservableObject.
//
// Signal availability classification for the 8 initial target metrics:
//
//   A. computableNow (backed by real captured signals)
//      - Session duration             → SessionReport.duration (pauses excluded)
//      - Gross motor action count     → SessionReport.commandCount / commandCounts
//      - Hand usage count             → SessionReport.intentCounts[handSwipeLeft/Right]
//      - Gesture success rate         → commandCount / intentCount (proxy: commands/intents)
//      - Weekly streak / consistency  → per-day session presence from report dates
//
//   B. blockedByMissingTelemetry (signal does not exist in current pipeline)
//      - Full-body active minutes (precise)
//          Proxy: session duration is usable, but true "body moving" time requires
//          continuous per-frame movement amplitude — not currently aggregated.
//          Classified computableNow via duration proxy; note in card state.
//      - Hesitation score
//          Requires per-attempt timing: time from first pending frame to confirmation.
//          MotionInterpreter tracks pendingCount but does not expose attempt timestamps.
//          Not surfaced in SessionReport.
//      - Persistence score
//          Requires retry/abandon events — a player attempting a gesture, failing, and
//          retrying. No such event stream exists in the current code path.
//
//   C. needsMoreSessions
//      - Gesture success rate needs ≥ 3 sessions to be meaningful.
//      - Weekly streak needs ≥ 2 distinct calendar days.
//
//   D. researchOnly / unavailable
//      - Heart rate, M5 IMU, M5 battery, microphone amplitude, sync events —
//        none of these signals exist anywhere in the current iOS or firmware code.
//
// Missing telemetry registry (signals that do NOT exist and are needed for blocked metrics):
//   - Per-attempt timestamps (gesture onset → confirmation gap) → hesitation score
//   - Retry/abandon event stream → persistence score
//   - Continuous frame-level movement amplitude → precise active-minutes
//   - M5 battery level notification → device health
//   - M5 IMU stream → raw motion data
//   - Microphone amplitude → environmental signal
//   - Heart rate → physiological workload (external HRM required)

import Foundation

// MARK: - DailyRollup

/// Summary of all sessions on a single calendar day.
struct DailyRollup: Codable {
    let date: Date               // normalized to start of day (midnight local time)
    let sessionCount: Int
    let totalDuration: TimeInterval
    let totalIntentCount: Int
    let totalCommandCount: Int
    let gamesPlayed: [String]    // GameID.rawValue strings, deduplicated, sorted
    let wasAnySessionPersonalized: Bool
}

extension DailyRollup {
    /// Total active play time in minutes.
    var activeMinutes: Double { totalDuration / 60.0 }

    /// Fraction of intents that produced a sent command. Nil when no intents recorded.
    var gestureSuccessRate: Double? {
        guard totalIntentCount > 0 else { return nil }
        return Double(totalCommandCount) / Double(totalIntentCount)
    }
}

// MARK: - WeeklyRollup

/// Summary of sessions across a 7-day window starting on weekStartDate.
struct WeeklyRollup: Codable {
    let weekStartDate: Date
    let activeDays: Int            // count of days with at least one session
    let totalDuration: TimeInterval
    let totalIntentCount: Int
    let totalCommandCount: Int
    let sessionCountPerDay: [Int]  // 7 elements — index 0 = weekStartDate
}

extension WeeklyRollup {
    var activeMinutes: Double { totalDuration / 60.0 }

    var gestureSuccessRate: Double? {
        guard totalIntentCount > 0 else { return nil }
        return Double(totalCommandCount) / Double(totalIntentCount)
    }
}

// MARK: - SessionAggregator

enum SessionAggregator {

    // MARK: - Daily rollup

    static func dailyRollup(from sessions: [SessionReport], for date: Date) -> DailyRollup {
        let cal = Calendar.current
        let daySessions = sessions.filter { cal.isDate($0.date, inSameDayAs: date) }
        let games = Array(Set(daySessions.compactMap { $0.gameID })).sorted()
        return DailyRollup(
            date:                        cal.startOfDay(for: date),
            sessionCount:                daySessions.count,
            totalDuration:               daySessions.reduce(0) { $0 + $1.duration },
            totalIntentCount:            daySessions.reduce(0) { $0 + $1.intentCount },
            totalCommandCount:           daySessions.reduce(0) { $0 + $1.commandCount },
            gamesPlayed:                 games,
            wasAnySessionPersonalized:   daySessions.contains { $0.wasPersonalized }
        )
    }

    // MARK: - Weekly rollup

    static func weeklyRollup(from sessions: [SessionReport], weekStarting start: Date) -> WeeklyRollup {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: start)
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: dayStart) else {
            return WeeklyRollup(weekStartDate: dayStart, activeDays: 0, totalDuration: 0,
                                totalIntentCount: 0, totalCommandCount: 0,
                                sessionCountPerDay: Array(repeating: 0, count: 7))
        }
        let weekSessions = sessions.filter { $0.date >= dayStart && $0.date < weekEnd }
        var perDay = Array(repeating: 0, count: 7)
        var activeDaySet = Set<Int>()
        for session in weekSessions {
            let offset = cal.dateComponents([.day], from: dayStart, to: session.date).day ?? 0
            if offset >= 0 && offset < 7 {
                perDay[offset] += 1
                activeDaySet.insert(offset)
            }
        }
        return WeeklyRollup(
            weekStartDate:      dayStart,
            activeDays:         activeDaySet.count,
            totalDuration:      weekSessions.reduce(0) { $0 + $1.duration },
            totalIntentCount:   weekSessions.reduce(0) { $0 + $1.intentCount },
            totalCommandCount:  weekSessions.reduce(0) { $0 + $1.commandCount },
            sessionCountPerDay: perDay
        )
    }

    // MARK: - Streak

    /// Consecutive calendar days with at least one session, ending today or yesterday.
    /// If the player has already played today, the streak includes today.
    /// If not, looks back from yesterday so the streak isn't broken by the current day.
    static func streakDays(from sessions: [SessionReport], relativeTo now: Date = Date()) -> Int {
        guard !sessions.isEmpty else { return 0 }
        let cal = Calendar.current
        let activeDays = Set(sessions.map { cal.startOfDay(for: $0.date) })

        let today = cal.startOfDay(for: now)
        var streak = 0
        var cursor = today

        // Count consecutive days going back from today.
        while activeDays.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }

        // If today has no session yet, retry starting from yesterday.
        if streak == 0 {
            cursor = cal.date(byAdding: .day, value: -1, to: today)!
            while activeDays.contains(cursor) {
                streak += 1
                cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
            }
        }
        return streak
    }

    // MARK: - Metric computations

    /// Total active play time across all sessions, in minutes.
    static func totalActiveMinutes(from sessions: [SessionReport]) -> Double {
        sessions.reduce(0.0) { $0 + $1.duration } / 60.0
    }

    /// Total commands sent, broken down by command type.
    static func grossMotorBreakdown(from sessions: [SessionReport]) -> [String: Int] {
        var merged: [String: Int] = [:]
        for s in sessions {
            for (key, count) in s.commandCounts {
                merged[key, default: 0] += count
            }
        }
        return merged
    }

    /// Total confirmed hand-swipe intents across all sessions.
    static func handUsageCount(from sessions: [SessionReport]) -> Int {
        sessions.reduce(0) { total, s in
            total
                + (s.intentCounts[AppIntent.handSwipeLeft.displayName]  ?? 0)
                + (s.intentCounts[AppIntent.handSwipeRight.displayName] ?? 0)
        }
    }

    /// Overall gesture success rate across all sessions.
    /// Returns nil when no intents have been recorded.
    static func overallGestureSuccessRate(from sessions: [SessionReport]) -> Double? {
        let totalIntents  = sessions.reduce(0) { $0 + $1.intentCount }
        let totalCommands = sessions.reduce(0) { $0 + $1.commandCount }
        guard totalIntents > 0 else { return nil }
        return Double(totalCommands) / Double(totalIntents)
    }
}
