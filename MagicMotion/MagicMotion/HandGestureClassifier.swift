// HandGestureClassifier.swift
// MagicMotion
//
// Kinivi-style two-stage hand gesture classifier.
//
// Stage 1 — Static shape (per-frame):
//   Rule: index extended + ring folded + pinky folded → .pointing
//   Middle finger is IGNORED — it often partially extends during real swipes.
//   This makes the gate tolerant of natural hand variation without
//   significantly increasing false-positive risk.
//   SWAP SLOT: replace classify(static:) body with a CoreML call later.
//
// Stage 2 — Dynamic swipe (temporal):
//   Uses whole-path statistics across all PointHistoryBuffer frames:
//     • cumulative signed horizontal displacement (sum of per-step dx)
//     • direction consistency: fraction of steps moving in the majority direction
//     • net displacement: start-to-end
//     • vertical drift guard: cumulative |dy| must not dominate cumulative |dx|
//   All four must pass. This is significantly more robust than start/end only.
//   SWAP SLOT: replace classify(dynamic:) body with a CoreML call later.

import Foundation

// MARK: - StaticHandShape

enum StaticHandShape: Equatable {
    case pointing   // index extended, ring+pinky folded — gates dynamic swipe
    case open       // all 4 fingers extended
    case fist       // all 4 fingers folded
    case other

    var displayName: String {
        switch self {
        case .pointing: return "Pointing"
        case .open:     return "Open"
        case .fist:     return "Fist"
        case .other:    return "Other"
        }
    }
}

// MARK: - HandGestureClassifier

struct HandGestureClassifier {

    // ── Tuning — Static ───────────────────────────────────────────────────

    /// Tip must be this far above its PIP in wrist-relative normalised space
    /// to count as "extended". Deliberately low (0.03) to avoid false .other
    /// when the hand is not perfectly still.
    private static let extensionThreshold: Float = 0.03

    // ── Tuning — Dynamic ─────────────────────────────────────────────────
    //
    // All dynamic thresholds are in ABSOLUTE IMAGE-SPACE units (0–1 per axis).
    // The point-history buffer stores absoluteIndexTipPoint (lm.y for x, lm.x for y)
    // so dx/dy values are fractions of full screen width/height.
    // Kazuhito insight: track absolute hand motion, not wrist-relative tip motion.
    //
    // Calibration reference (30 fps, typical swipe):
    //   Moderate swipe across ~25% of screen width over ~10 frames:
    //     per-step dx ≈ 0.025, cumulative ≈ 0.20, net ≈ 0.25
    //   Resting jitter: per-step |dx| ≈ 0.005, cumulative ≈ 0 (random-walk cancels)

    /// Minimum fraction of steps that must move in the majority horizontal direction.
    /// 0.65 = 65% of steps consistent. Tolerates some noise / path wobble.
    private static let directionConsistency: Float = 0.65

    /// Minimum cumulative signed horizontal displacement across all steps.
    /// In absolute image-space coordinates (0–1 = full screen width).
    /// 0.12 ≈ 12% of screen width — filters resting jitter, passes deliberate swipes.
    private static let cumulativeDxThreshold: Float = 0.12

    /// Net (start-to-end) horizontal displacement must also exceed this.
    /// Ensures the hand actually ended up in a different place, not just oscillated.
    private static let netDxThreshold: Float = 0.08

    /// Cumulative |dy| must not exceed this multiple of cumulative |dx|.
    /// 0.7: requires dx to be clearly dominant. Rejects diagonal arm motion.
    /// (Previous value 1.2 allowed near-diagonal paths.)
    private static let verticalDriftRatio: Float = 0.7

    /// Minimum buffer fill fraction before attempting dynamic classification.
    private static let minFillRatio: Float = 0.6   // 10/16 frames ≈ 0.33 s

    // ── Stage 1: Static shape ─────────────────────────────────────────────

