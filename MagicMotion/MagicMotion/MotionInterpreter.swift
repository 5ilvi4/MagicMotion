// MotionInterpreter.swift
// MotionMind
//
// Layer 3 — Motion Interpreter.
// Receives PoseSnapshot stream, classifies MotionEvents with smoothing + confidence gating.
// NO MediaPipeTasksVision import.

import Foundation
import Combine

// MARK: - GestureDebugInfo

/// Raw classifier inputs captured each frame for on-screen debugging.
struct GestureDebugInfo {
    var confidence: Float
    var isReliable: Bool
    var candidate: MotionEvent      // what classify() decided this frame (pre-confirmation)
    var pendingCount: Int           // frames accumulated toward confirmation
    // Raw landmark values (nil = landmark not visible)
    var leftWristY: Float?
    var rightWristY: Float?
    var leftShoulderY: Float?
    var rightShoulderY: Float?
    var leftHipY: Float?
    var rightHipY: Float?
    var hipCenterX: Float?
    var shoulderCenterX: Float?
    var leanDelta: Float?           // hipCenter.x - shoulderCenter.x
    var hipRise: Float?             // relative to oldest frame in buffer
    var hipDrop: Float?
    var timestamp: Date

    static var empty: GestureDebugInfo {
        GestureDebugInfo(confidence: 0, isReliable: false, candidate: .none,
                         pendingCount: 0, leftWristY: nil, rightWristY: nil,
                         leftShoulderY: nil, rightShoulderY: nil,
                         leftHipY: nil, rightHipY: nil,
                         hipCenterX: nil, shoulderCenterX: nil,
                         leanDelta: nil, hipRise: nil, hipDrop: nil,
                         timestamp: .distantPast)
    }
}

class MotionInterpreter: ObservableObject, MotionEngineDelegate {

    // MARK: - Published

    /// Display event — auto-clears after 0.8s. Use for momentary UI flash.
    @Published var currentEvent: MotionEvent = .none

    /// Last confirmed gesture — never auto-clears. Use for stable state display and transition logging.
    @Published private(set) var confirmedEvent: MotionEvent = .none

    /// Raw landmark values used by the last classify() call. Updated every frame.
    @Published var debugInfo: GestureDebugInfo = .empty

    // MARK: - Output

    var onMotionEvent: ((MotionEvent) -> Void)?

    // MARK: - Tuning (can be driven by AppSessionState in future)

    var confidenceGate: Float = 0.5        // snapshots below this are treated as .none
    var leanThreshold: Float = 0.08        // hip-to-shoulder lateral offset
    var verticalJumpThreshold: Float = 0.08
    var freezeSDThreshold: Float = 0.02    // std-dev of hipCenter.x across buffer
    /// Wrists must be this far BELOW hips (normalized) to fire handsDown.
    /// Natural arm-at-sides sits ~0.05–0.10 below hip; 0.15 requires a deliberate downward reach.
    var handsDownMargin: Float = 0.15

    // MARK: - Private state

    private var buffer = RingBuffer<PoseSnapshot>(capacity: 15)

    // Confirmation gate: event must appear this many consecutive frames before firing
    private var pendingEvent: MotionEvent = .none
    private var pendingCount: Int = 0
    private let confirmationFrames = 3

    // Cooldown between fired events
    private var lastEventTime: Date = .distantPast
    private let cooldown: TimeInterval = 0.5

    // Last confirmed event — separate from currentEvent which auto-clears for display.
    // Transition logging uses this so "– → gesture" doesn't repeat after every 0.8s reset.
    private var lastConfirmedEvent: MotionEvent = .none

    // Freeze tracking
    private var freezeStartTime: Date? = nil

    // MARK: - MotionEngineDelegate

    func motionEngine(_ engine: MotionEngine, didOutput snapshot: PoseSnapshot) {
        addSnapshot(snapshot)
    }

    func motionEngineDidLoseTracking(_ engine: MotionEngine) {
        pushConfirmation(.none)
    }

    // MARK: - Core

    func addSnapshot(_ snapshot: PoseSnapshot) {
        buffer.push(snapshot)

        guard buffer.count >= 5 else { return }

        let classified: MotionEvent
        if !snapshot.isReliable {
            classified = .none
        } else {
            classified = classify(latest: snapshot)
        }

        pushConfirmation(classified)

        // Publish raw debug info every frame (on main actor via DispatchQueue.main).
        let frames = buffer.elements
        let oldHip = frames.first?.hipCenter
        let nowHip = snapshot.hipCenter
        let leanDelta: Float? = {
            guard let h = snapshot.hipCenter, let s = snapshot.shoulderCenter else { return nil }
            return h.x - s.x
        }()
        let info = GestureDebugInfo(
            confidence: snapshot.trackingConfidence,
            isReliable: snapshot.isReliable,
            candidate: classified,
            pendingCount: pendingCount,
            leftWristY: snapshot.leftWrist?.y,
            rightWristY: snapshot.rightWrist?.y,
            leftShoulderY: snapshot.leftShoulder?.y,
            rightShoulderY: snapshot.rightShoulder?.y,
            leftHipY: snapshot.leftHip?.y,
            rightHipY: snapshot.rightHip?.y,
            hipCenterX: snapshot.hipCenter?.x,
            shoulderCenterX: snapshot.shoulderCenter?.x,
            leanDelta: leanDelta,
            hipRise: (oldHip != nil && nowHip != nil) ? oldHip!.y - nowHip!.y : nil,
            hipDrop: (oldHip != nil && nowHip != nil) ? nowHip!.y - oldHip!.y : nil,
            timestamp: snapshot.timestamp
        )
        DispatchQueue.main.async { [weak self] in self?.debugInfo = info }
    }

