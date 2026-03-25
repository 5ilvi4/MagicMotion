//
//  SkeletonOverlayView.swift
//  MagicMotion
//
//  Draws the detected skeleton on top of the camera preview.
//

import SwiftUI
import Vision

/// Draws body pose skeleton as an overlay on the camera feed.
struct SkeletonOverlayView: View {
    
    let poseFrame: PoseFrame?
    
    var body: some View {
        Canvas { context, size in
            guard let pose = poseFrame else { return }
            
            // Draw connections between joints
            drawSkeleton(context: context, size: size, pose: pose)
            
            // Draw individual joints
            drawJoints(context: context, size: size, pose: pose)
        }
    }
    
    // MARK: - Drawing
    
    /// Draw lines connecting the skeleton joints
    private func drawSkeleton(context: GraphicsContext, size: CGSize, pose: PoseFrame) {
        let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            // Spine
            (.neck, .root),
            
            // Left arm
            (.neck, .leftShoulder),
            (.leftShoulder, .leftElbow),
            (.leftElbow, .leftWrist),
            
            // Right arm
            (.neck, .rightShoulder),
            (.rightShoulder, .rightElbow),
            (.rightElbow, .rightWrist),
            
            // Left leg
            (.root, .leftHip),
            (.leftHip, .leftKnee),
            (.leftKnee, .leftAnkle),
            
            // Right leg
            (.root, .rightHip),
            (.rightHip, .rightKnee),
            (.rightKnee, .rightAnkle),
        ]
        
        for (start, end) in connections {
            guard let startPoint = pose.point(for: start),
                  let endPoint = pose.point(for: end) else {
                continue
            }
            
            // Convert normalized points (0...1) to screen coordinates
            let screenStart = convertToScreenCoordinates(startPoint, size: size)
            let screenEnd = convertToScreenCoordinates(endPoint, size: size)
            
            // Draw line
            var path = Path()
            path.move(to: screenStart)
            path.addLine(to: screenEnd)
            
            context.stroke(
                path,
                with: .color(.cyan),
                lineWidth: 3
            )
        }
    }
    
    /// Draw circles at each joint location
    private func drawJoints(context: GraphicsContext, size: CGSize, pose: PoseFrame) {
        let allJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .root,
            .leftShoulder, .leftElbow, .leftWrist,
            .rightShoulder, .rightElbow, .rightWrist,
            .leftHip, .leftKnee, .leftAnkle,
            .rightHip, .rightKnee, .rightAnkle,
            .leftEye, .rightEye, .leftEar, .rightEar
        ]
        
        for joint in allJoints {
            guard let point = pose.point(for: joint) else { continue }
            
            let screenPoint = convertToScreenCoordinates(point, size: size)
            
            let circle = Path(ellipseIn: CGRect(
                x: screenPoint.x - 6,
                y: screenPoint.y - 6,
                width: 12,
                height: 12
            ))
            
            context.fill(circle, with: .color(.yellow))
            context.stroke(circle, with: .color(.white), lineWidth: 2)
        }
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert Vision normalized coordinates (0...1, bottom-left origin) to screen coordinates
    private func convertToScreenCoordinates(_ point: CGPoint, size: CGSize) -> CGPoint {
        // Vision uses bottom-left origin, SwiftUI uses top-left
        // Also need to mirror horizontally for front camera
        return CGPoint(
            x: (1 - point.x) * size.width,  // Mirror horizontally
            y: (1 - point.y) * size.height  // Flip vertically
        )
    }
}

// MARK: - Preview

#if DEBUG
struct SkeletonOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        SkeletonOverlayView(poseFrame: nil)
            .background(Color.black)
    }
}
#endif
