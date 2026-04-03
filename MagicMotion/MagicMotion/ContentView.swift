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
    private let motionEngine = MotionEngine()

    // MARK: - Layer 3: Motion Interpreter
    @StateObject private var interpreter = MotionInterpreter()

    // MARK: - Layer 4: Game Runtime
    @StateObject private var session = GameSession()

    // MARK: - Layer 5: Presentation
    @StateObject private var displayManager = ExternalDisplayManager()
    @StateObject private var gameLauncher = GameLauncher.shared

    // MARK: - BLE Band
    @StateObject private var band = BandBLEManager()

    // MARK: - Layer 6: Diagnostics
    #if DEBUG
    @State private var useSyntheticInput = true  // ← DEBUG MODE: Using FakeMotionSource (no camera needed)
    @State private var debugMode = true  // ← Auto-enable debug panel
    @State private var currentSnapshot: PoseSnapshot? = nil
    @State private var fpsCounter: Double = 0.0
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
        }
        .onAppear { setupLayers() }
        .onDisappear { teardownLayers() }
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
    private var fallbackLayout: some View {
        VStack(spacing: 12) {
            #if DEBUG
            // In DEBUG mode with synthetic input, show full game
            if useSyntheticInput {
                GameView(session: session)
                    .ignoresSafeArea()
            } else {
                // With real camera, show camera preview + game
                CameraPreviewRepresentable(cameraManager: frameSource)
                    .frame(height: 300)
                    .cornerRadius(12)
                    .padding()

                if debugMode {
                    debugPanel
                        .padding()
                }

                Spacer()

                GameView(session: session)
                    .frame(height: 200)
                    .padding()
            }
            #else
            // RELEASE: Always show camera + game
            CameraPreviewRepresentable(cameraManager: frameSource)
                .frame(height: 300)
                .cornerRadius(12)
                .padding()

            Spacer()

            GameView(session: session)
                .frame(height: 200)
                .padding()
            #endif
        }
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

            if let snap = currentSnapshot {
                HStack {
                    Text("Conf: \(Int(snap.trackingConfidence * 100))%")
                    Text("Event: \(interpreter.currentEvent.displayName)")
                    Text("FPS: \(String(format: "%.0f", fpsCounter))")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.cyan)
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
                statusIndicator(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "Band",
                    active: band.isConnected
                )
                Spacer()
                Text(sessionStateLabel(session.state))
                    .font(.caption.bold())
                    .foregroundColor(sessionStateColor(session.state))
            }

            Divider().background(Color.white.opacity(0.3))

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

    private func sessionStateLabel(_ state: GameSessionState) -> String {
        switch state {
        case .idle:                return "Idle"
        case .calibrating:         return "Calibrating"
        case .countdown(let n):    return "Countdown: \(n)"
        case .active:              return "▶️ Playing"
        case .paused(let reason):  return "⏸️ Paused (\(reason))"
        case .roundOver:           return "Game Over"
        case .completed(let score):return "✅ Done (\(score))"
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
    #endif

    // MARK: - Setup

    private func setupLayers() {
        // Layer 2 → 3: Wire MotionEngine to MotionInterpreter
        motionEngine.delegate = interpreter

        // Layer 3 → 4: Wire MotionInterpreter to GameSession + Logger + BLE Band
        interpreter.onMotionEvent = { [weak session, weak band] event in
            session?.handle(event: event)
            band?.send(event: event)
        }

        // Wire logger: every snapshot goes to MotionSessionLogger
        motionEngine.onPoseSnapshot = { [weak interpreter] snapshot in
            guard let event = interpreter?.currentEvent, event != .none else { return }
            MotionSessionLogger.shared.log(event: event, snapshot: snapshot)
        }

        // Layer 1: Start frame source
        #if DEBUG
        if useSyntheticInput {
            // Use fake frames + fake poses (bypass MotionEngine entirely)
            fakeSource.delegate = interpreter
            fakeSource.start()
            print("🔧 DEBUG: Using SyntheticFrameSource + FakeMotionSource")
        } else {
            frameSource.onNewFrame = { [motionEngine] buffer, orientation in
                motionEngine.processFrame(buffer, orientation: orientation)
            }
            frameSource.start()
            print("📷 Using real camera")
        }
        #else
        frameSource.onNewFrame = { [motionEngine] buffer, orientation in
            motionEngine.processFrame(buffer, orientation: orientation)
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
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewLayer = cameraManager.previewLayer else { return }
        if previewLayer.superlayer == nil { uiView.layer.addSublayer(previewLayer) }
        DispatchQueue.main.async { previewLayer.frame = uiView.bounds }
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

// MARK: - CameraPreviewRepresentable

/// Bridges AVCaptureVideoPreviewLayer (UIKit) into SwiftUI.
///
/// SwiftUI can't use AVCaptureVideoPreviewLayer directly, so we wrap it in a
/// UIView and use UIViewRepresentable to drop it into our SwiftUI layout.
struct CameraPreviewRepresentable: UIViewRepresentable {

    let cameraManager: CameraManager

    /// makeUIView is called ONCE when the view first appears.
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    /// updateUIView is called every time SwiftUI re-renders this representable.
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewLayer = cameraManager.previewLayer else { return }

        // Attach the preview layer to this view the first time we see it
        if previewLayer.superlayer == nil {
            uiView.layer.addSublayer(previewLayer)
        }

        // Always keep the preview layer sized to fill the UIView
        // (CALayer doesn't auto-resize with its parent — we must do it manually)
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
    }
}

// MARK: - Xcode Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPad Air (5th generation)")
            .previewInterfaceOrientation(.portrait)
    }
}
#endif
