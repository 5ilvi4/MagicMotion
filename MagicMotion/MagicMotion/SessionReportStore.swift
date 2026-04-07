// SessionReportStore.swift
// MagicMotion
//
// Lightweight local persistence for SessionReports.
// Stores up to `maxReports` reports as a JSON array in UserDefaults.
// Most-recent-first ordering is maintained at write time.
//
// Owned as @StateObject in ContentView so ReportsView can observe it.
// ControllerSession writes via the onSessionEnded callback — it does not
// hold a reference to this store directly.

import Foundation
import Combine

final class SessionReportStore: ObservableObject {

    // MARK: - Published

    @Published private(set) var reports: [SessionReport] = []

    // MARK: - Configuration

    private let maxReports = 50
    private static let defaultsKey = "com.magicmotion.sessionReports"

    // MARK: - Init

    init() {
        reports = loadFromDefaults()
    }

    // MARK: - Write

    /// Prepend a new report and persist the updated list.
    /// Automatically trims to maxReports.
    func save(_ report: SessionReport) {
        var updated = [report] + reports
        if updated.count > maxReports {
            updated = Array(updated.prefix(maxReports))
        }
        reports = updated
        persist(updated)
        print("📊 [SessionReportStore] Saved report — game: \(report.gameName) duration: \(report.formattedDuration) commands: \(report.commandCount)")
    }

    /// Delete all persisted reports.
    func clearAll() {
        reports = []
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        print("📊 [SessionReportStore] Cleared all reports")
    }

    // MARK: - Private

    private func loadFromDefaults() -> [SessionReport] {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else { return [] }
        do {
            return try JSONDecoder().decode([SessionReport].self, from: data)
        } catch {
            print("📊 [SessionReportStore] Failed to decode reports: \(error.localizedDescription)")
            return []
        }
    }

    private func persist(_ reports: [SessionReport]) {
        do {
            let data = try JSONEncoder().encode(reports)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        } catch {
            print("📊 [SessionReportStore] Failed to persist reports: \(error.localizedDescription)")
        }
    }
}
