//
//  MediaPipeGestureClassifier.swift
//  MagicMotion
//
//  Cross-platform gesture recognition using MediaPipe landmarks
//

import Foundation
import Combine

/// Enhanced gesture classifier using MediaPipe's 33 landmarks
class MediaPipeGestureClassifier: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentGesture: Gesture = .none
    
    // MARK: - Properties
    
    var onGestureDetected: ((Gesture) -> Void)?
    
    private var frameBuffer: [MediaPipePoseResult] = []
    private let maxBufferSize = 10
    
    private var lastGestureTime: Date = .distantPast
    private let gestureCooldown: TimeInterval = 0.5
    
    // MARK: - Processing
    
    func addFrame(_ frame: MediaPipePoseResult) {
        frameBuffer.append(frame)
        if frameBuffer.count > maxBufferSize {
            frameBuffer.removeFirst()
        }
        
        guard frameBuffer.count >= 5 else { return }
        guard Date().timeIntervalSince(lastGestureTime) > gestureCooldown else { return }
        
        if let gesture = detectGesture() {
            confirmGesture(gesture)
        }
    }
    
    // MARK: - Gesture Detection
    
    private func detectGesture() -> Gesture? {
        guard let firstFrame = frameBuffer.first,
              let lastFrame = frameBuffer.last else {
            return nil
        }
        
        // Enhanced detection with MediaPipe's 33 landmarks
        
        // Try hand gestures first (more specific)
        if let handGesture = detectHandGesture(first: firstFrame, last: lastFrame) {
            return handGesture
        }
        
        // Fall back to arm movement gestures
        if let armGesture = detectArmGesture(first: firstFrame, last: lastFrame) {
            return armGesture
        }
        
        // Check body movement (jump, squat, etc.)
        if let bodyGesture = detectBodyGesture(first: firstFrame, last: lastFrame) {
            return bodyGesture
        }
        
        return nil
    }
    
    // MARK: - Hand Gesture Detection (NEW with MediaPipe!)
    
    private func detectHandGesture(first: MediaPipePoseResult, last: MediaPipePoseResult) -> Gesture? {
        // We can now detect hand shapes!
        // MediaPipe gives us wrist, thumb, index, pinky positions
        
        guard let rightWrist = last.landmark(.rightWrist),
              let rightIndex = last.landmark(.rightIndex),
              let rightThumb = last.landmark(.rightThumb) else {
            return nil
        }
        
        // Check visibility
        guard rightWrist.visibility > 0.5,
              rightIndex.visibility > 0.5,
              rightThumb.visibility > 0.5 else {
            return nil
        }
        
        // Example: Detect pointing gesture
        // (Index finger extended, other fingers curled)
        let indexToWrist = distance(from: rightIndex, to: rightWrist)
        
        // More hand gestures can be added here
        // - Thumbs up/down
        // - Peace sign
        // - Fist
        // - Open palm
        
        return nil  // Placeholder for now
    }
    
    // MARK: - Arm Gesture Detection
    
    private func detectArmGesture(first: MediaPipePoseResult, last: MediaPipePoseResult) -> Gesture? {
        guard let firstWrist = first.landmark(.rightWrist),
              let lastWrist = last.landmark(.rightWrist) else {
            return nil
        }
        
        guard firstWrist.visibility > 0.5, lastWrist.visibility > 0.5 else {
            return nil
        }
        
        // Calculate movement
        let deltaX = lastWrist.x - firstWrist.x
        let deltaY = lastWrist.y - firstWrist.y
        
        let horizontalThreshold: Float = 0.15
        let verticalThreshold: Float = 0.15
        
        // Horizontal swipes
        if abs(deltaX) > horizontalThreshold && abs(deltaX) > abs(deltaY) {
            return deltaX > 0 ? .swipeRight : .swipeLeft
        }
        
        // Vertical swipes
        if abs(deltaY) > verticalThreshold && abs(deltaY) > abs(deltaX) {
            return deltaY > 0 ? .swipeDown : .swipeUp
        }
        
        return nil
    }
    
    // MARK: - Body Gesture Detection
    
    private func detectBodyGesture(first: MediaPipePoseResult, last: MediaPipePoseResult) -> Gesture? {
        // Jump detection (hip moves up significantly)
        guard let firstHip = first.landmark(.leftHip),
              let lastHip = last.landmark(.leftHip) else {
            return nil
        }
        
        guard firstHip.visibility > 0.5, lastHip.visibility > 0.5 else {
            return nil
        }
        
        let hipDeltaY = lastHip.y - firstHip.y
        if hipDeltaY < -0.12 {  // Negative Y = upward movement
            return .jump
        }
        
        // Can add more:
        // - Squat detection (knees bend)
        // - Lean left/right
        // - Arm raise
        // - T-pose
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func distance(from: MediaPipeLandmark, to: MediaPipeLandmark) -> Float {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dz = to.z - from.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    private func confirmGesture(_ gesture: Gesture) {
        DispatchQueue.main.async { [weak self] in
            self?.currentGesture = gesture
        }
        
        onGestureDetected?(gesture)
        lastGestureTime = Date()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.currentGesture = .none
        }
        
        frameBuffer.removeAll()
    }
}

// MARK: - Cross-Platform Notes

/*
 This gesture classifier is designed to be cross-platform:
 
 iOS (Swift):
 - Uses MediaPipePoseResult struct
 - Combine for @Published
 
 Android (Kotlin):
 - Port to data class MediaPipePoseResult
 - Use StateFlow for reactive updates
 
 Web (JavaScript):
 - Port to JavaScript objects
 - Use RxJS or simple callbacks
 
 The LOGIC is the same across all platforms!
 Only the language syntax changes.
 */
