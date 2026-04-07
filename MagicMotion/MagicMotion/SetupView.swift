// SetupView.swift
// MagicMotion
//
// The "Setup" tab. Shows wearable connection status, body calibration status,
// and session readiness before play starts.
//
// This view is read-only except for the Recalibrate action.
// All mutations happen through CalibrationEngine.

import SwiftUI

struct SetupView: View {

    @ObservedObject var band: BandBLEManager
    @ObservedObject var calibrationEngine: CalibrationEngine
    @ObservedObject var controllerSession: ControllerSession
    @ObservedObject var interpreter: MotionInterpreter

    var body: some View {
        NavigationView {
            List {
                wearableSection
                calibrationSection
                readinessSection
            }
            .navigationTitle("Setup")
            .listStyle(.insetGrouped)
        }
        .navigationViewStyle(.stack)

        // Calibration overlay covers the whole screen when active
        .overlay {
            if calibrationEngine.isActive {
                CalibrationOverlayView(phase: calibrationEngine.phase)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Wearable section

    private var wearableSection: some View {
        Section {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(band.isConnected ? .green : .yellow)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(band.isConnected ? "Band connected" : band.statusText)
                        .font(.body)
                    if let last = band.lastSentCommand {
                        Text("Last command: \(last.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Circle()
                    .fill(band.isConnected ? Color.green : Color.yellow)
                    .frame(width: 10, height: 10)
            }
        } header: {
            Label("Wearable", systemImage: "applewatch")
        } footer: {
            Text(band.isConnected
                 ? "Commands will be sent to the band during play."
                 : "Make sure the band is charged and in range.")
                .font(.caption)
        }
    }

    // MARK: - Calibration section

    private var calibrationSection: some View {
        Section {
            // Status row
            HStack {
                Image(systemName: "figure.stand")
                    .foregroundColor(interpreter.isLeanCalibrated ? .green : .orange)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(calibrationStatusTitle)
                        .font(.body)
                    Text(calibrationStatusDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Personalized values (shown when calibrated)
            if let profile = controllerSession.activeProfile, profile.isPersonalized {
                let cal = profile.calibration
                Group {
                    calibrationRow(label: "Shoulder width",
                                   value: String(format: "%.0f%%", cal.shoulderWidth * 100))
                    calibrationRow(label: "Torso length",
                                   value: String(format: "%.0f%%", cal.torsoLength * 100))
                    calibrationRow(label: "Jump range",
                                   value: String(format: "%.0f%%", cal.maxJumpRise * 100))
                    calibrationRow(label: "Squat range",
                                   value: String(format: "%.0f%%", cal.maxCrouchDrop * 100))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Recalibrate button
            Button {
                calibrationEngine.startCalibration()
            } label: {
                Label("Start Body Calibration", systemImage: "arrow.triangle.2.circlepath")
            }
            .foregroundColor(interpreter.isLeanCalibrated ? .accentColor : .orange)
        } header: {
            Label("Body Calibration", systemImage: "person.badge.clock")
        } footer: {
            Text("Calibration personalises gesture thresholds to this child's height and movement range.")
                .font(.caption)
        }
    }

    private var calibrationStatusTitle: String {
        if let profile = controllerSession.activeProfile {
            return profile.isPersonalized ? "Personalized calibration" : "Using default calibration"
        }
        return interpreter.isLeanCalibrated ? "Auto-calibrated (lean)" : "Not calibrated"
    }

    private var calibrationStatusDetail: String {
        if let profile = controllerSession.activeProfile, profile.isPersonalized {
            return "Thresholds are body-relative for this child."
        }
        return "Run calibration for the best gesture accuracy."
    }

    private func calibrationRow(label: String, value: String) -> some View {
        HStack {
            Text(label).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).foregroundColor(.primary)
        }
    }

    // MARK: - Readiness section

    private var readinessSection: some View {
        Section {
            readinessRow(
                icon: "camera.fill",
                label: "Camera",
                met: true   // if we reached SetupView, ContentView already started camera
            )
            readinessRow(
                icon: "antenna.radiowaves.left.and.right",
                label: "Wearable",
                met: band.isConnected
            )
            readinessRow(
                icon: "figure.stand",
                label: "Body calibrated",
                met: interpreter.isLeanCalibrated
            )
            readinessRow(
                icon: "gamecontroller",
                label: "Game selected",
                met: controllerSession.activeProfile != nil
            )
        } header: {
            Label("Readiness", systemImage: "checkmark.shield")
        } footer: {
            if controllerSession.state == .needsCalibration {
                Text("Run body calibration before starting — the Controller tab will unlock once calibration completes.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private func readinessRow(icon: String, label: String, met: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(met ? .green : .secondary)
                .frame(width: 24)
            Text(label)
            Spacer()
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundColor(met ? .green : .secondary)
        }
    }
}
