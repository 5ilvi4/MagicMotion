// PoseDetectorDelegateProxy.swift
// MagicMotion
//
// Helper to bridge PoseDetector delegate errors to closures

import Foundation

class PoseDetectorDelegateProxy: NSObject, PoseDetectorDelegate {
    let onError: (Error) -> Void
    init(onError: @escaping (Error) -> Void) {
        self.onError = onError
    }
    func poseDetector(_ detector: PoseDetector, didDetect frame: PoseFrame) {}
    func poseDetector(_ detector: PoseDetector, didFailWith error: Error) {
        onError(error)
    }
}
