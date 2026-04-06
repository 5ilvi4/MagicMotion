// HandFeatureExtractor.swift
// MagicMotion
//
// Kinivi-style feature preparation for one HandSnapshot frame.
//
// Two outputs per frame:
//   1. normalisedLandmarks — 21 landmarks translated so wrist=origin,
//      then divided by the max absolute coordinate (scale-invariant).
//      Used by the static classifier (future).
//   2. indexTipPoint — normalised (x,y) of landmark #8 (index fingertip),
//      in the same wrist-relative space.
//      Used by the dynamic classifier (PointHistoryBuffer → swipe).
//
// Coordinate convention (MediaPipe portrait space):
//   lm.x → portrait vertical   (0 = top, 1 = bottom)
//   lm.y → portrait horizontal (0 = right, 1 = left — front camera mirror)
//   We build CGPoint(x: lm.y, y: lm.x) so x is horizontal and y is vertical,
//   which matches human intuition for swipe direction.

import CoreGraphics
import Foundation

struct HandFeatureExtractor {

    struct Features {
        /// Wrist-relative, max-normalised landmark coordinates, interleaved [x0,y0,x1,y1,...].
        /// Length 42 (21 × 2). Used for static shape classification.
        let normalisedLandmarks: [Float]

        /// Wrist-relative, max-normalised position of index fingertip (lm #8).
        /// x = horizontal (positive = right), y = vertical (positive = down).
        /// Used when the classifier needs hand-intrinsic (pose-relative) tip position.
        let indexTipPoint: CGPoint

        /// Absolute image-space position of index fingertip (lm #8).
        /// x = lm.y (horizontal, 0=left … 1=right in screen space after front-camera mirror).
        /// y = lm.x (vertical,    0=top  … 1=bottom).
        /// NOT wrist-relative. Range 0–1 in both axes.
        ///
        /// Used for the DYNAMIC point-history buffer.
        /// Kazuhito insight: swipe detection must track absolute hand motion through space,
        /// not finger position relative to wrist (which stays nearly constant during whole-hand swipes).
        let absoluteIndexTipPoint: CGPoint
    }

    /// Returns nil when wrist (lm[0]) or index tip (lm[8]) are not visible.
    static func extract(from hand: HandSnapshot) -> Features? {
        guard hand.landmarks.count == 21,
              let wrist = hand.landmarks[0],
              let indexTip = hand.landmarks[8] else { return nil }

        // ── 1. Translate so wrist is origin ───────────────────────────────
        // Use CGPoint(x: lm.y, y: lm.x) to get intuitive x=horizontal, y=vertical.
        let wristPt = CGPoint(x: CGFloat(wrist.y), y: CGFloat(wrist.x))

        var translated: [CGPoint] = hand.landmarks.map { lm -> CGPoint in
            guard let lm else { return .zero }
            let p = CGPoint(x: CGFloat(lm.y), y: CGFloat(lm.x))
            return CGPoint(x: p.x - wristPt.x, y: p.y - wristPt.y)
        }

        // ── 2. Scale: divide by max absolute coordinate ───────────────────
        let maxAbs = translated.flatMap { [abs($0.x), abs($0.y)] }.max() ?? 1
        let scale = maxAbs > 0 ? maxAbs : 1
        translated = translated.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }

        // ── 3. Flatten into [Float] for classifier ────────────────────────
        var flat: [Float] = []
        flat.reserveCapacity(42)
        for pt in translated {
            flat.append(Float(pt.x))
            flat.append(Float(pt.y))
        }

        // ── 4. Index tip in same normalised space ─────────────────────────
        let tipPt = CGPoint(
            x: CGFloat(indexTip.y - wrist.y) / scale,
            y: CGFloat(indexTip.x - wrist.x) / scale
        )

        // Absolute image-space tip position (for dynamic path).
        // lm.y → screen_x (horizontal), lm.x → screen_y (vertical). No wrist subtraction.
        let absTipPt = CGPoint(x: CGFloat(indexTip.y), y: CGFloat(indexTip.x))

        return Features(normalisedLandmarks: flat,
                        indexTipPoint: tipPt,
                        absoluteIndexTipPoint: absTipPt)
    }
}
