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
    /// Momentary event — auto-clears after 0.8s (shows flash)
    let currentEvent: MotionEvent
    /// Last confirmed event — never auto-clears (stable state)
    let confirmedEvent: MotionEvent
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

    // MediaPipe pose connections (index pairs), matching the official sample topology.
    private static let connections: [(Int, Int)] = [
        // Face
        (0,1),(1,2),(2,3),(3,7),(0,4),(4,5),(5,6),(6,8),
        // Shoulders → hips (torso)
        (11,12),(11,23),(12,24),(23,24),
        // Left arm
        (11,13),(13,15),(15,17),(15,19),(15,21),(17,19),
        // Right arm
        (12,14),(14,16),(16,18),(16,20),(16,22),(18,20),
        // Left leg
        (23,25),(25,27),(27,29),(27,31),(29,31),
        // Right leg
        (24,26),(26,28),(28,30),(28,32),(30,32)
    ]

    private func drawLandmarks(ctx: GraphicsContext, size: CGSize, snap: PoseSnapshot) {
        let landmarks = orderedLandmarks(snap)

        // ── Coordinate transform ──────────────────────────────────────────────
        // Raw buffer: landscape 1280×720. MediaPipe x/y are in landscape space.
        // AVCaptureVideoPreviewLayer (front camera, portrait) applies:
        //   1. Rotate 90° to portrait:
        //        landscape x_mp → screen_y  (x=0 = left of landscape = TOP of portrait)
        //        landscape y_mp → screen_x  (y=0 = top of landscape  = RIGHT of portrait before mirror)
        //   2. Front-camera mirror (flip screen_x):
        //        screen_x = (1 - y_mp) * W
        //        screen_y =  x_mp      * scaledH      ← no inversion; x=0 is top
        //   3. Aspect-fill vertical crop:
        //        scaledH  = W * (1280 / 720)
        //        cropTop  = (scaledH - H) / 2
        //        screen_y -= cropTop
        let bufAspect: CGFloat = 1280.0 / 720.0
        let scaledH = size.width * bufAspect
        let cropTop = max(0, (scaledH - size.height) / 2)

        func pt(_ lm: PoseSnapshot.Landmark) -> CGPoint {
            CGPoint(
                x: CGFloat(lm.y) * size.width,
                y: CGFloat(lm.x) * scaledH - cropTop
            )
        }

        // Draw skeleton connections first (behind dots)
        for (i, j) in Self.connections {
            guard i < landmarks.count, j < landmarks.count,
                  let a = landmarks[i], let b = landmarks[j] else { continue }
            var path = Path()
            path.move(to: pt(a))
            path.addLine(to: pt(b))
            ctx.stroke(path, with: .color(.cyan.opacity(0.8)), lineWidth: 2)
        }

        // Draw landmark dots
        for (idx, lm) in landmarks.enumerated() {
            guard let lm = lm else { continue }
            let p = pt(lm)
            let r: CGFloat = 5
            let color: Color = lm.visibility > 0.7 ? .green :
                               lm.visibility > 0.3 ? .yellow : .red
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)),
                     with: .color(color))
            if showLandmarkIndices {
                ctx.draw(Text("\(idx)").font(.system(size: 8)).foregroundColor(.white),
                         at: CGPoint(x: p.x + 8, y: p.y))
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
                VStack(alignment: .leading, spacing: 2) {
                    // Confirmed (stable) — never clears
                    HStack(spacing: 4) {
                        Text("✓").font(.system(size: 10)).foregroundColor(.green.opacity(0.7))
                        Text(confirmedEvent == .none ? "neutral" : confirmedEvent.displayName)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(confirmedEvent == .none ? .gray : .green)
                    }
                    // Flash (momentary currentEvent — lit when just fired)
                    if currentEvent != .none {
                        Text("⚡ \(currentEvent.displayName)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.yellow)
                    }
                }

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
                confirmedEvent: .leanLeft,
                fps: 29.8
            )
        }
    }
}
#endif
