// ControllerModeView.swift
// MagicMotion
//
// The "Play" tab. The canonical user flow for familiar-game active play:
//
//   1. Select supported game (segmented picker or single-game header)
//   2. See the gesture list for that game (sheet via "Show Controls" button)
//   3. Verify readiness (gating model via ControllerReadiness)
//   4. Start controller mode → ControllerSession.activate() + GameLauncher.launch(game:)
//   5. Pause banner when paused (safety zone / tracking lost / backgrounded)
//   6. Stop cleanly → end() + re-prepare so state returns to .ready
//
// This view is a surface only. All session logic lives in ControllerSession.
// All mapping logic lives in GameProfileManager.

import SwiftUI

struct ControllerModeView: View {

    // MARK: - Dependencies (all observables owned by ContentView)

    @ObservedObject var frameSource: CameraManager
    @ObservedObject var motionEngine: MotionEngine
    @ObservedObject var interpreter: MotionInterpreter
    @ObservedObject var handEngine: HandEngine
    @ObservedObject var handInterpreter: HandGestureInterpreter
    @ObservedObject var coordinator: InputCoordinator
    @ObservedObject var calibrationEngine: CalibrationEngine
    @ObservedObject var controllerSession: ControllerSession
    @ObservedObject var profileManager: GameProfileManager
    @ObservedObject var band: BandBLEManager
    @ObservedObject var gameLauncher: GameLauncher
    @ObservedObject var displayManager: ExternalDisplayManager

    // MARK: - Local state

    @State private var showGestureList = false

    #if DEBUG
    @State private var debugMode = true
    @State private var showLandmarkOverlay = true
    @State private var showHandOverlay = true
    #endif

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live camera feed
            CameraPreviewRepresentable(cameraManager: frameSource)
                .ignoresSafeArea()

