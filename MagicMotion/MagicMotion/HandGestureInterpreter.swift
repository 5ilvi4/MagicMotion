// HandGestureInterpreter.swift
// MagicMotion
//
// Detects hand gestures from HandEngine's MediaPipe hand landmarks.
// Runs entirely on MainActor (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
//
// Gesture: Open Palm
//   All 4 non-thumb fingertips must be clearly ABOVE their PIP joints.
//   In portrait normalized landmark space: fingertip.x < pip.x
//   (lm.x maps to portrait vertical; smaller = higher on screen.)
//
// Confirmation: 3 consecutive frames (same as MotionInterpreter).
// Cooldown:     1.0 s — slightly longer than body gesture (0.5 s) to
//               reduce double-fire when hand and body gestures overlap.
// Precedence:   suppressed while body interpreter has an active event.

import Combine
import Foundation

// MARK: - HandGesture

enum HandGesture: Equatable {
    case openPalm
    case none

    var displayName: String {
        switch self {
        case .openPalm: return "Open Palm"
        case .none:     return "none"
        }
    }
}

// MARK: - HandGestureInterpreter

final class HandGestureInterpreter: ObservableObject {

    // MARK: - Published

    /// Confirmed, active gesture (auto-clears after 0.8 s for display flash).
    @Published private(set) var currentGesture: HandGesture = .none

    /// What the classifier sees this frame — updates every frame before confirmation.
    @Published private(set) var candidate: HandGesture = .none

    /// How many consecutive matching frames have accumulated.
    @Published private(set) var pendingCount: Int = 0

    // MARK: - Output

    /// Called once per confirmed gesture on MainActor.
    var onHandGesture: ((HandGesture) -> Void)?

    /// Return true to suppress hand firing while a body gesture is active.
    /// Wired in ContentView to `interpreter.currentEvent != .none`.
    var bodyEventActive: (() -> Bool)?

    // MARK: - Tuning

    /// Minimum gap between fingertip.x and pip.x for "extended" (normalized, portrait-vertical).
    private let extensionThreshold: Float = 0.04

    /// Consecutive frames required before confirming a gesture.
    private let confirmationFrames = 3

    /// Minimum seconds between confirmed gestures.
    private let cooldown: TimeInterval = 1.0

    // MARK: - Private state

    private var pendingGesture: HandGesture = .none
    private var pendingFrameCount: Int = 0
    private var lastGestureTime: Date = .distantPast
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Wiring

    /// Subscribe to HandEngine. Call once from ContentView.setupLayers().
    func connect(to engine: HandEngine) {
        engine.$latestHands
            .receive(on: RunLoop.main)
            .sink { [weak self] hands in self?.process(hands: hands) }
            .store(in: &cancellables)
    }

    // MARK: - Processing (MainActor — called from RunLoop.main sink)

    private func process(hands: [HandSnapshot]) {
        // Use the first hand only (highest-confidence result from HandEngine).
        let gesture = hands.first.map { classify($0) } ?? .none

        // Confirmation gate
        if gesture == pendingGesture {
            pendingFrameCount += 1
        } else {
            pendingGesture = gesture
            pendingFrameCount = 1
        }

        // Update published candidate every frame for debug HUD.
        candidate = pendingGesture
        pendingCount = pendingFrameCount

        guard pendingFrameCount >= confirmationFrames else { return }

        // Confirmed .none — clear display.
        if gesture == .none {
            currentGesture = .none
            return
        }

        // Cooldown check.
        let now = Date()
        guard now.timeIntervalSince(lastGestureTime) >= cooldown else { return }

        // Precedence: do not fire while body gesture is active.
        if bodyEventActive?() == true { return }

        lastGestureTime = now
        pendingFrameCount = 0

        currentGesture = gesture
        print("🖐️ Hand gesture: \(gesture.displayName) → SPACE ↑")
        onHandGesture?(gesture)

        // Auto-clear display after 0.8 s (matches body gesture flash duration).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.currentGesture = .none
        }
    }

    // MARK: - Classifier

    private func classify(_ hand: HandSnapshot) -> HandGesture {
        let lm = hand.landmarks
        guard lm.count == 21 else { return .none }

        // lm.x = portrait vertical (0 = top of screen, 1 = bottom).
        // Extended finger: fingertip is ABOVE its PIP joint → fingertip.x < pip.x.
        // Threshold avoids triggering on partially-bent fingers.
        func extended(tip tipIdx: Int, pip pipIdx: Int) -> Bool {
            guard let tip = lm[tipIdx], let pip = lm[pipIdx] else { return false }
            return tip.x < pip.x - extensionThreshold
        }

        let extendedFingers = [
            extended(tip: 8,  pip: 6),   // index
            extended(tip: 12, pip: 10),  // middle
            extended(tip: 16, pip: 14),  // ring
            extended(tip: 20, pip: 18),  // pinky
        ].filter { $0 }.count

        // All 4 non-thumb fingers must be extended.
        return extendedFingers >= 4 ? .openPalm : .none
    }
}
