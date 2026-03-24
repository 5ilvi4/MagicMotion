// SkeletonOverlayView.swift
// Draws the 19-joint body skeleton on top of the camera preview using SwiftUI Canvas.
//
// COORDINATE SYSTEMS — important to understand:
//   Vision coords:  (0,0) = BOTTOM-LEFT of image,  Y increases UPWARD
//   Screen coords:  (0,0) = TOP-LEFT of view,       Y increases DOWNWARD
//   Conversion:     screenX = visionX * viewWidth
//                   screenY = (1 - visionY) * viewHeight   ← Y flip

import SwiftUI

struct SkeletonOverlayView: View {

    /// The latest pose data to draw. Pass nil when no person is detected.
    let poseFrame: PoseFrame?

    var body: some View {
        // GeometryReader gives us the actual pixel size of this view at runtime
        GeometryReader { geo in
            Canvas { context, size in
                guard let pose = poseFrame else { return }

                // Draw in two passes so dots always appear on top of lines
                drawBones(context: context, pose: pose, size: size)
                drawJoints(context: context, pose: pose, size: size)
            }
            // Overlay fills the whole parent view
            .frame(width: geo.size.width, height: geo.size.height)
            // IMPORTANT: let touch events fall through to whatever is behind this overlay
            .allowsHitTesting(false)
        }
    }

    // MARK: - Drawing

    /// Draw lime-green lines connecting pairs of joints (the "bones").
    private func drawBones(context: GraphicsContext, pose: PoseFrame, size: CGSize) {
        for (nameA, nameB) in PoseDetector.skeletonConnections {
            // Only draw if BOTH joints were detected with sufficient confidence
            guard let jointA = pose.joints[nameA],
                  let jointB = pose.joints[nameB] else { continue }

            let screenA = toScreen(jointA.location, in: size)
            let screenB = toScreen(jointB.location, in: size)

            var path = Path()
            path.move(to: screenA)
            path.addLine(to: screenB)

            // Use average confidence of the two joints to set line opacity
            let alpha = Double((jointA.confidence + jointB.confidence) / 2)
            context.stroke(path, with: .color(.green.opacity(alpha * 0.85)), lineWidth: 3)
        }
    }

    /// Draw a small circle at each detected joint position.
    private func drawJoints(context: GraphicsContext, pose: PoseFrame, size: CGSize) {
        for (_, joint) in pose.joints {
            let pos   = toScreen(joint.location, in: size)
            let alpha = Double(joint.confidence)
            let r: CGFloat = 6    // Dot radius in points

            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)

            // White fill (fades with confidence)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(.white.opacity(alpha))
            )
            // Green border
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(.green.opacity(alpha)),
                lineWidth: 1.5
            )
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert a Vision normalised point to a SwiftUI screen point.
    /// Vision: (0,0) = bottom-left. Screen: (0,0) = top-left.
    private func toScreen(_ visionPoint: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x:  visionPoint.x         * size.width,
            y: (1.0 - visionPoint.y)  * size.height   // Flip the Y axis
        )
    }
}

// MARK: - Preview helper (lets you see the view in Xcode Previews)
#if DEBUG
struct SkeletonOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        // No pose frame → overlay should be completely invisible
        SkeletonOverlayView(poseFrame: nil)
            .background(Color.black)
            .previewDevice("iPad Air (5th generation)")
    }
}
#endif
