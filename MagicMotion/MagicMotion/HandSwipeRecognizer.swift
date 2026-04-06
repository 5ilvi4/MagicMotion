// HandSwipeRecognizer.swift
// MagicMotion
//
// HandRecognizer: detects left/right swipe from absolute image-space
// index-fingertip history, gated by a pointing static shape.
//
// This encapsulates the logic that was previously split across
// HandGestureInterpreter.process() and HandGestureClassifier.classify(dynamic:).
// HandGestureInterpreter becomes a thin confirmation/cooldown wrapper.
//
// Config keys (all optional — defaults match current classifier values):
//   "graceFrames"          Double  non-pointing frames tolerated before clearing history (default 4)
//   "cumulativeDxThreshold" Double minimum cumulative horizontal displacement (default 0.12)
//   "netDxThreshold"       Double  minimum net (start→end) horizontal displacement (default 0.08)
//   "verticalDriftRatio"   Double  max ratio of |dy| to |dx| (default 0.7)
//   "directionConsistency" Double  fraction of steps in majority direction required (default 0.65)
//   "minFillRatio"         Double  minimum buffer fill fraction before classifying (default 0.6)
//
// Debug state (read by HandGestureInterpreter for HUD):
//   currentShape   — last classified static hand shape
//   historyFill    — current point-history fill count
//   isInGrace      — true while the grace window is absorbing non-pointing frames

import Foundation

final class HandSwipeRecognizer: HandRecognizer {

    let id: RecognizerID = .handSwipe

    // MARK: - Debug state (read by interpreter for HUD)

    private(set) var currentShape: StaticHandShape = .other
    private(set) var historyFill:  Int  = 0
    private(set) var isInGrace:    Bool = false

    // MARK: - Tuning

    private var graceFrames:           Int   = 4
    private var cumulativeDxThreshold: Float = 0.12
    private var netDxThreshold:        Float = 0.08
    private var verticalDriftRatio:    Float = 0.7
    private var directionConsistency:  Float = 0.65
    private var minFillRatio:          Float = 0.6

    // MARK: - Private state

    private var pointHistory       = PointHistoryBuffer(capacity: 16)
    private var nonPointingStreak  = 0

    // MARK: - HandRecognizer

    func configure(with config: RecognizerConfig) {
        if let v = config["graceFrames"]           { graceFrames           = Int(v) }
        if let v = config["cumulativeDxThreshold"] { cumulativeDxThreshold = Float(v) }
        if let v = config["netDxThreshold"]        { netDxThreshold        = Float(v) }
        if let v = config["verticalDriftRatio"]    { verticalDriftRatio    = Float(v) }
        if let v = config["directionConsistency"]  { directionConsistency  = Float(v) }
        if let v = config["minFillRatio"]          { minFillRatio          = Float(v) }
    }

    func reset() {
        pointHistory.clear()
        nonPointingStreak = 0
        currentShape = .other
        historyFill  = 0
        isInGrace    = false
    }

    /// Returns `.handSwipeLeft` / `.handSwipeRight` when a swipe is detected,
    /// `.none` placeholder does not occur — method returns nil for no gesture.
    func process(hand: HandSnapshot) -> AppIntent? {
        guard let features = HandFeatureExtractor.extract(from: hand) else {
            reset()
            return nil
        }

        // ── Stage 1: Static shape ─────────────────────────────────────────
        let shape = HandGestureClassifier.classify(static: features.normalisedLandmarks)
        currentShape = shape

        if shape == .pointing {
            nonPointingStreak = 0
            isInGrace = false
            pointHistory.push(features.absoluteIndexTipPoint)
        } else {
            nonPointingStreak += 1
            if nonPointingStreak <= graceFrames {
                isInGrace = true
                pointHistory.push(features.absoluteIndexTipPoint)
            } else {
                isInGrace = false
                if nonPointingStreak == graceFrames + 1 {
                    pointHistory.clear()
                }
            }
        }

        historyFill = pointHistory.fillCount

        // ── Stage 2: Dynamic swipe ────────────────────────────────────────
        return classifySwipe()
    }

    // MARK: - Dynamic classifier (SWAP SLOT for CoreML)

    private func classifySwipe() -> AppIntent? {
        guard Float(pointHistory.fillCount) / Float(pointHistory.capacity) >= minFillRatio else {
            return nil
        }
        let pts = pointHistory.elements
        guard pts.count >= 2 else { return nil }

        var cumulativeDx:    Float = 0
        var cumulativeAbsDy: Float = 0
        var stepsRight = 0
        var stepsLeft  = 0

        for i in 1 ..< pts.count {
            let dx = Float(pts[i].x - pts[i-1].x)
            let dy = Float(pts[i].y - pts[i-1].y)
            cumulativeDx    += dx
            cumulativeAbsDy += abs(dy)
            if dx > 0 { stepsRight += 1 } else if dx < 0 { stepsLeft += 1 }
        }

        let totalSteps = stepsRight + stepsLeft
        guard totalSteps > 0 else { return nil }

        let consistency = Float(max(stepsRight, stepsLeft)) / Float(totalSteps)
        guard consistency        >= directionConsistency          else { return nil }
        guard abs(cumulativeDx)  >= cumulativeDxThreshold         else { return nil }

        let netDx = Float(pts.last!.x - pts.first!.x)
        guard abs(netDx)         >= netDxThreshold                else { return nil }
        guard cumulativeAbsDy    <= verticalDriftRatio * abs(cumulativeDx) else { return nil }
        guard (cumulativeDx > 0) == (netDx > 0)                  else { return nil }

        return cumulativeDx > 0 ? .handSwipeRight : .handSwipeLeft
    }
}
