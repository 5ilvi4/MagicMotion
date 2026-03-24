// GestureClassifier.swift
// Watches a rolling window of pose frames and classifies body gestures.
// Each gesture has its own geometric rule described in the comments below.

import Foundation
import CoreGraphics

// MARK: - Gesture Enum

/// Every gesture the app can recognise.
enum DetectedGesture: String, Equatable {
    case leanLeft   = "LEAN LEFT ←"
    case leanRight  = "LEAN RIGHT →"
    case jump       = "JUMP ↑"
    case squat      = "SQUAT / ROLL ↓"
    case hoverboard = "HOVERBOARD 🛹"
    case none       = "—"
}

// MARK: - GestureClassifier

/// Maintains a rolling history of recent PoseFrames and fires gesture events.
class GestureClassifier: ObservableObject {

    // ── Configuration ────────────────────────────────────────────────────────
    /// How many recent frames to keep (at ~30 fps this is ~333 ms of history)
    private let historySize = 10

    /// Don't re-fire the same gesture for this many seconds (prevents spamming)
    private let cooldownSeconds: TimeInterval = 0.4

    // ── State ─────────────────────────────────────────────────────────────────
    private var frameHistory:         [PoseFrame]    = []
    private var lastGestureTime:      TimeInterval   = 0
    private var wristConvergenceTimes: [TimeInterval] = []   // For hoverboard detection

    // ── Output ────────────────────────────────────────────────────────────────
    /// The gesture shown on screen right now (nil = nothing firing)
    @Published var currentGesture: DetectedGesture = .none

    /// Callback — connect this to TouchInjector in ContentView
    var onGestureDetected: ((DetectedGesture) -> Void)?

    // MARK: - Public API

    /// Feed in the latest PoseFrame. Call this from PoseDetector's callback.
    func addFrame(_ frame: PoseFrame) {
        frameHistory.append(frame)

        // Drop oldest frame if we've exceeded the history limit
        if frameHistory.count > historySize {
            frameHistory.removeFirst()
        }

        // Need at least 3 frames to measure motion
        guard frameHistory.count >= 3 else { return }

        let detected = classify()
        guard detected != .none else { return }

        // Cooldown: ignore if we just fired a gesture
        let now = CACurrentMediaTime()
        guard (now - lastGestureTime) > cooldownSeconds else { return }

        lastGestureTime = now

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentGesture = detected
            self.onGestureDetected?(detected)

            // Auto-clear the gesture label after 0.8 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.currentGesture = .none
            }
        }
    }

    // MARK: - Classifier

    /// Check gestures in priority order and return the first match.
    private func classify() -> DetectedGesture {
        if checkLeanLeft()   { return .leanLeft   }
        if checkLeanRight()  { return .leanRight  }
        if checkJump()       { return .jump       }
        if checkSquat()      { return .squat      }
        if checkHoverboard() { return .hoverboard }
        return .none
    }

    // MARK: - Individual Gesture Rules

    /// LEAN LEFT — hip midpoint X is more than 15% left of centre.
    ///
    /// Coordinate system: Vision X goes 0.0 (left edge) → 1.0 (right edge).
    /// Centre = 0.5. The front camera is mirrored, so YOUR left = larger X in Vision.
    /// 0.5 – 0.15 = 0.35 threshold.
    private func checkLeanLeft() -> Bool {
        guard let latest = frameHistory.last,
              let hipMid = latest.hipMidpoint else { return false }
        return hipMid.x < 0.35
    }

    /// LEAN RIGHT — hip midpoint X is more than 15% right of centre.
    /// 0.5 + 0.15 = 0.65 threshold.
    private func checkLeanRight() -> Bool {
        guard let latest = frameHistory.last,
              let hipMid = latest.hipMidpoint else { return false }
        return hipMid.x > 0.65
    }

    /// JUMP — both ankles rise by more than 20% of frame height over 3 consecutive frames.
    ///
    /// Vision Y: 0.0 = bottom of frame, 1.0 = top of frame.
    /// "Rising" means Y value INCREASES (ankles move toward the top of frame = upward).
    /// We compare frame[now] vs frame[3 back] — a fast enough rise = jump.
    private func checkJump() -> Bool {
        guard frameHistory.count >= 3 else { return false }

        let oldest = frameHistory[frameHistory.count - 3]
        let newest = frameHistory.last!

        guard let oldLA = oldest.leftAnkle,  let oldRA = oldest.rightAnkle,
              let newLA = newest.leftAnkle,  let newRA = newest.rightAnkle
        else { return false }

        let leftRise  = newLA.location.y - oldLA.location.y   // Positive = upward
        let rightRise = newRA.location.y - oldRA.location.y

        // Both ankles must have risen by more than 20% of frame height
        return leftRise > 0.20 && rightRise > 0.20
    }

    /// SQUAT / ROLL — hip midpoint Y drops by more than 20% over 3 consecutive frames.
    ///
    /// Vision Y: 0.0 = bottom. Hips dropping toward the floor = Y value DECREASES.
    /// oldHipY – newHipY > 0.20 means the hips fell significantly.
    private func checkSquat() -> Bool {
        guard frameHistory.count >= 3 else { return false }

        let oldest = frameHistory[frameHistory.count - 3]
        let newest = frameHistory.last!

        guard let oldLH = oldest.leftHip,  let oldRH = oldest.rightHip,
              let newLH = newest.leftHip,  let newRH = newest.rightHip
        else { return false }

        let oldMidY = (oldLH.location.y + oldRH.location.y) / 2
        let newMidY = (newLH.location.y + newRH.location.y) / 2

        // Hip midpoint dropped by more than 20% of frame height
        return (oldMidY - newMidY) > 0.20
    }

    /// HOVERBOARD — wrists converge within 10% of frame width, twice within 500 ms.
    ///
    /// The idea: if you hold your hands together (like grabbing a hoverboard), the X
    /// distance between left and right wrist becomes very small. We require this to
    /// happen TWICE in quick succession to avoid accidental triggers.
    private func checkHoverboard() -> Bool {
        guard let latest = frameHistory.last,
              let lw = latest.leftWrist,
              let rw = latest.rightWrist else { return false }

        let wristGap = abs(lw.location.x - rw.location.x)
        let now = CACurrentMediaTime()

        if wristGap < 0.10 {
            // Wrists are close right now — log the timestamp
            wristConvergenceTimes.append(now)

            // Remove timestamps older than 500 ms
            wristConvergenceTimes = wristConvergenceTimes.filter { now - $0 < 0.5 }

            // Two or more close-wrist moments within 500 ms = hoverboard gesture
            if wristConvergenceTimes.count >= 2 {
                wristConvergenceTimes.removeAll()   // Reset to avoid retriggering
                return true
            }
        }

        return false
    }
}
