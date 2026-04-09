// MetricCardState.swift
// MagicMotion
//
// Typed state for each metric card on the report dashboard.
//
// Every metric is in exactly one state at any time:
//   .value           — real data, show the number
//   .moreSessionsNeeded — not enough history to be meaningful
//   .enhancedTrackingComingSoon — requires telemetry that doesn't exist yet
//   .researchPreview — computable but requires interpretive caution
//   .unavailable     — permanently blocked by a specific missing signal
//
// The UI consumes MetricCardState directly — it never reads raw numbers
// and then decides what to show. All truth about availability lives here.

import Foundation
import SwiftUI

// MARK: - MetricValue

/// A typed, renderable metric value.
enum MetricValue {
    /// A whole-number count (e.g. gesture count, streak days).
    case integer(Int)
    /// A decimal number (e.g. average confidence, success rate as 0–1).
    case decimal(Double, fractionDigits: Int)
    /// A time interval rendered as "Xm Ys" or "Ys".
    case duration(TimeInterval)
    /// A proportion rendered as "XX%" (input is 0.0–1.0).
    case percentage(Double)
}

extension MetricValue {
    var displayString: String {
        switch self {
        case .integer(let v):
            return "\(v)"
        case .decimal(let v, let d):
            return String(format: "%.\(d)f", v)
        case .duration(let t):
            let total = Int(t)
            let m = total / 60
            let s = total % 60
            return m > 0 ? "\(m)m \(s)s" : "\(s)s"
        case .percentage(let v):
            return "\(Int((v * 100).rounded()))%"
        }
    }
}

// MARK: - MetricCardState

enum MetricCardState {
    /// A real, captured, computed value. Show it.
    case value(MetricValue)

    /// Not enough sessions have been completed to compute a meaningful result.
    /// The associated `minimum` is the session count threshold before this unblocks.
    case moreSessionsNeeded(minimum: Int)

    /// The metric requires hardware or pipeline telemetry that doesn't yet exist.
    /// Examples: per-attempt hesitation timing, retry/abandon stream, M5 IMU.
    case enhancedTrackingComingSoon

    /// Computable from current data but the interpretation requires caution
    /// (e.g. a proxy metric, or one that is sensitive to short session counts).
    /// The associated value is shown with a disclaimer badge.
    case researchPreview(MetricValue)

    /// Permanently blocked by a named missing signal — not expected to unblock
    /// without a new data source (hardware, firmware change, or external API).
    case unavailable(reason: String)
}

// MARK: - Display helpers

extension MetricCardState {
    /// Primary display string. Shown in the large number slot of a card.
    var primaryText: String {
        switch self {
        case .value(let v):                   return v.displayString
        case .moreSessionsNeeded(let min):    return "–"
        case .enhancedTrackingComingSoon:     return "–"
        case .researchPreview(let v):         return v.displayString
        case .unavailable:                    return "–"
        }
    }

    /// Short secondary label explaining the state to the user.
    var subtitleText: String {
        switch self {
        case .value:                          return ""
        case .moreSessionsNeeded(let min):    return "Play \(min) session\(min == 1 ? "" : "s") to unlock"
        case .enhancedTrackingComingSoon:     return "Enhanced tracking coming soon"
        case .researchPreview:               return "Preview – limited data"
        case .unavailable(let reason):        return reason
        }
    }

    /// Accent color for the card. Green = real data; orange = needs more; gray = blocked.
    var accentColor: Color {
        switch self {
        case .value:                          return .green
        case .researchPreview:               return .yellow
        case .moreSessionsNeeded:            return .orange
        case .enhancedTrackingComingSoon:     return .blue.opacity(0.8)
        case .unavailable:                   return .gray
        }
    }

    /// SF Symbol for the card state badge. Nil when no badge is needed.
    var badgeSymbol: String? {
        switch self {
        case .value:                          return nil
        case .moreSessionsNeeded:            return "lock.fill"
        case .enhancedTrackingComingSoon:     return "sparkles"
        case .researchPreview:               return "exclamationmark.triangle"
        case .unavailable:                   return "xmark.circle"
        }
    }
}

// MARK: - MetricDescriptor

/// Metadata about a named metric. Used to populate card headers regardless of availability.
struct MetricDescriptor {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String

    // MARK: - All initial targets

    static let sessionDuration   = MetricDescriptor(id: "sessionDuration",   title: "Last Session",          subtitle: "Active play time",              symbolName: "clock")
    static let weeklyStreak      = MetricDescriptor(id: "weeklyStreak",       title: "Streak",                subtitle: "Consecutive days played",       symbolName: "flame.fill")
    static let activeMinutes     = MetricDescriptor(id: "activeMinutes",      title: "Active Minutes",        subtitle: "All-time total (proxy)",        symbolName: "figure.run")
    static let grossMotorCount   = MetricDescriptor(id: "grossMotorCount",    title: "Body Actions",          subtitle: "Commands sent to controller",   symbolName: "bolt.fill")
    static let handUsageCount    = MetricDescriptor(id: "handUsageCount",     title: "Hand Gestures",         subtitle: "Confirmed swipe intents",       symbolName: "hand.raised.fill")
    static let gestureSuccessRate = MetricDescriptor(id: "gestureSuccessRate", title: "Success Rate",         subtitle: "Commands / gestures attempted", symbolName: "checkmark.circle.fill")
    static let hesitationScore   = MetricDescriptor(id: "hesitationScore",    title: "Hesitation",           subtitle: "Time from attempt to confirm",  symbolName: "timer")
    static let persistenceScore  = MetricDescriptor(id: "persistenceScore",   title: "Persistence",          subtitle: "Retry rate after failure",      symbolName: "arrow.uturn.right.circle")
}
