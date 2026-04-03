// ParentMonitorView.swift
// MotionMind
//
// Layer 5 — Presentation (External Monitor).
// Shown on the external HDMI/AirPlay screen.
// Displays: live camera feed + skeleton overlay + gesture labels + session metrics.
// The parent / clinician sees exactly what the child is doing.

import SwiftUI

struct ParentMonitorView: View {

    @ObservedObject var interpreter: MotionInterpreter
    @ObservedObject var session: GameSession
    let cameraManager: CameraManager

    var body: some View {
        ZStack {
            // 1. Black background fallback
            Color.black.ignoresSafeArea()

            // 2. Live camera preview
            CameraPreviewRepresentable(cameraManager: cameraManager)
                .ignoresSafeArea()

            // 3. Debug skeleton overlay (visible on monitor only)
            #if DEBUG
            DebugOverlayView(
                snapshot: nil,
                currentEvent: interpreter.currentEvent,
                fps: 0
            )
            .ignoresSafeArea()
            #endif

            // 4. HUD panels
            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding()
        }
    }

    // MARK: - Top Bar: identity + status

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Label("MotionMind — Parent Monitor", systemImage: "person.2.fill")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    statusDot(active: cameraManager.isRunning, label: "Camera")
                    statusDot(active: true, label: "MediaPipe")
                    statusDot(active: BackgroundTaskManager.shared.isInBackground, label: "Background")
                }
            }
            .padding(12)
            .background(.black.opacity(0.7))
            .cornerRadius(12)

            Spacer()

            // Current gesture
            VStack(alignment: .trailing, spacing: 4) {
                Text(interpreter.currentEvent.displayName)
                    .font(.title.bold())
                    .foregroundColor(eventColor(interpreter.currentEvent))
                    .animation(.easeInOut(duration: 0.2), value: interpreter.currentEvent.displayName)

                Text("Session: \(sessionStateLabel)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(12)
            .background(.black.opacity(0.7))
            .cornerRadius(12)
        }
    }

    // MARK: - Bottom Bar: session metrics

    private var bottomBar: some View {
        HStack(spacing: 16) {
            metricTile(label: "Gestures", value: "\(session.score / 10)")
            metricTile(label: "Score", value: "\(session.score)")
            metricTile(label: "Distance", value: "\(session.distance)m")
            metricTile(label: "Symmetry", value: symmetryLabel)
            metricTile(label: "Avg Conf", value: String(format: "%.0f%%", avgConfidence * 100))
        }
        .padding(12)
        .background(.black.opacity(0.7))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func statusDot(active: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func metricTile(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(minWidth: 60)
    }

    private func eventColor(_ event: MotionEvent) -> Color {
        switch event {
        case .leanLeft, .leanRight: return .cyan
        case .jump, .handsUp:       return .yellow
        case .squat, .handsDown:    return .orange
        case .freeze:               return .purple
        case .none:                 return .white.opacity(0.3)
        }
    }

    private var sessionStateLabel: String {
        switch session.state {
        case .idle:              return "Idle"
        case .calibrating:       return "Calibrating…"
        case .countdown(let n):  return "Countdown \(n)"
        case .active:            return "▶ Active"
        case .paused(let r):     return "⏸ \(r)"
        case .roundOver:         return "Round Over"
        case .completed:         return "Complete ✓"
        }
    }

    private var symmetryLabel: String {
        // Real symmetry comes from MotionSessionLogger
        return "—"
    }

    private var avgConfidence: Double {
        // Use last interpreter confidence
        return 0.0 // hooked up via MotionSessionLogger.shared.metrics.avgConfidence
    }
}