    // MARK: - Classifiers

    private func classify(latest: PoseSnapshot) -> MotionEvent {
        let frames = buffer.elements

        // --- handsUp ---
        // Checked first: deliberate bilateral raise, low false-positive risk.
        if let lw = latest.leftWrist, let rw = latest.rightWrist,
           let ls = latest.leftShoulder, let rs = latest.rightShoulder {
            // y=0 is top: wrist y < shoulder y means wrist is ABOVE shoulder
            if lw.y < ls.y - 0.05 && rw.y < rs.y - 0.05 {
                return .handsUp
            }
        }

        // --- leanLeft / leanRight ---
        // Checked before handsDown: neutral arm position (wrists at sides) used to mask
        // lean detection when handsDown was checked first. Lean is a primary game control.
        if let hip = latest.hipCenter, let shoulder = latest.shoulderCenter {
            if hip.x < shoulder.x - leanThreshold {
                return .leanLeft
            }
            if hip.x > shoulder.x + leanThreshold {
                return .leanRight
            }
        }

        // --- jump (hip rose relative to oldest frame in buffer) ---
        if frames.count >= 11,
           let oldHip = frames[0].hipCenter,
           let nowHip = latest.hipCenter {
            // y decreases upward in MediaPipe
            let hipRise = oldHip.y - nowHip.y  // positive = moved up
            if hipRise > verticalJumpThreshold {
                return .jump
            }
        }

        // --- squat (hip dropped relative to oldest frame) ---
        if frames.count >= 11,
           let oldHip = frames[0].hipCenter,
           let nowHip = latest.hipCenter {
            let hipDrop = nowHip.y - oldHip.y  // positive = moved down
            if hipDrop > verticalJumpThreshold {
                return .squat
            }
        }

        // --- handsDown ---
        // Checked last among arm/body events. Requires handsDownMargin below hips to avoid
        // firing in neutral arm-at-sides posture (~0.05–0.10 below hip in practice).
        if let lw = latest.leftWrist, let rw = latest.rightWrist,
           let lh = latest.leftHip, let rh = latest.rightHip {
            if lw.y > lh.y + handsDownMargin && rw.y > rh.y + handsDownMargin {
                return .handsDown
            }
        }

        // --- freeze (std-dev of hipCenter.x < threshold) ---
        if frames.count == buffer.capacity {
            let xs = frames.compactMap { $0.hipCenter?.x }
            if xs.count == buffer.capacity {
                let mean = xs.reduce(0, +) / Float(xs.count)
                let variance = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(xs.count)
                let sd = sqrt(variance)
                if sd < freezeSDThreshold {
                    let now = Date()
                    if freezeStartTime == nil { freezeStartTime = now }
                    let duration = now.timeIntervalSince(freezeStartTime!)
                    return .freeze(duration: duration)
                }
            }
        }

        // Reset freeze timer when body moves
        freezeStartTime = nil

        return .none
    }

    // MARK: - Confirmation + cooldown

    private func pushConfirmation(_ event: MotionEvent) {
        if event == pendingEvent {
            pendingCount += 1
        } else {
            pendingEvent = event
            pendingCount = 1
        }

        guard pendingCount >= confirmationFrames else { return }
        guard event != .none else {
            // Publish .none immediately (clears display).
            // Also reset lastConfirmedEvent so the next real gesture logs a clean transition.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.lastConfirmedEvent != .none {
                    print("🕹️ Gesture: \(self.lastConfirmedEvent.displayName) → neutral")
                    self.lastConfirmedEvent = .none
                    self.confirmedEvent = .none
                }
                self.currentEvent = .none
            }
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastEventTime) >= cooldown else { return }

        lastEventTime = now
        pendingCount = 0  // reset so the same event can re-fire after cooldown

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Log transition against lastConfirmedEvent, NOT currentEvent.
            // currentEvent auto-clears after 0.8s (display-only), so reading it would
            // produce repeated "– → gesture" entries after each reset.
            if self.lastConfirmedEvent != event {
                print("🕹️ Gesture: \(self.lastConfirmedEvent.displayName) → \(event.displayName)")
                self.lastConfirmedEvent = event
                self.confirmedEvent = event
            }
            self.currentEvent = event
            self.onMotionEvent?(event)
        }

        // Auto-clear display after 0.8s (does not affect lastConfirmedEvent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.currentEvent = .none
        }
    }
}
