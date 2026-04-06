// PointHistoryBuffer.swift
// MagicMotion
//
// Fixed-size ring buffer of 2D points representing the recent trajectory
// of a single tracked landmark (index fingertip) across time.
//
// Mirrors kinivi's point_history deque (default length 16).
// Normalisation follows kinivi: translate so the first (oldest) point is origin,
// then scale by bounding box so the output is always in [-1, 1]^2.
// This makes the classifier view position-invariant and scale-invariant.

import CoreGraphics
import Foundation

struct PointHistoryBuffer {

    // MARK: - Configuration

    /// Number of frames stored. 16 frames @ ~30 fps ≈ 0.5 s of history.
    let capacity: Int

    // MARK: - Storage

    private var points: [CGPoint] = []  // oldest first
    private var head: Int = 0
    private var count: Int = 0

    init(capacity: Int = 16) {
        self.capacity = capacity
        points = Array(repeating: .zero, count: capacity)
    }

    // MARK: - Mutation

    /// Append a new point. Overwrites oldest when full.
    mutating func push(_ point: CGPoint) {
        points[head] = point
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Reset to empty.
    mutating func clear() {
        count = 0
        head = 0
        points = Array(repeating: .zero, count: capacity)
    }

    // MARK: - Query

    /// True once the buffer has collected at least `capacity` samples.
    var isFull: Bool { count == capacity }

    /// Current fill level (0…capacity).
    var fillCount: Int { count }

    /// Ordered points, oldest first.
    var elements: [CGPoint] {
        guard count > 0 else { return [] }
        if count < capacity {
            return Array(points[0..<count])
        }
        // Ring: from head (oldest) to end, then 0..<head
        let tail = Array(points[head..<capacity])
        let front = Array(points[0..<head])
        return tail + front
    }

    // MARK: - Normalisation

    /// Returns the point history normalised so that:
    ///   • the first point is translated to origin
    ///   • all coordinates are divided by the bounding-box span (max of width, height)
    /// Returns nil if there are fewer than 2 points.
    func normalisedElements() -> [CGPoint]? {
        let pts = elements
        guard pts.count >= 2 else { return nil }

        let origin = pts[0]
        let translated = pts.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }

        let xs = translated.map { $0.x }
        let ys = translated.map { $0.y }
        let xSpan = (xs.max()! - xs.min()!)
        let ySpan = (ys.max()! - ys.min()!)
        let span = max(xSpan, ySpan)
        let scale = span > 0.001 ? span : 1.0   // avoid divide-by-zero for stationary hand

        return translated.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }
    }

    /// Flattened Float array for a future CoreML classifier: [x0,y0,x1,y1,...].
    /// Length = capacity × 2. Pads with zeros when buffer not yet full.
    func flatFeatureVector() -> [Float] {
        let pts = elements
        var vec: [Float] = Array(repeating: 0, count: capacity * 2)
        if let norm = normalisedElements() {
            for (i, pt) in norm.enumerated() {
                vec[i * 2]     = Float(pt.x)
                vec[i * 2 + 1] = Float(pt.y)
            }
        }
        return vec
    }
}
