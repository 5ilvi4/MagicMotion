//
//  TouchInjector.swift
//  MagicMotion
//
//  Converts detected gestures into touch events for the external display.
//

import UIKit

/// Injects touch events to simulate swipes and taps based on gestures.
class TouchInjector {
    
    // MARK: - Properties
    
    /// The external window where we'll inject touches (if TV is connected)
    private weak var targetWindow: UIWindow?
    
    // MARK: - Public Methods
    
    /// Inject a touch event for the given gesture
    func inject(gesture: Gesture) {
        print("🎯 Injecting gesture: \(gesture.rawValue)")
        
        // Find the external screen's window
        guard let externalWindow = findExternalWindow() else {
            print("⚠️ No external window found - gesture ignored")
            return
        }
        
        targetWindow = externalWindow
        
        // Convert gesture to touch action
        switch gesture {
        case .swipeLeft:
            simulateSwipe(in: externalWindow, direction: .left)
        case .swipeRight:
            simulateSwipe(in: externalWindow, direction: .right)
        case .swipeUp:
            simulateSwipe(in: externalWindow, direction: .up)
        case .swipeDown:
            simulateSwipe(in: externalWindow, direction: .down)
        case .jump:
            simulateTap(in: externalWindow)
        case .none:
            break
        }
    }
    
    // MARK: - Private Methods
    
    /// Find the window on the external display
    private func findExternalWindow() -> UIWindow? {
        // Look for a window scene on an external display
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.screen != UIScreen.main,
                  let window = windowScene.windows.first else {
                continue
            }
            return window
        }
        return nil
    }
    
    /// Simulate a swipe gesture
    private func simulateSwipe(in window: UIWindow, direction: SwipeDirection) {
        let bounds = window.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        let startPoint: CGPoint
        let endPoint: CGPoint
        
        let swipeDistance: CGFloat = 200
        
        switch direction {
        case .left:
            startPoint = CGPoint(x: center.x + swipeDistance/2, y: center.y)
            endPoint = CGPoint(x: center.x - swipeDistance/2, y: center.y)
        case .right:
            startPoint = CGPoint(x: center.x - swipeDistance/2, y: center.y)
            endPoint = CGPoint(x: center.x + swipeDistance/2, y: center.y)
        case .up:
            startPoint = CGPoint(x: center.x, y: center.y + swipeDistance/2)
            endPoint = CGPoint(x: center.x, y: center.y - swipeDistance/2)
        case .down:
            startPoint = CGPoint(x: center.x, y: center.y - swipeDistance/2)
            endPoint = CGPoint(x: center.x, y: center.y + swipeDistance/2)
        }
        
        print("  Swipe from \(startPoint) to \(endPoint)")
        
        // Note: Actual touch injection requires private APIs or external libraries
        // For a production app, you'd use:
        // 1. GameController framework for game integration
        // 2. Accessibility features (if enabled by user)
        // 3. Custom server/client architecture between iPad and TV app
        
        // This is a placeholder that logs the action
        notifyExternalApp(action: "swipe", data: ["from": startPoint, "to": endPoint])
    }
    
    /// Simulate a tap gesture
    private func simulateTap(in window: UIWindow) {
        let bounds = window.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        print("  Tap at \(center)")
        
        notifyExternalApp(action: "tap", data: ["point": center])
    }
    
    /// Send notification to external app (placeholder for real implementation)
    private func notifyExternalApp(action: String, data: [String: Any]) {
        // In a real app, you could:
        // 1. Use URLSession to send HTTP requests to a server running on the TV app
        // 2. Use MultipeerConnectivity for peer-to-peer communication
        // 3. Use NotificationCenter for same-process communication
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("GestureDetected"),
                object: nil,
                userInfo: ["action": action, "data": data]
            )
        }
    }
    
    // MARK: - Helper Types
    
    private enum SwipeDirection {
        case left, right, up, down
    }
}
