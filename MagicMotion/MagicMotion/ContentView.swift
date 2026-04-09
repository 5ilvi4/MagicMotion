// ContentView.swift
// MagicMotion
//
// App entry point and wiring layer.
// Owns all StateObjects, wires the architecture in setupLayers(),
// and hosts the Home shell TabView.
//
// Architecture layers:
//   1. Capture      (CameraManager)
//   2. Engine       (MotionEngine + HandEngine)
//   3. Interpreter  (MotionInterpreter + HandGestureInterpreter)
//   3.5 Coordinator (InputCoordinator)
//   4. Session      (ControllerSession)
//   5. Presentation (ExternalDisplayManager → HomeMonitorView)
//   6. Diagnostics  (DEBUG only — FakeMotionSource)
//
// Tab views: ControllerModeView · SetupView · ReportsView

import SwiftUI
import AVFoundation

struct ContentView: View {

    // MARK: - Layer 1: Capture
    @StateObject private var frameSource    = CameraManager()

    // MARK: - Layer 2: Engine
    @StateObject private var motionEngine   = MotionEngine()
    @StateObject private var handEngine     = HandEngine()

    // MARK: - Layer 3: Interpreter
    @StateObject private var interpreter       = MotionInterpreter()
    @StateObject private var handInterpreter   = HandGestureInterpreter()

    // MARK: - Layer 3.5: Coordinator
    @StateObject private var coordinator    = InputCoordinator()

    // MARK: - Layer 4: Session
    @StateObject private var controllerSession = ControllerSession()

    // MARK: - Layer 5: Presentation
    @StateObject private var displayManager = ExternalDisplayManager()
    @StateObject private var gameLauncher   = GameLauncher.shared

    // MARK: - Support
    @StateObject private var band           = BandBLEManager()
    @StateObject private var profileManager = GameProfileManager()
    @StateObject private var calibrationEngine = CalibrationEngine()
    @StateObject private var reportStore    = SessionReportStore()
    @StateObject private var reportDashboard = ReportDashboard()

    // MARK: - Wiring guard
    @State private var didSetupLayers = false

    // MARK: - DEBUG: synthetic input bypass
    #if DEBUG
    @State private var useSyntheticInput = false
    private let fakeSource = FakeMotionSource()
    #endif

    // MARK: - Body

