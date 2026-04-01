// MotionInterpreter.swift
// MotionMind
//
// Layer 3 — Motion Interpreter.
// Receives PoseSnapshot stream, classifies MotionEvents with smoothing + confidence gating.
// NO MediaPipeTasksVision import.

import Foundation
import Combine

class MotionInterpreter: ObservableObject, MotionEngineDelegate {

    // MARK: - Published

    @Published var currentEvent: MotionEvent = .none

    // MARK: - Output

    var onMotionEvent: ((MotionEvent) -> Void)?

    // MARK: - Tuning (can be driven by AppSessionState in future)

    var confidenceGate: Float = 0.5       // snapshots below this are treated as .none
    var leanThreshold: Float = 0.08       // hip-to-shoulder lateral offset
    var verticalJumpThreshold: Float = 0.08
    var freezeSDThreshold: Float = 0.02   // std-dev of hipCenter.x across buffer

    // MARK: - Private state

    private var buffer = RingBuffer<PoseSnapshot>(capacity: 15)

    // Confirmation gate: event must appear this many consecutive frames before firing
    private var pendingEvent: MotionEvent = .none
    private var pendingCount: Int = 0
    private let confirmationFrames = 3

    // Cooldown between fired events
    private var lastEventTime: Date = .distantPast
    private let cooldown: TimeInterval = 0.5

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
    }

    // MARK: - Classifiers

    private func classify(latest: PoseSnapshot) -> MotionEvent {
        let frames = buffer.elements

        // --- handsUp ---
        if let lw = latest.leftWrist, let rw = latest.rightWrist,
           let ls = latest.leftShoulder, let rs = latest.rightShoulder {
            // y=0 is top: wrist y < shoulder y means wrist is ABOVE shoulder
            if lw.y < ls.y - 0.05 && rw.y < rs.y - 0.05 {
                return .handsUp
            }
        }

        // --- handsDown ---
        if let lw = latest.leftWrist, let rw = latest.rightWrist,
           let lh = latest.leftHip, let rh = latest.rightHip {
            if lw.y > lh.y && rw.y > rh.y {
                return .handsDown
            }
        }

        // --- leanLeft / leanRight ---
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
            // Publish .none immediately (clears display)
            DispatchQueue.main.async { self.currentEvent = .none }
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastEventTime) >= cooldown else { return }

        lastEventTime = now
        pendingCount = 0  // reset so the same event can re-fire after cooldown

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentEvent = event
            self.onMotionEvent?(event)
        }

        // Auto-clear display after 0.8s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.currentEvent = .none
        }
    }
}