            #if DEBUG
            // Skeleton overlay
            if showLandmarkOverlay {
                DebugOverlayView(
                    snapshot: motionEngine.latestSnapshot,
                    currentEvent: interpreter.currentEvent,
                    confirmedEvent: interpreter.confirmedEvent,
                    fps: motionEngine.fps
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Hand overlay
            if showHandOverlay {
                HandOverlayView(hands: handEngine.latestHands)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            #endif

            // Calibration overlay — auto-dismisses on completion / failure
            if calibrationEngine.isActive {
                CalibrationOverlayView(phase: calibrationEngine.phase)
            }

            // Pause banner — full-screen when session is paused
            if case .paused(let reason) = controllerSession.state {
                PauseBannerView(
                    reason: reason,
                    onResume: {
                        controllerSession.resume()
                    },
                    onStop: {
                        stopAndReprepare()
                    }
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: controllerSession.state)
            }

            // HUD layer
            VStack(spacing: 0) {
                #if DEBUG
                if debugMode {
                    HStack(alignment: .top) {
                        gestureDebugOverlay
                            .padding([.top, .leading])
                        Spacer()
                        overlayToggles
                            .padding([.top, .trailing])
                    }
                }
                #endif

                Spacer()

                controlPanel
                    .padding()
                    .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showGestureList) {
            if let profile = profileManager.activeProfile {
                GestureListView(profile: profile)
            }
        }
    }

    // MARK: - Readiness model

    private var readiness: ControllerReadiness {
        ControllerReadiness(
            gameSelected:          profileManager.activeProfile != nil,
            calibrationAvailable:  controllerSession.state != .needsCalibration
                                       && controllerSession.state != .idle,
            cameraActive:          frameSource.isCameraActive,
            wearableConnected:     band.isConnected
        )
    }

    // MARK: - Control panel

    private var controlPanel: some View {
        VStack(spacing: 12) {
            gameHeader
            Divider().background(Color.white.opacity(0.25))
            readinessRow
            Divider().background(Color.white.opacity(0.25))
            primaryActionButton
            secondaryActions
        }
    }

    // MARK: - Game header

    private var gameHeader: some View {
        HStack(spacing: 12) {
            // Game icon
            Image(systemName: "gamecontroller.fill")
                .font(.title3)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(profileManager.activeProfile?.displayName ?? "No game selected")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(controllerSession.state.displayLabel)
                    .font(.caption)
                    .foregroundColor(controllerSession.state.displayColor)
            }

            Spacer()

            // Game picker (segmented when multiple games are available)
            let profiles = profileManager.availableProfiles()
            if profiles.count > 1 {
                Menu {
                    ForEach(profiles, id: \.gameID) { profile in
                        Button(profile.displayName) {
                            profileManager.setActiveGame(profile.gameID)
                        }
                    }
                } label: {
                    Label("Change", systemImage: "chevron.up.chevron.down")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }

            // Show gesture list
            Button {
                showGestureList = true
            } label: {
                Label("Controls", systemImage: "list.bullet.rectangle")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .disabled(profileManager.activeProfile == nil)
        }
    }

    // MARK: - Readiness row

    private var readinessRow: some View {
        HStack(spacing: 16) {
            readinessDot(
                icon: "camera.fill",
                label: "Camera",
                met: readiness.cameraActive
            )
            readinessDot(
                icon: "figure.stand",
                label: "Calibrated",
                met: readiness.calibrationAvailable
            )
            readinessDot(
                icon: "gamecontroller",
                label: "Game",
                met: readiness.gameSelected
            )
            readinessDot(
                icon: "antenna.radiowaves.left.and.right",
                label: band.isConnected ? "Band ✓" : band.statusText,
                met: readiness.wearableConnected,
                isAdvisory: true   // not a hard gate
            )
            Spacer()

            // Live runtime stats when active
            if controllerSession.state == .active {
                HStack(spacing: 14) {
                    liveStat(value: liveDurationText, label: "time")
                    liveStat(value: "\(controllerSession.commandCount)", label: "sent")
                }
            }
        }
    }

    private func readinessDot(icon: String, label: String, met: Bool,
                               isAdvisory: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundColor(met ? .green : (isAdvisory ? .yellow : .red))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func liveStat(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.green)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Primary action button

    private var primaryActionButton: some View {
        Group {
            if gameLauncher.gameRunning {
                // ── Active / game launched: Stop ──────────────────────────────
                Button {
                    stopAndReprepare()
                } label: {
                    Label("Stop — Return to MagicMotion", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .font(.headline)
                }

            } else if readiness.canStart {
                // ── Ready: Start ──────────────────────────────────────────────
                Button {
                    startControllerMode()
                } label: {
                    Label(startButtonLabel, systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .font(.headline)
                }

            } else {
                // ── Not ready: explain what's missing ────────────────────────
                VStack(spacing: 6) {
                    Button { } label: {
                        Label("Start Controller Mode", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.gray.opacity(0.4))
                            .foregroundColor(.white.opacity(0.5))
                            .cornerRadius(12)
                            .font(.headline)
                    }
                    .disabled(true)

                    if let msg = readiness.primaryBlockMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                            Text(msg)
                                .foregroundColor(.orange)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var startButtonLabel: String {
        if let name = profileManager.activeProfile?.displayName {
            return "Start — \(name)"
        }
        return "Start Controller Mode"
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        HStack(spacing: 12) {
            Button {
                calibrationEngine.startCalibration()
            } label: {
                Label(
                    interpreter.isLeanCalibrated ? "Re-Calibrate" : "Calibrate Body",
                    systemImage: "figure.stand"
                )
                .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(interpreter.isLeanCalibrated ? .primary : .orange)

            Button {
                stopAndReprepare()
                MotionSessionLogger.shared.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)

            #if DEBUG
            Spacer()
            Button { debugMode.toggle() } label: {
                Image(systemName: debugMode ? "eye.slash" : "eye")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(debugMode ? .yellow : .primary)
            #endif
        }
    }

    // MARK: - Actions

    private func startControllerMode() {
        guard let profile = profileManager.activeProfile else { return }
        controllerSession.activate()
        gameLauncher.launch(game: profile.gameID)
        BackgroundTaskManager.shared.beginBackgroundProcessing()
    }

    /// Stop the session, close the game, and immediately re-prepare so the
    /// state returns to .ready / .needsCalibration — no manual Reset step needed.
    private func stopAndReprepare() {
        gameLauncher.returnFromGame()
        controllerSession.end()
        if let profile = profileManager.activeProfile {
            let cal = BodyCalibration.load() ?? .uncalibrated
            controllerSession.prepare(gameProfile: profile, calibration: cal)
        } else {
            controllerSession.reset()
        }
    }

    // MARK: - Live duration text

    private var liveDurationText: String {
        let total = Int(controllerSession.sessionDuration)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m\(String(format: "%02d", s))s" : "\(s)s"
    }

    // MARK: - DEBUG overlays

    #if DEBUG
    private var overlayToggles: some View {
        VStack(spacing: 6) {
            Button(showHandOverlay ? "Hide Hands" : "Show Hands") { showHandOverlay.toggle() }
            Button(showLandmarkOverlay ? "Hide Skeleton" : "Show Skeleton") { showLandmarkOverlay.toggle() }
        }
        .font(.caption.bold())
        .padding(8)
        .background(Color.black.opacity(0.6))
        .foregroundColor(.white)
        .cornerRadius(8)
    }

    private var gestureDebugOverlay: some View {
        let d = interpreter.debugInfo
        let fmt = { (v: Float?) -> String in
            guard let v else { return "—" }
            return String(format: "%.3f", v)
        }
        return VStack(alignment: .leading, spacing: 4) {
            // Tracking header
            HStack {
                Circle()
                    .fill(d.isReliable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(d.isReliable ? "Tracking OK" : "Tracking LOST")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(d.isReliable ? .green : .red)
                Spacer()
                Text(String(format: "conf %.2f", d.confidence))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }

            Divider().background(Color.white.opacity(0.3))

            HStack {
                Text("Confirmed:")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                Text(interpreter.currentEvent.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(interpreter.currentEvent == .none ? .gray : .cyan)
                Spacer()
                Text("Candidate: \(d.candidate.displayName) [\(d.pendingCount)/3]")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.yellow)
            }

            if let cmd = profileManager.lastMappedCommand {
                Text("→ \(cmd.displayName)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            }

            Divider().background(Color.white.opacity(0.3))

            Group {
                landmarkRow("LWrist Y",     fmt(d.leftWristY),    "LShoulder Y", fmt(d.leftShoulderY))
                landmarkRow("RWrist Y",     fmt(d.rightWristY),   "RShoulder Y", fmt(d.rightShoulderY))
                landmarkRow("LHip Y",       fmt(d.leftHipY),      "RHip Y",      fmt(d.rightHipY))
                landmarkRow("Lean Δ(cal)",  fmt(d.leanDelta),     "Lean(raw)",   fmt(d.rawLeanDelta))
                landmarkRow("Lean offset",
                            String(format: "%+.3f", interpreter.leanNeutralOffset),
                            interpreter.isLeanCalibrated ? "cal ✓" : "cal…", "")
                landmarkRow("HandsUp",      fmt(d.handsUpScore),  "Jump/Squat",  fmt(d.jumpMetric))
            }

            HStack(spacing: 6) {
                Button {
                    interpreter.debugLeanOnly.toggle()
                } label: {
                    Label(interpreter.debugLeanOnly ? "Lean Only ON" : "Lean Only OFF",
                          systemImage: "figure.walk")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.bordered)
                .tint(interpreter.debugLeanOnly ? .orange : .primary)
                Spacer()
            }

            Divider().background(Color.white.opacity(0.3))

            HStack(spacing: 4) {
                Text("✋ HAND").font(.system(size: 9, weight: .bold)).foregroundColor(.cyan)
                Spacer()
                Text("shape: \(handInterpreter.currentShape.displayName)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(handInterpreter.currentShape == .pointing ? .yellow : .white.opacity(0.4))
                Text("hist:\(handInterpreter.historyFill)/16\(handInterpreter.isInGrace ? " ⏳" : "")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(handInterpreter.isInGrace ? .orange : .white.opacity(0.4))
            }
            HStack {
                Text(handInterpreter.candidate == .none ? "—" : handInterpreter.candidate.displayName)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(handInterpreter.candidate == .none ? .gray : .yellow)
                Text("[\(handInterpreter.pendingCount)/3]")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                if handInterpreter.currentGesture != .none {
                    Text(handInterpreter.currentGesture == .swipeLeft ? "Swipe Left" : "Swipe Right")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.yellow)
                }
            }

            Divider().background(Color.white.opacity(0.3))

            HStack(spacing: 4) {
                Text("⚡ COORD").font(.system(size: 9, weight: .bold)).foregroundColor(.orange)
                Spacer()
                if let reason = coordinator.suppressionReason {
                    Text("🚫 \(reason)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("body: \(coordinator.lastBodyEvent == .none ? "—" : coordinator.lastBodyEvent.displayName)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(coordinator.lastBodyEvent == .none ? .gray : .cyan)
                    Text("hand: \(coordinator.lastHandGesture == .none ? "—" : coordinator.lastHandGesture.displayName)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(coordinator.lastHandGesture == .none ? .gray :
                            coordinator.suppressionReason != nil ? .red.opacity(0.7) : .yellow)
                }
                Spacer()
                if coordinator.lastResolvedIntent != .none {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("→ \(coordinator.lastResolvedIntent.displayName)")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.green)
                        Text("via \(coordinator.lastCommandSource.displayName)")
                            .font(.system(size: 9)).foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            Divider().background(Color.white.opacity(0.2))
            Text("BLE TEST")
                .font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(GameCommand.allCases, id: \.rawValue) { command in
                    Button { band.send(command: command) } label: {
                        Text(command.displayName)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(band.lastSentCommand == command ? .green : .gray)
                    .disabled(!band.isConnected)
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.72))
        .cornerRadius(10)
        .frame(maxWidth: 340)
    }

    private func landmarkRow(_ l1: String, _ v1: String, _ l2: String, _ v2: String) -> some View {
        HStack(spacing: 4) {
            Text(l1).font(.system(size: 9)).foregroundColor(.white.opacity(0.55)).frame(width: 64, alignment: .leading)
            Text(v1).font(.system(size: 10, design: .monospaced)).foregroundColor(.white).frame(width: 52, alignment: .trailing)
            Spacer()
            Text(l2).font(.system(size: 9)).foregroundColor(.white.opacity(0.55)).frame(width: 64, alignment: .leading)
            Text(v2).font(.system(size: 10, design: .monospaced)).foregroundColor(.white).frame(width: 52, alignment: .trailing)
        }
    }
    #endif
}