    var body: some View {
        TabView {
            ControllerModeView(
                frameSource:       frameSource,
                motionEngine:      motionEngine,
                interpreter:       interpreter,
                handEngine:        handEngine,
                handInterpreter:   handInterpreter,
                coordinator:       coordinator,
                calibrationEngine: calibrationEngine,
                controllerSession: controllerSession,
                profileManager:    profileManager,
                band:              band,
                gameLauncher:      gameLauncher,
                displayManager:    displayManager
            )
            .tabItem { Label("Play", systemImage: "gamecontroller.fill") }

            SetupView(
                band:              band,
                calibrationEngine: calibrationEngine,
                controllerSession: controllerSession,
                interpreter:       interpreter
            )
            .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }

            ReportsView(controllerSession: controllerSession, reportStore: reportStore, dashboard: reportDashboard)
                .tabItem { Label("Reports", systemImage: "chart.bar.fill") }
        }
        .onAppear  { setupLayers() }
        .onDisappear { teardownLayers() }
        .onChange(of: calibrationEngine.phase) { phase in
            if case .complete(let cal) = phase {
                interpreter.applyCalibration(cal)
                if let gameProfile = profileManager.activeProfile {
                    controllerSession.prepare(gameProfile: gameProfile, calibration: cal)
                }
            }
        }
    }

    // MARK: - Layer wiring

    private func setupLayers() {
        guard !didSetupLayers else { return }
        didSetupLayers = true

        // Layer 2 → 3
        motionEngine.delegate = interpreter
        handInterpreter.connect(to: handEngine)
        handInterpreter.onHandGesture = { [weak coordinator] gesture in
            coordinator?.receive(handGesture: gesture)
        }

        // Default profile on first launch
        if profileManager.getActiveProfileID() == nil {
            profileManager.setActiveGame(.subwaySurfers)
        }
        if let profile = profileManager.activeProfile {
            interpreter.apply(profile: profile)
            handInterpreter.apply(profile: profile)
        }

        // Reconfigure when the active game changes
        profileManager.onProfileChanged = { [weak interpreter, weak handInterpreter, weak controllerSession] profile in
            interpreter?.apply(profile: profile)
            handInterpreter?.apply(profile: profile)
            let cal = BodyCalibration.load() ?? .uncalibrated
            controllerSession?.prepare(gameProfile: profile, calibration: cal)
        }

        // Prepare ControllerSession
        if let profile = profileManager.activeProfile {
            let cal = BodyCalibration.load() ?? .uncalibrated
            controllerSession.prepare(gameProfile: profile, calibration: cal)
        }

        // Band disconnect / reconnect → record in session
        band.onDisconnect = { [weak controllerSession] in
            controllerSession?.recordBandDisconnect()
        }
        // band.onReconnect is available for future use (e.g. toast notification).

        // Safety zone → release D-pad + count + pause controller (only when active)
        // Guard required: onSafetyZoneViolation fires every MediaPipe frame while
        // nose.z < threshold (~30×/s). Without the guard, sendNeutral() would write
        // 0x00 to BLE continuously while already paused.
        interpreter.onSafetyZoneViolation = { [weak controllerSession, weak band] in
            guard case .active = controllerSession?.state else { return }
            band?.sendNeutral()
            controllerSession?.recordSafetyZoneViolation()
            controllerSession?.pause(reason: .safetyZoneViolation)
        }

        // Tracking loss → release D-pad + count + pause controller when active
        interpreter.onTrackingLost = { [weak controllerSession, weak band] in
            guard case .active = controllerSession?.state else { return }
            band?.sendNeutral()
            controllerSession?.recordTrackingLost()
            controllerSession?.pause(reason: .trackingLost)
        }

        // Tracking restored → auto-resume only when the pause was specifically for
        // tracking loss. Safety-zone and backgrounding pauses require explicit user action.
        interpreter.onTrackingRestored = { [weak controllerSession] in
            guard case .paused(let reason) = controllerSession?.state,
                  reason == .trackingLost else { return }
            controllerSession?.resume()
        }

        // App backgrounding → pause controller when active + release D-pad
        BackgroundTaskManager.shared.onDidEnterBackground = { [weak controllerSession, weak band] in
            guard case .active = controllerSession?.state else { return }
            band?.sendNeutral()          // release D-pad before pausing
            controllerSession?.pause(reason: .appBackgrounded)
        }

        // App foregrounding → if paused for backgrounding and game is no longer
        // running, re-prepare to .ready so the user sees the Play panel (not a stuck
        // "Controller paused" banner). If the launched game is still open (gameLauncher
        // reports gameRunning = true), leave the session paused — the user is expected
        // to come back fully when they tap Stop.
        BackgroundTaskManager.shared.onWillEnterForeground = { [weak controllerSession, weak profileManager, weak gameLauncher] in
            guard case .paused(let reason) = controllerSession?.state,
                  reason == .appBackgrounded else { return }
            // If the user returned to MagicMotion directly (game not running), reset to ready.
            if gameLauncher?.gameRunning == false {
                if let profile = profileManager?.activeProfile {
                    let cal = BodyCalibration.load() ?? .uncalibrated
                    controllerSession?.prepare(gameProfile: profile, calibration: cal)
                } else {
                    controllerSession?.reset()
                }
            }
            // If gameLauncher.gameRunning is still true, the user backgrounded back to
            // MagicMotion while the game is open in the switcher. Leave paused — they
            // can tap Resume or Stop explicitly.
        }

        // Session end → release D-pad + persist report + refresh dashboard
        controllerSession.onSessionEnded = { [weak reportStore, weak band, weak reportDashboard] report in
            band?.sendNeutral()
            reportStore?.save(report)
            if let store = reportStore {
                reportDashboard?.refresh(from: store.reports)
            }
        }

        // Intent path: coordinator → ControllerSession + band
        // BLE send is gated on session being active. Camera and pose detection keep
        // running while paused — confirmed gestures must not produce game inputs
        // while the pause banner is visible or the session has ended.
        coordinator.onIntent = { [weak controllerSession, weak band, weak profileManager] intent in
            controllerSession?.handle(intent: intent)
            guard case .active = controllerSession?.state else { return }
            if let command = profileManager?.mapIntent(intent) {
                band?.send(command: command)
                controllerSession?.recordMappedCommand(command)
            }
        }
        interpreter.onMotionEvent = { [weak coordinator] event in
            coordinator?.receive(bodyEvent: event)
        }

        // Pose snapshot → calibration feed + session logger
        motionEngine.onPoseSnapshot = { [weak interpreter, weak calibrationEngine] snapshot in
            calibrationEngine?.feed(snapshot: snapshot)
            if let event = interpreter?.currentEvent, event != .none {
                MotionSessionLogger.shared.log(event: event, snapshot: snapshot)
            }
        }

        // Layer 1: Start frame source
        #if DEBUG
        if useSyntheticInput {
            fakeSource.delegate = interpreter
            fakeSource.replay(script: FakeMotionSource.demoScript)
            print("🔧 DEBUG: Using FakeMotionSource")
        } else {
            frameSource.onNewFrame = { [motionEngine, handEngine] buffer, orientation in
                motionEngine.processFrame(buffer, orientation: orientation)
                handEngine.processFrame(buffer)
            }
            frameSource.start()
            print("📷 Using real camera")
        }
        #else
        frameSource.onNewFrame = { [motionEngine, handEngine] buffer, orientation in
            motionEngine.processFrame(buffer, orientation: orientation)
            handEngine.processFrame(buffer)
        }
        frameSource.start()
        #endif

        // Layer 5: External display
        if displayManager.isExternalDisplayConnected,
           let externalScreen = UIScreen.screens.first(where: { $0 != UIScreen.main }) {
            displayManager.connect(
                to: externalScreen,
                controllerSession: controllerSession,
                interpreter: interpreter,
                cameraManager: frameSource
            )
        }

        // Seed dashboard from any previously persisted reports.
        reportDashboard.refresh(from: reportStore.reports)

        print("✅ All layers initialized and wired")
    }

    private func teardownLayers() {
        #if DEBUG
        if useSyntheticInput { fakeSource.stop() } else { frameSource.stop() }
        #else
        frameSource.stop()
        #endif
        controllerSession.end()
        displayManager.disconnect()
    }
}

// MARK: - CameraPreviewRepresentable

struct CameraPreviewRepresentable: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager

    func makeUIView(context: Context) -> PreviewContainerView {
        print("📷 CameraPreviewRepresentable: makeUIView — previewLayer: \(cameraManager.previewLayer != nil ? "ready" : "pending")")
        return PreviewContainerView()
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        let incoming = cameraManager.previewLayer
        if let incoming, uiView.previewLayer === incoming { return }
        print("📷 CameraPreviewRepresentable: updateUIView — incoming=\(incoming != nil ? "non-nil" : "nil")")
        uiView.previewLayer = incoming
    }
}

/// Keeps the AVCaptureVideoPreviewLayer filling its bounds after layout passes and rotation.
final class PreviewContainerView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            guard let layer = previewLayer else { return }
            layer.videoGravity = .resizeAspectFill
            backgroundColor = .clear
            self.layer.insertSublayer(layer, at: 0)
            layer.frame = bounds
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPad Air (5th generation)")
            .previewInterfaceOrientation(.portrait)
    }
}
#endif
