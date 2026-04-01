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

    // MARK: - Layer 6: Diagnostics
    #if DEBUG
    @State private var useSyntheticInput = false
    @State private var debugMode = false
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
            // Top: camera preview
            CameraPreviewRepresentable(cameraManager: frameSource)
                .frame(height: 300)
                .cornerRadius(12)
                .padding()

            #if DEBUG
            if debugMode {
                debugPanel
                    .padding()
            }
            #endif

            Spacer()

            // Bottom: game (embedded)
            GameView(session: session)
                .frame(height: 200)
                .padding()
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
        HStack(spacing: 16) {
            Button(action: { session.beginCalibration() }) {
                Label("Calibrate", systemImage: "target")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)

            Button(action: { session.reset() }) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)

            Spacer()

            Text(sessionStateLabel(session.state))
                .font(.caption.bold())
                .foregroundColor(sessionStateColor(session.state))
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

        // Layer 3 → 4: Wire MotionInterpreter to GameSession
        interpreter.onMotionEvent = { [weak session] event in
            session?.handle(event: event)
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

        // Layer 5: Wire external display
        if displayManager.isExternalDisplayConnected, let externalScreen = UIScreen.screens.first(where: { $0 != UIScreen.main }) {
            displayManager.connect(to: externalScreen, session: session)
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
