//
//  GestureClassifier.swift
//  MagicMotion
//
//  Analyzes a stream of pose frames to detect gestures.
//

import Foundation
import Vision
import Combine

/// Classifies body pose gestures from a stream of PoseFrame data.
class GestureClassifier: ObservableObject {
    
    // MARK: - Published Properties
    
    /// The currently recognized gesture (displayed in the UI)
    @Published var currentGesture: Gesture = .none
    
    // MARK: - Properties
    
    /// Callback invoked when a gesture is confirmed
    var onGestureDetected: ((Gesture) -> Void)?
    
    /// Circular buffer to store recent pose frames
    private var frameBuffer: [PoseFrame] = []
    private let maxBufferSize = 10 // Keep last 10 frames (~0.3 seconds at 30fps)
    
    /// Cooldown to prevent rapid-fire gesture detection
    private var lastGestureTime: Date = .distantPast
    private let gestureCooldown: TimeInterval = 0.5 // 500ms between gestures
    
    // MARK: - Processing
    
    /// Add a new pose frame and check for gestures
    func addFrame(_ frame: PoseFrame) {
        // Add to buffer
        frameBuffer.append(frame)
        if frameBuffer.count > maxBufferSize {
            frameBuffer.removeFirst()
        }
        
        // Need at least a few frames to detect motion
        guard frameBuffer.count >= 5 else { return }
        
        // Check if we're still in cooldown
        guard Date().timeIntervalSince(lastGestureTime) > gestureCooldown else { return }
        
        // Try to detect a gesture
        if let gesture = detectGesture() {
            confirmGesture(gesture)
        }
    }
    
    // MARK: - Gesture Detection
    
    /// Analyze the frame buffer and return a detected gesture, if any
    private func detectGesture() -> Gesture? {
        guard let firstFrame = frameBuffer.first,
              let lastFrame = frameBuffer.last else {
            return nil
        }
        
        // Get key points from first and last frames
        guard let firstWrist = firstFrame.point(for: .rightWrist),
              let lastWrist = lastFrame.point(for: .rightWrist) else {
            return nil
        }
        
        // Calculate movement delta
        let deltaX = lastWrist.x - firstWrist.x
        let deltaY = lastWrist.y - firstWrist.y
        
        // Thresholds for gesture detection (in normalized 0...1 space)
        let horizontalThreshold: CGFloat = 0.15
        let verticalThreshold: CGFloat = 0.15
        
        // Detect horizontal swipes
        if abs(deltaX) > horizontalThreshold && abs(deltaX) > abs(deltaY) {
            return deltaX > 0 ? .swipeRight : .swipeLeft
        }
        
        // Detect vertical swipes
        if abs(deltaY) > verticalThreshold && abs(deltaY) > abs(deltaX) {
            return deltaY > 0 ? .swipeUp : .swipeDown
        }
        
        // Check for jump (both feet leave ground - simplified: hip moves up significantly)
        if let firstHip = firstFrame.point(for: .root),
           let lastHip = lastFrame.point(for: .root) {
            let hipDeltaY = lastHip.y - firstHip.y
            if hipDeltaY > 0.12 {
                return .jump
            }
        }
        
        return nil
    }
    
    /// Confirm and fire a detected gesture
    private func confirmGesture(_ gesture: Gesture) {
        // Update UI on main thread
        DispatchQueue.main.async { [weak self] in
            self?.currentGesture = gesture
        }
        
        // Fire the callback
        onGestureDetected?(gesture)
        
        // Update cooldown timer
        lastGestureTime = Date()
        
        // Clear the gesture display after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.currentGesture = .none
        }
        
        // Clear buffer to start fresh
        frameBuffer.removeAll()
    }
}
