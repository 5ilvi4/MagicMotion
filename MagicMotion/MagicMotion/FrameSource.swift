// FrameSource.swift
// MotionMind
//
// Protocol that decouples the rest of the app from the concrete camera.
// Enables fake/synthetic input for testing without a real camera.

import AVFoundation
import CoreMedia

/// A source that delivers video frames for pose processing.
/// Conformers: CameraManager (real camera), SyntheticFrameSource (test/fake).
protocol FrameSource: AnyObject {
    /// Called for every new frame. Deliver on any queue; callers must dispatch to main if needed.
    var onNewFrame: ((CMSampleBuffer, CGImagePropertyOrientation) -> Void)? { get set }

    /// Whether the source is currently running.
    var isRunning: Bool { get }

    /// Begin delivering frames.
    func start()

    /// Stop delivering frames.
    func stop()
}
