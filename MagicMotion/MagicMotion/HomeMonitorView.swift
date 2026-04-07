// HomeMonitorView.swift
// MagicMotion
//
// External display surface for MagicMotion Home controller mode.
// Shown on the HDMI/AirPlay screen via ExternalDisplayManager.
//
// Driven by ControllerSession — not by GameSession.
// Shows controller-relevant state: active game, calibration status,
// live gesture, last command dispatched, and session activity.
//
// Replaces ParentMonitorView (in LegacyDemo/) as the canonical
// external-display surface for the Home architecture.

import SwiftUI

struct HomeMonitorView: View {

    @ObservedObject var controllerSession: ControllerSession
    @ObservedObject var interpreter: MotionInterpreter
    let cameraManager: CameraManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live camera feed — child is always visible to parent on external display.
            CameraPreviewRepresentable(cameraManager: cameraManager)
                .ignoresSafeArea()

            // Skeleton overlay in DEBUG builds.
            #if DEBUG
            DebugOverlayView(
                snapshot: interpreter.debugInfo.isReliable ? nil : nil,
                currentEvent: interpreter.currentEvent,
                confirmedEvent: interpreter.confirmedEvent,
                fps: 0
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            #endif

            // HUD panels pinned to top and bottom.
            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding()
        }
    }

    // MARK: - Top bar: identity, game, gesture

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {

            // Left: app identity + game name + status dots
            VStack(alignment: .leading, spacing: 6) {
                Label("MagicMotion", systemImage: "figure.run")
                    .font(.headline.bold())
                    .foregroundColor(.white)

                if let profile = controllerSession.activeProfile {
                    Text(profile.displayName)
                        .font(.subheadline)
                        .foregroundColor(.yellow)
                    Text(profile.isPersonalized ? "Calibrated ✓" : "Using default calibration")
                        .font(.caption2)
                        .foregroundColor(profile.isPersonalized ? .green : .orange)
                }

                HStack(spacing: 8) {
                    statusDot(active: cameraManager.isRunning,    label: "Camera")
                    statusDot(active: interpreter.isLeanCalibrated, label: "Lean")
                    statusDot(active: controllerSession.state == .active, label: "Active")
                }
            }
            .padding(12)
            .background(.black.opacity(0.75))
            .cornerRadius(12)

            Spacer()

            // Right: current gesture (large) + session state
            VStack(alignment: .trailing, spacing: 6) {
                Text(interpreter.currentEvent.displayName)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(gestureColor(interpreter.currentEvent))
                    .animation(.easeInOut(duration: 0.15), value: interpreter.currentEvent.displayName)

                Text(controllerSession.state.displayLabel)
                    .font(.caption.bold())
                    .foregroundColor(controllerSession.state.displayColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(controllerSession.state.displayColor.opacity(0.2))
                    .cornerRadius(6)
            }
            .padding(12)
            .background(.black.opacity(0.75))
            .cornerRadius(12)
        }
    }

    // MARK: - Bottom bar: session activity metrics

    private var bottomBar: some View {
        HStack(spacing: 12) {
            metricTile(label: "Intents",  value: "\(controllerSession.intentCount)")
            metricTile(label: "Commands", value: "\(controllerSession.commandCount)")
            metricTile(label: "Duration", value: durationText)

            if let cmd = controllerSession.lastMappedCommand {
                Divider()
                    .frame(height: 36)
                    .background(Color.white.opacity(0.2))
                metricTile(label: "Last sent", value: cmd.displayName)
                    .foregroundColor(.green)
            }

            Spacer()

            // Tracking confidence pill
            HStack(spacing: 4) {
                Circle()
                    .fill(interpreter.debugInfo.isReliable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(interpreter.debugInfo.isReliable
                     ? String(format: "conf %.0f%%", interpreter.debugInfo.confidence * 100)
                     : "Tracking lost")
                    .font(.caption.bold())
                    .foregroundColor(interpreter.debugInfo.isReliable ? .green : .red)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6))
            .cornerRadius(8)
        }
        .padding(12)
        .background(.black.opacity(0.75))
        .cornerRadius(12)
    }

    // MARK: - Helper views

    private func statusDot(active: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? Color.green : Color.red)
                .frame(width: 7, height: 7)
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

    // MARK: - Computed helpers

    // State label/color come from ControllerSessionState.displayLabel / .displayColor extension.

    private var durationText: String {
        let total = Int(controllerSession.sessionDuration)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private func gestureColor(_ event: MotionEvent) -> Color {
        switch event {
        case .leanLeft, .leanRight: return .cyan
        case .jump, .handsUp:       return .yellow
        case .squat, .handsDown:    return .orange
        case .freeze:               return .purple
        case .none:                 return .white.opacity(0.3)
        }
    }
}
