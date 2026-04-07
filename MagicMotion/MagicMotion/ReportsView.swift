// ReportsView.swift
// MagicMotion
//
// The "Reports" tab. Shows persisted SessionReports from SessionReportStore,
// most recent first. Falls back to an empty state when no sessions exist yet.
//
// Scope: lightweight first pass — the live in-session data from ControllerSession
// is also shown at the top when a session is active or recently ended.

import SwiftUI

struct ReportsView: View {

    @ObservedObject var controllerSession: ControllerSession
    @ObservedObject var reportStore: SessionReportStore

    var body: some View {
        NavigationView {
            Group {
                if reportStore.reports.isEmpty && !hasLiveActivity {
                    emptyState
                } else {
                    reportList
                }
            }
            .navigationTitle("Reports")
            .toolbar {
                if !reportStore.reports.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            reportStore.clearAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Report list

    private var reportList: some View {
        List {
            // Live session card — shown while a session is active or recently ended
            if hasLiveActivity {
                Section {
                    liveSessionCard
                } header: {
                    Label("Current Session", systemImage: "bolt.fill")
                }
            }

            // Persisted sessions
            if !reportStore.reports.isEmpty {
                Section {
                    ForEach(reportStore.reports) { report in
                        reportRow(report)
                    }
                } header: {
                    Label("Past Sessions", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Live session card

    private var liveSessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(controllerSession.state == .active ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(controllerSession.state.displayLabel)
                    .font(.caption.bold())
                    .foregroundColor(controllerSession.state.displayColor)
                Spacer()
                if let profile = controllerSession.activeProfile {
                    Text(profile.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 20) {
                liveStat(label: "Duration",  value: liveDurationText)
                liveStat(label: "Intents",   value: "\(controllerSession.intentCount)")
                liveStat(label: "Commands",  value: "\(controllerSession.commandCount)")
            }

            if let last = controllerSession.lastMappedCommand {
                Text("Last: \(last.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func liveStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Past session row

    private func reportRow(_ report: SessionReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(report.gameName)
                    .font(.headline)
                Spacer()
                Text(report.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                statChip(icon: "clock",
                         value: report.formattedDuration)
                statChip(icon: "bolt",
                         value: "\(report.intentCount) intents")
                statChip(icon: "antenna.radiowaves.left.and.right",
                         value: "\(report.commandCount) sent")
            }

            HStack(spacing: 8) {
                if let last = report.lastCommand {
                    Label(last, systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if report.wasPersonalized {
                    Label("Calibrated", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Label("Default", systemImage: "circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statChip(icon: String, value: String) -> some View {
        Label(value, systemImage: icon)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No sessions yet")
                .font(.title2.bold())
            Text("Play a session using the Controller tab.\nYour activity will appear here when done.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var hasLiveActivity: Bool {
        controllerSession.intentCount > 0 || controllerSession.commandCount > 0
            || controllerSession.state == .active
    }

    private var liveDurationText: String {
        let total = Int(controllerSession.sessionDuration)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
