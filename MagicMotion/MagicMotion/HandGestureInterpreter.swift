// HandGestureInterpreter.swift
// MagicMotion
//
// Layer 3b — Hand Gesture Interpreter.
// Thin confirmation/cooldown gate sitting above the HandRecognizer library.
//
//   HandEngine.latestHands
//     → HandSwipeRecognizer.process(hand:)  → AppIntent?
//     → confirmation gate (2 frames)
//     → cooldown (0.8 s)
//     → onHandGesture(HandGesture) → InputCoordinator
//
// Recognition logic (feature extraction, static shape, point history, dynamic
// swipe classification) now lives in HandSwipeRecognizer.
// To swap to a different recognizer: replace `swipeRecognizer` and keep this gate.
//
// Conflict suppression is handled upstream in InputCoordinator, not here.

import Combine
import Foundation

// MARK: - HandGesture

enum HandGesture: Equatable {
    case swipeLeft
    case swipeRight
    case none

    var displayName: String {
        switch self {
        case .swipeLeft:  return "Swipe Left"
        case .swipeRight: return "Swipe Right"
        case .none:       return "none"
        }
    }
}

// MARK: - HandGestureInterpreter

final class HandGestureInterpreter: ObservableObject {

    // MARK: - Published

    /// Confirmed, active gesture. Auto-clears after 0.8 s for display flash.
    @Published private(set) var currentGesture: HandGesture = .none

    /// What the dynamic classifier returned this frame (pre-confirmation).
    @Published private(set) var candidate: HandGesture = .none

    /// Consecutive matching frames accumulated toward confirmation.
    @Published private(set) var pendingCount: Int = 0

    /// Current static hand shape (updated every frame, for debug HUD).
    @Published private(set) var currentShape: StaticHandShape = .other

    /// Current history fill level (for debug HUD).
    @Published private(set) var historyFill: Int = 0

    /// True while the grace window is absorbing non-pointing frames (for debug HUD).
    @Published private(set) var isInGrace: Bool = false

    // MARK: - Output

    /// Called once per confirmed gesture on MainActor.
    var onHandGesture: ((HandGesture) -> Void)?

    // MARK: - Recognizer

    /// The active hand recognizer. Replace to swap gesture logic without changing this gate.
    private let swipeRecognizer = HandSwipeRecognizer()

    // MARK: - Tuning

    /// Consecutive matching frames required before confirming a gesture.
    private let confirmationFrames = 2

    /// Minimum seconds between confirmed gestures.
    private let cooldown: TimeInterval = 0.8

    // MARK: - Private state

    private var pendingGesture: HandGesture = .none
    private var pendingFrameCount: Int = 0
    private var lastGestureTime: Date = .distantPast
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Profile-driven configuration

    /// Apply recognizer config from the active GameProfile.
    /// Call from ContentView.setupLayers() or whenever the active game changes.
    func apply(profile: GameProfile) {
        if profile.isEnabled(.handSwipe) {
            swipeRecognizer.configure(with: profile.config(for: .handSwipe))
        } else {
            swipeRecognizer.reset()
        }
    }

    // MARK: - Wiring

    /// Subscribe to HandEngine. Call once from ContentView.setupLayers().
    func connect(to engine: HandEngine) {
        engine.$latestHands
            .receive(on: RunLoop.main)
            .sink { [weak self] hands in self?.process(hands: hands) }
            .store(in: &cancellables)
    }

    // MARK: - Per-frame processing (MainActor — called from RunLoop.main sink)

    private func process(hands: [HandSnapshot]) {
        guard let hand = hands.first else {
            swipeRecognizer.reset()
            mirrorDebugState()
            pushConfirmation(.none)
            return
        }

        let intent = swipeRecognizer.process(hand: hand)
        mirrorDebugState()

        // Convert AppIntent back to HandGesture for the confirmation gate and callback.
        // The gate and downstream (InputCoordinator) still speak HandGesture.
        let gesture: HandGesture
        switch intent {
        case .handSwipeLeft:  gesture = .swipeLeft
        case .handSwipeRight: gesture = .swipeRight
        default:              gesture = .none
        }
        pushConfirmation(gesture)
    }

    /// Sync published debug properties from the recognizer so the HUD stays live.
    private func mirrorDebugState() {
        currentShape = swipeRecognizer.currentShape
        historyFill  = swipeRecognizer.historyFill
        isInGrace    = swipeRecognizer.isInGrace
    }

    // MARK: - Confirmation + cooldown

    private func pushConfirmation(_ gesture: HandGesture) {
        if gesture == pendingGesture {
            pendingFrameCount += 1
        } else {
            pendingGesture = gesture
            pendingFrameCount = 1
        }

        candidate = pendingGesture
        pendingCount = pendingFrameCount

        guard pendingFrameCount >= confirmationFrames else { return }

        if gesture == .none {
            currentGesture = .none
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastGestureTime) >= cooldown else { return }

        lastGestureTime = now
        pendingFrameCount = 0

        // Reset the recognizer so the same swipe can't retrigger from stale history.
        swipeRecognizer.reset()

        currentGesture = gesture
        print("🖐️ [Hand] Confirmed: \(gesture.displayName)")
        onHandGesture?(gesture)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.currentGesture = .none
        }
    }
}
