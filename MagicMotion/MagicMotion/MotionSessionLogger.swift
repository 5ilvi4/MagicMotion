// MotionSessionLogger.swift
// MotionMind
//
// Persists gesture events, confidence scores, and session metrics to disk.
// Survives app crashes and game switches. Exports JSON for backend upload.

import Foundation
import UIKit

// MARK: - Data Models

struct GestureEntry: Codable {
    let timestamp: TimeInterval
    let event: String
    let confidence: Double
    let hipX: Double
    let hipY: Double
}

struct SessionMetrics: Codable {
    var totalGestures: Int = 0
    var avgConfidence: Double = 0
    var leftGestures: Int = 0
    var rightGestures: Int = 0
    var jumpGestures: Int = 0
    var squatGestures: Int = 0
    var handsUpGestures: Int = 0
    var symmetryScore: Double = 0   // |left - right| / total, lower = more symmetric
    var sessionDuration: TimeInterval = 0
    var startTime: TimeInterval = Date().timeIntervalSince1970
}

struct SessionExport: Codable {
    let sessionID: String
    let deviceID: String
    let exportedAt: TimeInterval
    var metrics: SessionMetrics
    var entries: [GestureEntry]
}

// MARK: - Logger

class MotionSessionLogger {

    // MARK: - Singleton

    static let shared = MotionSessionLogger()
    private init() {
        sessionID = UUID().uuidString
        startTime = Date()
        load()
    }

    // MARK: - State

    private(set) var sessionID: String
    private var startTime: Date
    private var entries: [GestureEntry] = []
    private var metrics = SessionMetrics()
    private let flushThreshold = 100    // Write to disk every 100 entries
    private let maxEntries = 1000       // Drop oldest to prevent overflow

    private let queue = DispatchQueue(label: "motionmind.logger", qos: .background)

    // MARK: - Public API

    /// Log a detected motion event.
    func log(event: MotionEvent, snapshot: PoseSnapshot) {
        queue.async { [weak self] in
            guard let self else { return }

            let entry = GestureEntry(
                timestamp: Date().timeIntervalSince1970,
                event: event.displayName,
                confidence: Double(snapshot.trackingConfidence),
                hipX: Double(snapshot.hipCenter?.x ?? 0),
                hipY: Double(snapshot.hipCenter?.y ?? 0)
            )

            // Guard against buffer overflow — drop oldest
            if self.entries.count >= self.maxEntries {
                self.entries.removeFirst(100)
                print("⚠️ MotionSessionLogger: buffer trimmed (was at max \(self.maxEntries))")
            }

            self.entries.append(entry)
            self.updateMetrics(for: event, confidence: snapshot.trackingConfidence)

            // Flush to disk every N entries
            if self.entries.count % self.flushThreshold == 0 {
                self.writeToDisk()
            }
        }
    }

    /// Periodic heartbeat to mark that processing is still active.
    func logHeartbeat() {
        queue.async { [weak self] in
            self?.metrics.sessionDuration = Date().timeIntervalSince(self?.startTime ?? Date())
        }
    }

    /// Force write everything to disk (call on app terminate or background).
    func flush() {
        queue.sync { writeToDisk() }
        print("📦 MotionSessionLogger: flushed \(entries.count) entries to disk")
    }

    /// Export the full session as a JSON string (for backend upload).
    func exportJSON() -> String? {
        let export = SessionExport(
            sessionID: sessionID,
            deviceID: UIDeviceID(),
            exportedAt: Date().timeIntervalSince1970,
            metrics: metrics,
            entries: entries
        )
        guard let data = try? JSONEncoder().encode(export),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    /// Reset the session (new game round).
    func reset() {
        queue.async { [weak self] in
            self?.entries = []
            self?.metrics = SessionMetrics()
            self?.startTime = Date()
            self?.sessionID = UUID().uuidString
        }
    }

    // MARK: - Private

    private func updateMetrics(for event: MotionEvent, confidence: Float) {
        metrics.totalGestures += 1

        // Rolling average confidence
        let n = Double(metrics.totalGestures)
        metrics.avgConfidence = (metrics.avgConfidence * (n - 1) + Double(confidence)) / n

        switch event {
        case .leanLeft:   metrics.leftGestures += 1
        case .leanRight:  metrics.rightGestures += 1
        case .jump:       metrics.jumpGestures += 1
        case .squat:      metrics.squatGestures += 1
        case .handsUp:    metrics.handsUpGestures += 1
        default: break
        }

        // Symmetry: 0 = perfect, 1 = completely one-sided
        let total = metrics.leftGestures + metrics.rightGestures
        if total > 0 {
            metrics.symmetryScore = abs(Double(metrics.leftGestures - metrics.rightGestures)) / Double(total)
        }

        metrics.sessionDuration = Date().timeIntervalSince(startTime)
    }

    // MARK: - Disk Persistence

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("motionmind_session_\(sessionID).json")
    }

    private func writeToDisk() {
        let export = SessionExport(
            sessionID: sessionID,
            deviceID: UIDeviceID(),
            exportedAt: Date().timeIntervalSince1970,
            metrics: metrics,
            entries: entries
        )
        do {
            let data = try JSONEncoder().encode(export)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ MotionSessionLogger: write failed — \(error)")
        }
    }

    private func load() {
        // Recover any existing session file on launch (crash recovery)
        guard let data = try? Data(contentsOf: fileURL),
              let export = try? JSONDecoder().decode(SessionExport.self, from: data) else { return }
        entries = export.entries
        metrics = export.metrics
        print("📦 MotionSessionLogger: recovered \(entries.count) entries from disk")
    }

    private func UIDeviceID() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}