    /// Classify the current hand shape from normalised landmark flat vector.
    /// Input: 42-element [Float] from HandFeatureExtractor.Features.normalisedLandmarks.
    /// Layout: [x0,y0, x1,y1, … x20,y20] where x=horizontal, y=vertical.
    ///
    /// SWAP SLOT: replace this body with a CoreML keypoint classifier call.
    static func classify(static features: [Float]) -> StaticHandShape {
        guard features.count == 42 else { return .other }

        // y component of each landmark is at offset [idx*2 + 1].
        // "extended" = tip.y is clearly LESS than pip.y (higher up on screen).
        func extended(tipIdx: Int, pipIdx: Int) -> Bool {
            let tipY = features[tipIdx * 2 + 1]
            let pipY = features[pipIdx * 2 + 1]
            return tipY < pipY - extensionThreshold
        }

        let indexExt  = extended(tipIdx: 8,  pipIdx: 6)
        let middleExt = extended(tipIdx: 12, pipIdx: 10)  // intentionally not used in .pointing rule
        let ringExt   = extended(tipIdx: 16, pipIdx: 14)
        let pinkyExt  = extended(tipIdx: 20, pipIdx: 18)

        // .pointing: index up, ring+pinky down. Middle is ignored.
        // This matches natural pointing posture even when middle rides up slightly.
        if indexExt && !ringExt && !pinkyExt { return .pointing }

        // .open: all four clearly extended (middle now must be up too).
        if indexExt && middleExt && ringExt && pinkyExt { return .open }

        // .fist: all four clearly folded.
        if !indexExt && !middleExt && !ringExt && !pinkyExt { return .fist }

        return .other
    }

    // ── Stage 2: Dynamic swipe ────────────────────────────────────────────

    /// Classify swipe direction from PointHistoryBuffer.
    /// Uses whole-path statistics across all buffered frames — not just start/end.
    ///
    /// Input: buffer containing absoluteIndexTipPoint values (lm.y for x, lm.x for y).
    /// All threshold units are fractions of screen width/height (0–1).
    ///
    /// SWAP SLOT: replace this body with a CoreML sequence classifier call.
    /// For a trained model, use `buffer.flatFeatureVector()` as the input —
    /// it returns bounding-box-normalised history flattened to [Float] of length capacity×2.
    static func classify(dynamic buffer: PointHistoryBuffer) -> HandGesture {
        guard Float(buffer.fillCount) / Float(buffer.capacity) >= minFillRatio else {
            return .none
        }

        // Use raw absolute-image-space elements (not bounding-box normalised).
        // Bounding-box normalisation would make a tiny tremor look identical to a large swipe.
        // We guard against noise with the cumulative-displacement threshold instead.
        let pts = buffer.elements
        guard pts.count >= 2 else { return .none }

        // ── Accumulate per-step statistics ────────────────────────────────
        var cumulativeDx: Float = 0
        var cumulativeAbsDy: Float = 0
        var stepsRight = 0
        var stepsLeft  = 0

        for i in 1 ..< pts.count {
            let dx = Float(pts[i].x - pts[i-1].x)
            let dy = Float(pts[i].y - pts[i-1].y)
            cumulativeDx  += dx
            cumulativeAbsDy += abs(dy)
            if dx > 0 { stepsRight += 1 } else if dx < 0 { stepsLeft += 1 }
        }

        let totalSteps = stepsRight + stepsLeft
        guard totalSteps > 0 else { return .none }

        // ── Direction consistency ─────────────────────────────────────────
        let majoritySteps = max(stepsRight, stepsLeft)
        let consistency = Float(majoritySteps) / Float(totalSteps)
        guard consistency >= directionConsistency else { return .none }

        // ── Cumulative signed displacement ────────────────────────────────
        guard abs(cumulativeDx) >= cumulativeDxThreshold else { return .none }

        // ── Net (start-to-end) displacement ──────────────────────────────
        let netDx = Float(pts.last!.x - pts.first!.x)
        guard abs(netDx) >= netDxThreshold else { return .none }

        // ── Vertical drift guard ──────────────────────────────────────────
        // If the path is mostly vertical (e.g. hand waving up/down), reject it.
        guard cumulativeAbsDy <= verticalDriftRatio * abs(cumulativeDx) else { return .none }

        // ── Direction must agree between cumulative and net ───────────────
        // Prevents a path that goes right-then-left-net from passing.
        guard (cumulativeDx > 0) == (netDx > 0) else { return .none }

        return cumulativeDx > 0 ? .swipeRight : .swipeLeft
    }
}
