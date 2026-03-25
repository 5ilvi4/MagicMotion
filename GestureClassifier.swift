// GestureClassifier.swift
// Watches a rolling window of PoseFrames and fires gesture events.
//
// COORDINATE SYSTEM REMINDER (MediaPipe):
//   x: 0.0 = left,  1.0 = right
//   y: 0.0 = TOP,   1.0 = BOTTOM   ← opposite of Apple Vision!
//
//   JUMP:  ankles Y DECREASES (moves toward top = upward)
//   SQUAT: hips   Y INCREASES (moves toward bottom = downward)

import Foundation
import CoreGraphics

// MARK: - Gesture Enum

/// Every gesture MagicMotion can recognise.
enum DetectedGesture: String, Equatable {
    case leanLeft   = "LEAN LEFT ←"
    case leanRight  = "LEAN RIGHT →"
    case jump       = "JUMP ↑"
    case squat      = "SQUAT / ROLL ↓"
    case hoverboard = "HOVERBOARD 🛹"
    case none       = "—"
}

// MARK: - GestureClassifier

/// Maintains a rolling history of recent PoseFrames and fires gesture callbacks.
class GestureClassifier: ObservableObject {

    // ── Configuration ────────────────────────────────────────────────────────

    /// Frames to keep in rolling window (~333 ms at 30 fps)
    private let historySize = 10

    /// Seconds before the same gesture can fire again (prevents spamming)
    private let cooldownSeconds: TimeInterval = 0.4

    // ── State ─────────────────────────────────────────────────────────────────
    private var frameHistory:          [PoseFrame]    = []
    private var lastGestureTime:       TimeInterval   = 0
    private var wristConvergenceTimes: [TimeInterval] = []

    // ── Output ────────────────────────────────────────────────────────────────

    /// The gesture currently shown on screen (.none = nothing)
    @Published var currentGesture: DetectedGesture = .none

    /// Connect this to TouchInjector in ContentView
    var onGestureDetected: ((DetectedGesture) -> Void)?

    // MARK: - Public API

    /// Add the latest frame and check for gestures. Call from PoseDetector's callback.
    func addFrame(_ frame: PoseFrame) {
        frameHistory.append(frame)
        if frameHistory.count > historySize { frameHistory.removeFirst() }
        guard frameHistory.count >= 3 else { return }

        let detected = classify()
        guard detected != .none else { return }

        let now = CACurrentMediaTime()
        guard (now - lastGestureTime) > cooldownSeconds else { return }

        lastGestureTime = now

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentGesture = detected
            self.onGestureDetected?(detected)

            // Auto-clear the label after 0.8 s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.currentGesture = .none
            }
        }
    }

    // MARK: - Classifier

    private func classify() -> DetectedGesture {
        if checkLeanLeft()   { return .leanLeft   }
        if checkLeanRight()  { return .leanRight  }
        if checkJump()       { return .jump       }
        if checkSquat()      { return .squat      }
        if checkHoverboard() { return .hoverboard }
        return .none
    }

    // MARK: - Gesture Rules

    /// LEAN LEFT — hip midpoint X < 0.35 (more than 15% left of centre).
    /// MediaPipe X: 0 = left, 1 = right, centre = 0.5.
    /// Front camera is mirrored, so your physical left = lower X value.
    private func checkLeanLeft() -> Bool {
        guard let latest = frameHistory.last,
              let mid = latest.hipMidpoint else { return false }
        return mid.x < 0.35
    }

    /// LEAN RIGHT — hip midpoint X > 0.65 (more than 15% right of centre).
    private func checkLeanRight() -> Bool {
        guard let latest = frameHistory.last,
              let mid = latest.hipMidpoint else { return false }
        return mid.x > 0.65
    }

    /// JUMP — both ankles Y drops by > 0.20 over 3 consecutive frames.
    /// MediaPipe Y: 0 = TOP, 1 = BOTTOM.
    /// Jumping UP means ankles move toward the TOP → Y value DECREASES.
    /// oldY - newY > 0.20 means ankles rose significantly.
    private func checkJump() -> Bool {
        guard frameHistory.count >= 3 else { return false }

        let oldest = frameHistory[frameHistory.count - 3]
        let newest = frameHistory.last!

        guard let oldLA = oldest[.leftAnkle],  let oldRA = oldest[.rightAnkle],
              let newLA = newest[.leftAnkle],  let newRA = newest[.rightAnkle]
        else { return false }

        // Positive value = ankles moved UP (Y decreased toward 0)
        let leftRise  = CGFloat(oldLA.y - newLA.y)
        let rightRise = CGFloat(oldRA.y - newRA.y)

        return leftRise > 0.20 && rightRise > 0.20
    }

    /// SQUAT / ROLL — hip midpoint Y increases by > 0.20 over 3 consecutive frames.
    /// MediaPipe Y: 0 = TOP. Squatting DOWN means hips move toward BOTTOM → Y INCREASES.
    /// newY - oldY > 0.20 means hips dropped significantly.
    private func checkSquat() -> Bool {
        guard frameHistory.count >= 3 else { return false }

        let oldest = frameHistory[frameHistory.count - 3]
        let newest = frameHistory.last!

        guard let oldLH = oldest[.leftHip],  let oldRH = oldest[.rightHip],
              let newLH = newest[.leftHip],  let newRH = newest[.rightHip]
        else { return false }

        let oldMidY = CGFloat((oldLH.y + oldRH.y) / 2)
        let newMidY = CGFloat((newLH.y + newRH.y) / 2)

        // Positive = hips moved DOWN
        return (newMidY - oldMidY) > 0.20
    }

    /// HOVERBOARD — wrists come within 10% of each other in X, twice within 500 ms.
    private func checkHoverboard() -> Bool {
        guard let latest = frameHistory.last,
              let lw = latest[.leftWrist],
              let rw = latest[.rightWrist] else { return false }

        let wristGap = abs(CGFloat(lw.x - rw.x))
        let now = CACurrentMediaTime()

        if wristGap < 0.10 {
            wristConvergenceTimes.append(now)
            wristConvergenceTimes = wristConvergenceTimes.filter { now - $0 < 0.5 }

            if wristConvergenceTimes.count >= 2 {
                wristConvergenceTimes.removeAll()
                return true
            }
        }

        return false
    }
}
