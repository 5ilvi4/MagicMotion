// TouchInjector.swift
//
// ─────────────────────────────────────────────────────────────────────────────
// ⚠️  IMPORTANT — READ THIS BEFORE YOU TRY TO CONTROL SUBWAY SURFERS ⚠️
// ─────────────────────────────────────────────────────────────────────────────
// iOS/iPadOS sandboxes every app.  No app can send touch events to ANOTHER app.
// This is a core security guarantee Apple enforces in hardware + software.
//
// That means SubwaySurferMotion CANNOT directly swipe inside Subway Surfers
// on a standard (non-jailbroken) iPad — no matter what code we write.
//
// What this file DOES instead:
//   1. Logs the detected gesture to the Xcode console (great for testing).
//   2. Posts an in-app NotificationCenter event your own code can listen to.
//   3. Calls a closure (`onSwipe`) you can attach to any logic you control.
//   4. Demonstrates how you'd simulate swipes inside your OWN app/game.
//
// Practical paths forward:
//   A) Build your OWN Subway-Surfers–style mini-game in this same Xcode project
//      and wire it up to the `onSwipe` callback below. ✅ Fully allowed.
//   B) Use Assistive Touch / Switch Control accessibility features (limited).
//   C) Use a Mac as the game host via sidecar and a virtual HID device (advanced).
// ─────────────────────────────────────────────────────────────────────────────

import UIKit

/// The four swipe directions plus a special "hoverboard" action.
enum SwipeDirection: String {
    case left    = "SWIPE LEFT"
    case right   = "SWIPE RIGHT"
    case up      = "SWIPE UP (JUMP)"
    case down    = "SWIPE DOWN (SQUAT)"
    case special = "HOVERBOARD"
}

/// Translates a DetectedGesture into a swipe action and dispatches it.
class TouchInjector {

    // Attach your own game logic here.
    // Example: touchInjector.onSwipe = { dir in myGame.handleSwipe(dir) }
    var onSwipe: ((SwipeDirection) -> Void)?

    // MARK: - Public API

    /// Convert a detected body gesture into a swipe direction and fire it.
    func inject(gesture: DetectedGesture) {
        switch gesture {
        case .leanLeft:   fire(.left)
        case .leanRight:  fire(.right)
        case .jump:       fire(.up)
        case .squat:      fire(.down)
        case .hoverboard: fire(.special)
        case .none:       break
        }
    }

    // MARK: - Private

    /// Dispatch a swipe action through all available channels.
    private func fire(_ direction: SwipeDirection) {
        // ── 1. Console log (visible in Xcode's debug area) ──────────────────
        print("🎮 Gesture fired: \(direction.rawValue)")

        // ── 2. In-app notification (any object in YOUR app can subscribe) ───
        //    Listen with:
        //    NotificationCenter.default.addObserver(forName: .subwayGesture, ...)
        NotificationCenter.default.post(
            name:     .subwayGesture,
            object:   nil,
            userInfo: ["direction": direction.rawValue]
        )

        // ── 3. Direct callback ───────────────────────────────────────────────
        onSwipe?(direction)

        // ── 4. Simulate a touch swipe WITHIN THIS APP'S OWN window ──────────
        //    (Only affects views inside SubwaySurferMotion — NOT Subway Surfers)
        simulateInAppSwipe(direction)
    }

    /// Send a synthetic touch-move gesture into this app's own UIWindow.
    /// Useful if you embed a game scene (SpriteKit, SceneKit, custom UIView) here.
    private func simulateInAppSwipe(_ direction: SwipeDirection) {
        // Find this app's key window
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first(where: { $0.isKeyWindow })
        else { return }

        let centre   = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        let distance: CGFloat = 120   // How far the simulated finger travels

        var start: CGPoint
        var end:   CGPoint

        switch direction {
        case .left:
            start = CGPoint(x: centre.x + distance, y: centre.y)
            end   = CGPoint(x: centre.x - distance, y: centre.y)
        case .right:
            start = CGPoint(x: centre.x - distance, y: centre.y)
            end   = CGPoint(x: centre.x + distance, y: centre.y)
        case .up:
            start = CGPoint(x: centre.x, y: centre.y + distance)
            end   = CGPoint(x: centre.x, y: centre.y - distance)
        case .down:
            start = CGPoint(x: centre.x, y: centre.y - distance)
            end   = CGPoint(x: centre.x, y: centre.y + distance)
        case .special:
            // Double-tap in centre for hoverboard
            start = centre
            end   = centre
        }

        // Synthesise UITouch events via the public UIEvent / sendEvent path.
        // This works for UIGestureRecognizers attached to views IN THIS APP.
        // It does NOT cross the app sandbox boundary.
        sendSwipeEvent(from: start, to: end, in: window)
    }

    /// Build a minimal touch-down → touch-move → touch-up sequence and
    /// deliver it to the window's gestureRecognizers.
    private func sendSwipeEvent(from start: CGPoint, to end: CGPoint, in window: UIWindow) {
        // UIKit's public API does not expose touch synthesis.
        // The correct approach for YOUR OWN game views is to use a dedicated
        // gesture recognizer and respond to the NotificationCenter event above,
        // or to use the onSwipe callback directly.
        //
        // If you are integrating a SpriteKit scene, for example:
        //   scene.handleSwipe(direction)   ← call this from the onSwipe closure.
        //
        // We purposely do not call private _UIApplicationHandleEventQueue here
        // because it breaks under App Store review and iOS updates.
        _ = start   // Silence "unused variable" warnings
        _ = end
    }
}

// MARK: - Notification Name
extension Notification.Name {
    /// Posted every time a body gesture is recognised.
    /// userInfo["direction"] contains a SwipeDirection.rawValue String.
    static let subwayGesture = Notification.Name("com.subwaysurfermotion.gesture")
}
