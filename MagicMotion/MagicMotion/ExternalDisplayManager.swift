// ExternalDisplayManager.swift
// MotionMind
//
// Layer 5 — Presentation.
// Manages a UIWindow on an external screen (HDMI / AirPlay).
// TV = kid-facing GameView.  iPad = operator surface (managed by ContentView).

import UIKit
import SwiftUI
import Combine

class ExternalDisplayManager: ObservableObject {

    // MARK: - Published

    @Published var isExternalDisplayConnected: Bool = false

    // MARK: - Private

    private var externalWindow: UIWindow?
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    // MARK: - Init / deinit

    init() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.didConnectNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let screen = notification.object as? UIScreen else { return }
            self?.isExternalDisplayConnected = true
            // ContentView observes isExternalDisplayConnected and calls connect(to:session:)
            _ = screen // silence unused warning
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.disconnect()
        }

        // Already connected at launch?
        if UIScreen.screens.count > 1 {
            isExternalDisplayConnected = true
        }
    }

    deinit {
        [connectObserver, disconnectObserver].forEach {
            if let o = $0 { NotificationCenter.default.removeObserver(o) }
        }
    }

    // MARK: - Connect / disconnect

    /// Create a UIWindow on the external screen and display ParentMonitorView on it.
    func connect(to screen: UIScreen, session: GameSession, interpreter: MotionInterpreter, cameraManager: CameraManager) {
        guard externalWindow == nil else { return }

        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        let monitorView = ParentMonitorView(
            interpreter: interpreter,
            session: session,
            cameraManager: cameraManager
        )
        window.rootViewController = UIHostingController(rootView: monitorView)
        window.makeKeyAndVisible()
        externalWindow = window
        isExternalDisplayConnected = true
        print("📺 ExternalDisplayManager: ParentMonitorView created on external screen \(screen.bounds.size)")
    }

    /// Legacy overload — shows GameView (fallback for older callers).
    func connect(to screen: UIScreen, session: GameSession) {
        guard externalWindow == nil else { return }

        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = UIHostingController(rootView: GameView(session: session))
        window.makeKeyAndVisible()
        externalWindow = window
        isExternalDisplayConnected = true
        print("📺 ExternalDisplayManager: GameView (fallback) created on external screen")
    }

    func disconnect() {
        externalWindow?.isHidden = true
        externalWindow = nil
        isExternalDisplayConnected = false
        print("📱 ExternalDisplayManager: external window removed")
    }
}
