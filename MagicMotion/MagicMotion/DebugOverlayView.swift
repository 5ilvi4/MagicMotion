// DebugOverlayView.swift
// MotionMind
//
// Layer 6 — Diagnostics.
// Replaces SkeletonOverlayView in debug builds.
// Shows all 33 landmarks colored by visibility, current event, confidence, FPS.

import SwiftUI

#if DEBUG
struct DebugOverlayView: View {

    let snapshot: PoseSnapshot?
    let currentEvent: MotionEvent
    let fps: Double

    @State private var showLandmarkIndices = false

    var body: some View {
        ZStack {
            landmarkCanvas
            topHUD
        }
        .onTapGesture {
            withAnimation { showLandmarkIndices.toggle() }
        }
    }

    // MARK: - Landmark canvas

    private var landmarkCanvas: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard let snap = snapshot else { return }
                drawLandmarks(ctx: ctx, size: size, snap: snap)
            }
        }
        .ignoresSafeArea()
    }

    private func drawLandmarks(ctx: GraphicsContext, size: CGSize, snap: PoseSnapshot) {
        let landmarks = orderedLandmarks(snap)
        for (idx, lm) in landmarks.enumerated() {
            guard let lm = lm else { continue }
            let pt = CGPoint(x: CGFloat(lm.x) * size.width,
                             y: CGFloat(lm.y) * size.height)
            let r: CGFloat = 6
            let color: Color = lm.visibility > 0.7 ? .green :
                               lm.visibility > 0.3 ? .yellow : .red
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r,
                                            width: r*2, height: r*2)),
                     with: .color(color))

            if showLandmarkIndices {
                ctx.draw(
                    Text("\(idx)").font(.system(size: 8)).foregroundColor(.white),
                    at: CGPoint(x: pt.x + 8, y: pt.y)
                )
            }
        }
    }

    /// Returns all 33 landmarks as an ordered array (index = MediaPipe index).
    private func orderedLandmarks(_ s: PoseSnapshot) -> [PoseSnapshot.Landmark?] {
        [s.nose,        // 0
         nil, s.leftEye, nil, nil, s.rightEye, nil,   // 1-6
         s.leftEar, s.rightEar, nil, nil,              // 7-10
         s.leftShoulder, s.rightShoulder,              // 11-12
         s.leftElbow, s.rightElbow,                    // 13-14
         s.leftWrist, s.rightWrist,                    // 15-16
         nil, nil, nil, nil, nil, nil,                 // 17-22
         s.leftHip, s.rightHip,                        // 23-24
         s.leftKnee, s.rightKnee,                      // 25-26
         s.leftAnkle, s.rightAnkle,                    // 27-28
         s.leftHeel, s.rightHeel,                      // 29-30
         s.leftFootIndex, s.rightFootIndex]            // 31-32
    }

    // MARK: - HUD

    private var topHUD: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(currentEvent.displayName)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(currentEvent == .none ? .gray : .green)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    let conf = snapshot?.trackingConfidence ?? 0
                    Text("Conf: \(Int(conf * 100))%")
                        .foregroundColor(conf > 0.5 ? .green : .orange)
                    Text("FPS: \(String(format: "%.0f", fps))")
                        .foregroundColor(.cyan)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            }

            if showLandmarkIndices {
                Text("Tap to hide indices")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("Tap to show indices")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.6))
        .cornerRadius(10)
        .padding(.top, 60)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Preview
struct DebugOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            DebugOverlayView(
                snapshot: FakeMotionSource.standingPose(),
                currentEvent: .leanLeft,
                fps: 29.8
            )
        }
    }
}
#endif
