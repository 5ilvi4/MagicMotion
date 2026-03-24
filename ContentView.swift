// ContentView.swift
// The main screen of the app.
//
// Layer stack (bottom to top):
//   1. Black background
//   2. Live camera preview (AVCaptureVideoPreviewLayer wrapped in UIViewRepresentable)
//   3. Skeleton overlay (SwiftUI Canvas drawn on top of camera)
//   4. Gesture label (large text that pops up when a gesture fires)
//   5. Status bar (top-left: app name + camera state)

import SwiftUI
import AVFoundation

struct ContentView: View {

    // ── Dependencies (created once, live for the app's lifetime) ─────────────
    @StateObject private var cameraManager      = CameraManager()
    @StateObject private var gestureClassifier  = GestureClassifier()
    @StateObject private var airPlayManager     = AirPlayManager()

    // PoseDetector and TouchInjector don't need @StateObject because they don't
    // publish @Published properties we observe directly in this view.
    private let poseDetector  = PoseDetector()
    private let touchInjector = TouchInjector()

    // ── View state ────────────────────────────────────────────────────────────
    /// The most recent skeleton data — updated ~30 fps from the camera thread
    @State private var currentPose: PoseFrame? = nil

    // MARK: - Body

    var body: some View {
        ZStack {

            // ── 1. Black background ──────────────────────────────────────────
            Color.black.ignoresSafeArea()

            // ── 2. Camera preview ────────────────────────────────────────────
            CameraPreviewRepresentable(cameraManager: cameraManager)
                .ignoresSafeArea()

            // ── 3. Skeleton overlay ──────────────────────────────────────────
            // Fills the whole screen and draws joints on top of the camera feed
            SkeletonOverlayView(poseFrame: currentPose)
                .ignoresSafeArea()

            // ── 4. Gesture label ─────────────────────────────────────────────
            gestureLabel

            // ── 5. Status bar ─────────────────────────────────────────────────
            statusBar
        }
        .onAppear {
            connectPipeline()
            cameraManager.requestPermissionAndSetup()
        }
        .onDisappear {
            // Stop the camera when the view is removed (saves battery)
            cameraManager.stopSession()
        }
    }

    // MARK: - Sub-views

    /// Big animated label that appears when a gesture fires.
    private var gestureLabel: some View {
        VStack {
            Spacer()

            if gestureClassifier.currentGesture != .none {
                Text(gestureClassifier.currentGesture.rawValue)
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.65))
                    )
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

            Spacer().frame(height: 48)
        }
        // SwiftUI animates whenever currentGesture changes
        .animation(.spring(response: 0.25, dampingFraction: 0.6),
                   value: gestureClassifier.currentGesture)
    }

    /// Small info panel in the top-left corner.
    private var statusBar: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("SubwaySurferMotion", systemImage: "figure.run")
                        .font(.caption.bold())
                        .foregroundColor(.white)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(cameraManager.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(cameraManager.isRunning ? "Camera running" : "Camera stopped")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    if airPlayManager.isExternalScreenConnected {
                        Label("TV connected", systemImage: "tv")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.55))
                .cornerRadius(12)

                Spacer()
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Pipeline

    /// Wire together: Camera → PoseDetector → GestureClassifier → TouchInjector
    ///
    /// Think of this as connecting LEGO bricks in a chain:
    ///   frame arrives → joints extracted → gesture classified → swipe fired
    private func connectPipeline() {

        // Step 1: Camera delivers each frame to the pose detector
        cameraManager.onNewFrame = { [poseDetector] sampleBuffer, orientation in
            poseDetector.processFrame(sampleBuffer, orientation: orientation)
        }

        // Step 2: Pose detector delivers joint data to:
        //   a) The UI (update the skeleton overlay on the main thread)
        //   b) The gesture classifier
        poseDetector.onPoseDetected = { [gestureClassifier] poseFrame in
            DispatchQueue.main.async {
                // Update skeleton overlay — must happen on main thread
                currentPose = poseFrame
            }
            // Classifier runs on whatever thread delivered the frame (background — that's fine)
            gestureClassifier.addFrame(poseFrame)
        }

        // Step 3: Gesture classifier fires confirmed gestures to the touch injector
        gestureClassifier.onGestureDetected = { [touchInjector] gesture in
            touchInjector.inject(gesture: gesture)
        }
    }
}

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
