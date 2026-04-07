// ContentView.swift
// MotionMind
//
// Main integrator view. Wires the 6-layer architecture:
//   1. Capture    (CameraManager / SyntheticFrameSource)
//   2. Engine     (MotionEngine)
//   3. Interpreter (MotionInterpreter)
//   4. Runtime    (GameSession)
//   5. Presentation (ExternalDisplayManager + GameView on iPad)
//   6. Diagnostics (DebugOverlayView + FakeMotionSource)

import SwiftUI
import AVFoundation

struct ContentView: View {

    // MARK: - Layer 1: Capture
    @StateObject private var frameSource: CameraManager = CameraManager()

    // MARK: - Layer 2: Motion Engine
    @StateObject private var motionEngine = MotionEngine()
    @StateObject private var handEngine = HandEngine()
    @StateObject private var handInterpreter = HandGestureInterpreter()

    // MARK: - Layer 3.5: Input Coordinator
    @StateObject private var coordinator = InputCoordinator()

    // MARK: - Layer 3: Motion Interpreter
    @StateObject private var interpreter = MotionInterpreter()

    // MARK: - Layer 4: Game Runtime
    @StateObject private var session = GameSession()

    // MARK: - Layer 5: Presentation
    @StateObject private var displayManager = ExternalDisplayManager()
    @StateObject private var gameLauncher = GameLauncher.shared

    // MARK: - BLE Band
    @StateObject private var band = BandBLEManager()

    // MARK: - Game Profile
    @StateObject private var profileManager = GameProfileManager()

    // MARK: - Body Calibration
    @StateObject private var calibrationEngine = CalibrationEngine()

    // MARK: - Layer 6: Diagnostics
    @State private var didSetupLayers = false

    #if DEBUG
    @State private var useSyntheticInput = false  // set to true to bypass camera and use FakeMotionSource
    @State private var debugMode = true  // ← Auto-enable debug panel
    @State private var showLandmarkOverlay = true  // toggle skeleton overlay in real-camera mode
    @State private var showHandOverlay = true       // toggle hand/finger overlay independently
    private let fakeSource = FakeMotionSource()
    #endif

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // --- Layout: iPad or iPad + TV ---
            if displayManager.isExternalDisplayConnected {
                operatorSurface  // iPad: camera feed + controls for parent
            } else {
                fallbackLayout   // iPad: camera feed + game embedded
            }

