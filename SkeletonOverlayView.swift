// SkeletonOverlayView.swift
// Draws the 33-point MediaPipe skeleton on top of the camera preview using SwiftUI Canvas.
//
// COORDINATE SYSTEM (MediaPipe — already matches the screen, no flip needed):
//   (0, 0) = TOP-LEFT      x: 0 → 1 left to right
//   (1, 1) = BOTTOM-RIGHT  y: 0 → 1 top to bottom

import SwiftUI

struct SkeletonOverlayView: View {

    /// The latest pose data to draw. Pass nil when no person is detected.
    let poseFrame: PoseFrame?

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard let pose = poseFrame,
                      !pose.landmarks.isEmpty else { return }

                // Draw bones (lines) first, then joints (dots) on top
                drawBones(context: context, pose: pose, size: size)
                drawJoints(context: context, pose: pose, size: size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(false) // Touch events fall through to whatever is behind
        }
    }

    // MARK: - Drawing

    /// Draw neon-green lines between connected landmark pairs.
    private func drawBones(context: GraphicsContext, pose: PoseFrame, size: CGSize) {
        for (landmarkA, landmarkB) in skeletonConnections {
            guard let ptA = pose[landmarkA],
                  let ptB = pose[landmarkB] else { continue }

            let screenA = toScreen(ptA, in: size)
            let screenB = toScreen(ptB, in: size)

            var path = Path()
            path.move(to: screenA)
            path.addLine(to: screenB)

            // Line opacity = average visibility of the two endpoints
            let alpha = Double((ptA.visibility + ptB.visibility) / 2)
            context.stroke(path, with: .color(.green.opacity(alpha * 0.85)), lineWidth: 3)
        }
    }

    /// Draw a white dot at each visible landmark.
    private func drawJoints(context: GraphicsContext, pose: PoseFrame, size: CGSize) {
        for (index, lm) in pose.landmarks.enumerated() {
            guard lm.visibility > 0.5 else { continue }   // Skip low-confidence points

            let pos   = toScreen(lm, in: size)
            let alpha = Double(lm.visibility)

            // Slightly larger dots for major joints (hips, shoulders, ankles)
            let majorJoints: Set<Int> = [11, 12, 15, 16, 23, 24, 27, 28]
            let r: CGFloat = majorJoints.contains(index) ? 7 : 5

            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)

            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            context.stroke(Path(ellipseIn: rect),
                           with: .color(.green.opacity(alpha)),
                           lineWidth: 1.5)
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert MediaPipe normalised (0..1) coordinates to screen pixel coordinates.
    /// MediaPipe Y already goes top→bottom, matching the screen — no flip needed.
    private func toScreen(_ lm: LandmarkPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(lm.x) * size.width,
                y: CGFloat(lm.y) * size.height)
    }
}
