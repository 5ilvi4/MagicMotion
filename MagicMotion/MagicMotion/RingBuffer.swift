// RingBuffer.swift
// MotionMind
//
// Generic fixed-capacity ring buffer. Thread-unsafe — call from one queue.

import Combine
import Foundation

struct RingBuffer<T> {
    private var storage: [T?]
    private var head: Int = 0
    private(set) var count: Int = 0

    init(capacity: Int) {
        storage = Array(repeating: nil, count: capacity)
    }

    var capacity: Int { storage.count }
    var isFull: Bool { count == capacity }

    mutating func push(_ element: T) {
        storage[head] = element
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Elements in chronological order (oldest first).
    var elements: [T] {
        guard count > 0 else { return [] }
        if count < capacity {
            // Buffer not yet full — elements start at index 0
            return (0..<count).compactMap { storage[$0] }
        }
        // Full — head points to oldest
        return (0..<capacity).compactMap { storage[(head + $0) % capacity] }
    }

    var first: T? { elements.first }
    var last: T?  { elements.last }
}