            // Body calibration overlay — covers UI during active calibration phases.
            // CalibrationEngine auto-dismisses after completion / failure.
            if calibrationEngine.isActive {
                CalibrationOverlayView(phase: calibrationEngine.phase)
            }
        }
        .onAppear { setupLayers() }
        .onDisappear { teardownLayers() }
        .onChange(of: calibrationEngine.phase) { phase in
            // When CalibrationEngine finishes, push the personalized calibration
            // into MotionInterpreter so body-relative thresholds take effect immediately.
            if case .complete(let cal) = phase {
                interpreter.applyCalibration(cal)
            }
        }
    }

    // MARK: - Layouts

    /// Operator surface on iPad (parent controls). Game is on TV via ExternalDisplayManager.
    private var operatorSurface: some View {
        VStack(spacing: 12) {
            // Top: camera preview + diagnostics
            VStack {
                CameraPreviewRepresentable(cameraManager: frameSource)
                    .frame(height: 300)
                    .cornerRadius(12)

                #if DEBUG
                if debugMode {
                    debugPanel
                }
                #endif
            }
            .padding()

            Spacer()

            // Bottom: session controls
            VStack(spacing: 12) {
                sessionControlsPanel
            }
            .padding()
        }
    }

    /// Fallback: iPad-only, game embedded below camera.
    private var fallbackLayout: AnyView {
        #if DEBUG
        if useSyntheticInput {
            return AnyView(
                ZStack(alignment: .top) {
                    GameView(session: session)
                        .ignoresSafeArea()
                    if debugMode {
                        debugPanel.padding()
                    }
                }
            )
        } else {
            return AnyView(
                ZStack {
                    CameraPreviewRepresentable(cameraManager: frameSource)
                        .ignoresSafeArea()

                    // MediaPipe pose overlay
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

                    // MediaPipe hand overlay
                    if showHandOverlay {
                        HandOverlayView(hands: handEngine.latestHands)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

                    // Gesture debug panel (top-left)
                    VStack {
                        HStack {
                            gestureDebugOverlay.padding()
                            Spacer()
                        }
                        Spacer()
                        // Toggle buttons (bottom-right)
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Button(showHandOverlay ? "Hide Hands" : "Show Hands") {
                                    showHandOverlay.toggle()
                                }
                                Button(showLandmarkOverlay ? "Hide Skeleton" : "Show Skeleton") {
                                    showLandmarkOverlay.toggle()
                                }
                            }
                            .font(.caption.bold())
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .padding()
                        }
                    }
                }
            )
        }
        #else
        return AnyView(
            CameraPreviewRepresentable(cameraManager: frameSource)
                .ignoresSafeArea()
        )
        #endif
    }

    // MARK: - Debug panel

    #if DEBUG
    private var debugPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("DEBUG MODE").font(.caption.bold()).foregroundColor(.yellow)
                Spacer()
                Button(action: { useSyntheticInput.toggle() }) {
                    Label(useSyntheticInput ? "Fake Input ON" : "Fake Input OFF",
                          systemImage: "waveform.circle.fill")
                        .font(.caption)
                        .foregroundColor(useSyntheticInput ? .green : .gray)
                }
            }

            // Row 1: live MotionEvent + unmapped indicator
            HStack {
                Text("Event: \(interpreter.currentEvent.displayName)")
                    .foregroundColor(interpreter.currentEvent == .none ? .gray : .cyan)
                Spacer()
                if let miss = profileManager.lastUnmappedEvent {
                    Text("⚠️ \(miss.displayName)")
                        .foregroundColor(.red.opacity(0.75))
                }
            }

            // Row 2: active profile + last mapped command
            HStack {
                Text("Game: \(profileManager.activeProfile?.displayName ?? "—")")
                Spacer()
                Text("Map: \(profileManager.lastMappedCommand?.displayName ?? "—")")
            }
            .foregroundColor(.orange)

            // Row 3: last command dispatched to band
            HStack {
                Text("Band: \(band.isConnected ? "✓ connected" : "off")")
                    .foregroundColor(band.isConnected ? .green : .yellow)
                Spacer()
                Text("Sent: \(band.lastSentCommand?.displayName ?? "—")")
                    .foregroundColor(band.isConnected ? .green : .gray)
            }

            // BLE Test — bypass motion pipeline and send fixed commands directly to band
            Divider().background(Color.white.opacity(0.2))
            Text("BLE TEST  (bypasses profile)")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(GameCommand.allCases, id: \.rawValue) { command in
                    Button(action: { band.send(command: command) }) {
                        Text(command.displayName)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(band.lastSentCommand == command ? .green : .gray)
                    .disabled(!band.isConnected)
                }
            }

            // Row 4: profile switcher (mirrors sessionControlsPanel picker for non-TV testing)
            let profiles = profileManager.availableProfiles()
            if profiles.count > 1 {
                Picker(
                    "Profile",
                    selection: Binding(
                        get: { profileManager.activeGameID ?? .subwaySurfers },
                        set: { profileManager.setActiveGame($0) }
                    )
                ) {
                    ForEach(profiles, id: \.gameID) { profile in
                        Text(profile.displayName).tag(profile.gameID)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }

    private var sessionControlsPanel: some View {
        VStack(spacing: 12) {
            // Status indicators
            HStack(spacing: 16) {
                statusIndicator(
                    icon: "camera.fill",
                    label: "Camera",
                    active: frameSource.isCameraActive
                )
                statusIndicator(
                    icon: "waveform",
                    label: "MediaPipe",
                    active: frameSource.isRunning
                )
                statusIndicator(
                    icon: "tv",
                    label: "Monitor",
                    active: displayManager.isExternalDisplayConnected
                )
                bandStatusIndicator
                Spacer()
                Text(sessionStateLabel(session.state))
                    .font(.caption.bold())
                    .foregroundColor(sessionStateColor(session.state))
            }

            Divider().background(Color.white.opacity(0.3))

            // Profile picker — hidden when only one profile is available
            let profiles = profileManager.availableProfiles()
            if profiles.count > 1 {
                Picker(
                    "Game Profile",
                    selection: Binding(
                        get: { profileManager.activeGameID ?? .subwaySurfers },
                        set: { profileManager.setActiveGame($0) }
                    )
                ) {
                    ForEach(profiles, id: \.gameID) { profile in
                        Text(profile.displayName).tag(profile.gameID)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Game launch / return button
            if gameLauncher.gameRunning {
                Button(action: { gameLauncher.returnFromGame() }) {
                    Label("BACK TO MOTIONMIND", systemImage: "arrow.uturn.left")
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .font(.headline)
                }
            } else {
                Button(action: {
                    gameLauncher.launchSubwaySurfers()
                    BackgroundTaskManager.shared.beginBackgroundProcessing()
                }) {
                    Label("🎮  PLAY GAME", systemImage: "gamecontroller.fill")
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .font(.headline)
                }
            }

            // Calibrate + Reset
            HStack(spacing: 12) {
                Button(action: { session.beginCalibration() }) {
                    Label("Calibrate", systemImage: "target")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button(action: { calibrationEngine.startCalibration() }) {
                    Label("Calibrate Body", systemImage: "figure.stand")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(interpreter.isLeanCalibrated ? .primary : .orange)

                Button(action: {
                    session.reset()
                    MotionSessionLogger.shared.reset()
                }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func statusIndicator(icon: String, label: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundColor(active ? .green : .red)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    /// Band status uses green when connected, yellow (not red) when scanning/disconnected.
    private var bandStatusIndicator: some View {
        VStack(spacing: 3) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundColor(band.isConnected ? .green : .yellow)
            Text(band.isConnected ? "Band ✓" : band.statusText)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func sessionStateLabel(_ state: GameSessionState) -> String {
        switch state {
        case .idle:                return "Idle"
        case .calibrating:         return "Calibrating"
        case .countdown(let n):    return "Countdown: \(n)"
        case .active:              return "▶️ Playing"
        case .paused(let reason):      return "⏸️ Paused (\(reason))"
        case .roundOver(let score):    return "Game Over (\(score))"
        case .completed(let score):    return "✅ Done (\(score))"
        }
    }

    private func sessionStateColor(_ state: GameSessionState) -> Color {
        switch state {
        case .active:   return .green
        case .paused:   return .orange
        case .idle:     return .gray
        default:        return .white
        }
    }

    // MARK: - Gesture debug overlay (real-camera mode)

    private var gestureDebugOverlay: some View {
        let d = interpreter.debugInfo
        let fmt = { (v: Float?) -> String in
            guard let v else { return "—" }
            return String(format: "%.3f", v)
        }
        return VStack(alignment: .leading, spacing: 4) {
            // Header
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

            // Confirmed event + pending progress
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

            // Last mapped command
            if let cmd = profileManager.lastMappedCommand {
                Text("→ \(cmd.displayName)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            }

            Divider().background(Color.white.opacity(0.3))

            // Raw landmark values
            Group {
                landmarkRow("LWrist Y", fmt(d.leftWristY), "LShoulder Y", fmt(d.leftShoulderY))
                landmarkRow("RWrist Y", fmt(d.rightWristY), "RShoulder Y", fmt(d.rightShoulderY))
                landmarkRow("LHip Y",  fmt(d.leftHipY),   "RHip Y",      fmt(d.rightHipY))
                // Lean Δ = calibrated (0=neutral); rawLean = before offset subtraction
                landmarkRow("Lean Δ(cal)", fmt(d.leanDelta), "Lean(raw)", fmt(d.rawLeanDelta))
                landmarkRow("Lean offset",
                            String(format: "%+.3f", interpreter.leanNeutralOffset),
                            interpreter.isLeanCalibrated ? "cal ✓" : "cal…",
                            "")
                // handsUpScore: negative means wrists above shoulders; fires when < -handsUpMargin
                landmarkRow("HandsUp score", fmt(d.handsUpScore), "Jump/Squat", fmt(d.jumpMetric))
            }

            // Debug mode toggle: lean-only isolates lean from competing recognizers
            HStack(spacing: 6) {
                Button(action: { interpreter.debugLeanOnly.toggle() }) {
                    Label(interpreter.debugLeanOnly ? "Lean Only ON" : "Lean Only OFF",
                          systemImage: "figure.walk")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.bordered)
                .tint(interpreter.debugLeanOnly ? .orange : .primary)
                Spacer()
            }

            Divider().background(Color.white.opacity(0.3))

            // ── Hand gesture section ──────────────────────────────
            HStack(spacing: 4) {
                Text("✋ HAND")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.cyan)
                Spacer()
                Text("shape: \(handInterpreter.currentShape.displayName)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(handInterpreter.currentShape == .pointing ? .yellow : .white.opacity(0.4))
                Text("hist:\(handInterpreter.historyFill)/16\(handInterpreter.isInGrace ? " ⏳" : "")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(handInterpreter.isInGrace ? .orange : .white.opacity(0.4))
            }
            HStack {
                let cand = handInterpreter.candidate
                let cnt  = handInterpreter.pendingCount
                Text(cand == .none ? "—" : cand.displayName)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(cand == .none ? .gray : .yellow)
                Text("[\(cnt)/3]")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                if handInterpreter.currentGesture != .none {
                    Text(handInterpreter.currentGesture == .swipeLeft ? "Swipe Left" : "Swipe Right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.yellow)
                }
            }

            Divider().background(Color.white.opacity(0.3))

            // ── InputCoordinator section ──────────────────────────
            HStack(spacing: 4) {
                Text("⚡ COORD")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
                Spacer()
                if let reason = coordinator.suppressionReason {
                    Text("🚫 \(reason)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                        Text("via \(coordinator.lastCommandSource.displayName)")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
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

    // MARK: - Setup

    private func setupLayers() {
        guard !didSetupLayers else { return }
        didSetupLayers = true

        // Layer 2 → 3: Wire MotionEngine to MotionInterpreter
        motionEngine.delegate = interpreter

        // Layer 2 → 3b: Wire HandEngine to HandGestureInterpreter
        handInterpreter.connect(to: handEngine)
        // Hand gestures feed InputCoordinator — conflict gating happens there.
        handInterpreter.onHandGesture = { [weak coordinator] gesture in
            coordinator?.receive(handGesture: gesture)
        }

        // Layer 3 → 4: Wire both interpreters through InputCoordinator.
        // Only set default game on first launch; UserDefaults restores the selection otherwise.
        if profileManager.getActiveProfileID() == nil {
            profileManager.setActiveGame(.subwaySurfers)
        }

        // Apply active profile immediately to both interpreters
        if let profile = profileManager.activeProfile {
            interpreter.apply(profile: profile)
            handInterpreter.apply(profile: profile)
        }

        // Reconfigure both interpreters whenever the active game changes
        profileManager.onProfileChanged = { [weak interpreter, weak handInterpreter] profile in
            interpreter?.apply(profile: profile)
            handInterpreter?.apply(profile: profile)
        }

        // Unified intent path: coordinator → GameProfileManager → BandBLEManager
        // Both body and hand flow through here after conflict resolution.
        coordinator.onIntent = { [weak session, weak band, weak profileManager] intent in
            // GameSession only understands MotionEvent (body actions).
            // Map hand intents to the equivalent MotionEvent where applicable.
            if case .leanLeft  = intent { session?.handle(event: .leanLeft)  }
            if case .leanRight = intent { session?.handle(event: .leanRight) }
            if case .jump      = intent { session?.handle(event: .jump)      }
            if case .squat     = intent { session?.handle(event: .squat)     }
            if case .handsUp   = intent { session?.handle(event: .handsUp)   }
            if case .handsDown = intent { session?.handle(event: .handsDown) }
            // Hand intents (.handSwipeLeft/.handSwipeRight) don't map to GameSession actions.

            if let command = profileManager?.mapIntent(intent) {
                band?.send(command: command)
            }
        }
        // Body events enter the coordinator.
        interpreter.onMotionEvent = { [weak coordinator] event in
            coordinator?.receive(bodyEvent: event)
        }

        // Wire logger and calibration feed.
        // CalibrationEngine.feed() is a no-op when idle so this is always safe.
        motionEngine.onPoseSnapshot = { [weak interpreter, weak calibrationEngine] snapshot in
            calibrationEngine?.feed(snapshot: snapshot)
            if let event = interpreter?.currentEvent, event != .none {
                MotionSessionLogger.shared.log(event: event, snapshot: snapshot)
            }
        }

        // Layer 1: Start frame source
        #if DEBUG
        if useSyntheticInput {
            // Use fake frames + fake poses (bypass MotionEngine entirely)
            fakeSource.delegate = interpreter
            // FakeMotionSource uses replay(script:) — start a demo script
            fakeSource.replay(script: FakeMotionSource.demoScript)
            print("🔧 DEBUG: Using SyntheticFrameSource + FakeMotionSource")
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

        // Layer 5: Wire external display with ParentMonitorView
        if displayManager.isExternalDisplayConnected,
           let externalScreen = UIScreen.screens.first(where: { $0 != UIScreen.main }) {
            displayManager.connect(
                to: externalScreen,
                session: session,
                interpreter: interpreter,
                cameraManager: frameSource
            )
        }

        // Layer 4: Start game
        session.beginCalibration()

        print("✅ All 6 layers initialized and wired")
    }

    private func teardownLayers() {
        #if DEBUG
        if useSyntheticInput {
            fakeSource.stop()
        } else {
            frameSource.stop()
        }
        #else
        frameSource.stop()
        #endif

        session.reset()
        displayManager.disconnect()
    }
}

// MARK: - CameraPreviewRepresentable

struct CameraPreviewRepresentable: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager

    func makeUIView(context: Context) -> PreviewContainerView {
        print("📷 CameraPreviewRepresentable: makeUIView — previewLayer at this point: \(cameraManager.previewLayer != nil ? "ready" : "nil (will attach in updateUIView)")")
        return PreviewContainerView()
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        let incoming = cameraManager.previewLayer
        // Only skip if the layer is already the same non-nil object.
        // Do NOT skip nil→nil: that's the case where the layer hasn't arrived yet
        // and we must attach it as soon as it becomes available.
        if let incoming, uiView.previewLayer === incoming { return }
        print("📷 CameraPreviewRepresentable: updateUIView — incoming=\(incoming != nil ? "non-nil" : "nil")")
        uiView.previewLayer = incoming
    }
}

/// UIView subclass that keeps the preview layer filling its bounds at all times,
/// including after SwiftUI layout passes and device rotation.
final class PreviewContainerView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        print("📷 PreviewContainerView: init")
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            guard let layer = previewLayer else { return }
            layer.videoGravity = .resizeAspectFill
            backgroundColor = .clear
            self.layer.insertSublayer(layer, at: 0)
            // Set frame immediately; layoutSubviews will correct it once final bounds arrive.
            layer.frame = bounds
            print("📷 PreviewContainerView: layer attached — bounds=\(bounds) layerFrame=\(layer.frame) superlayer=\(layer.superlayer != nil ? "ok" : "nil")")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layer = previewLayer else { return }
        layer.frame = bounds
        print("📷 PreviewContainerView: layoutSubviews bounds=\(bounds) layerFrame=\(layer.frame)")
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


