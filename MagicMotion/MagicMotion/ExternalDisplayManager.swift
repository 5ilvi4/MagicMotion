// ExternalDisplayManager.swift
// MagicMotion
//
// Layer 5 — Presentation.
// Manages a UIWindow on an external screen (HDMI / AirPlay).
//
// Canonical path: connect(to:controllerSession:interpreter:cameraManager:)
//   → HomeMonitorView — driven by ControllerSession, no GameSession dependency.
//
// Legacy demo overloads (connect(to:session:*)) are kept in the LEGACY DEMO
// section below so they compile if other demo code still references them.
// They are not called from ContentView and can be deleted with LegacyDemo/.

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
            // ContentView observes isExternalDisplayConnected and calls connect(to:controllerSession:).
            _ = screen
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.disconnect()
        }

        if UIScreen.screens.count > 1 {
            isExternalDisplayConnected = true
        }
    }

    deinit {
        [connectObserver, disconnectObserver].forEach {
            if let o = $0 { NotificationCenter.default.removeObserver(o) }
        }
    }

    // MARK: - Canonical Home connect

    /// Show HomeMonitorView on the external screen.
    /// This is the canonical MagicMotion Home connect path.
    func connect(to screen: UIScreen,
                 controllerSession: ControllerSession,
                 interpreter: MotionInterpreter,
                 cameraManager: CameraManager) {
        guard externalWindow == nil else { return }

        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        let view = HomeMonitorView(
            controllerSession: controllerSession,
            interpreter: interpreter,
            cameraManager: cameraManager
        )
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        externalWindow = window
        isExternalDisplayConnected = true
        print("📺 ExternalDisplayManager: HomeMonitorView on external screen \(screen.bounds.size)")
    }

    func disconnect() {
        externalWindow?.isHidden = true
        externalWindow = nil
        isExternalDisplayConnected = false
        print("📱 ExternalDisplayManager: external window removed")
    }

    // MARK: - LEGACY DEMO overloads
    // These are NOT called from ContentView.
    // Kept only so LegacyDemo code that may reference them still compiles.
    // Delete together with LegacyDemo/.

    @available(*, deprecated, renamed: "connect(to:controllerSession:interpreter:cameraManager:)")
    func connect(to screen: UIScreen, session: GameSession, interpreter: MotionInterpreter, cameraManager: CameraManager) {
        guard externalWindow == nil else { return }
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = UIHostingController(
            rootView: ParentMonitorView(interpreter: interpreter, session: session, cameraManager: cameraManager)
        )
        window.makeKeyAndVisible()
        externalWindow = window
        isExternalDisplayConnected = true
        print("📺 [LEGACY DEMO] ExternalDisplayManager: ParentMonitorView on external screen")
    }

    @available(*, deprecated, renamed: "connect(to:controllerSession:interpreter:cameraManager:)")
    func connect(to screen: UIScreen, session: GameSession) {
        guard externalWindow == nil else { return }
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = UIHostingController(rootView: GameView(session: session))
        window.makeKeyAndVisible()
        externalWindow = window
        isExternalDisplayConnected = true
        print("📺 [LEGACY DEMO] ExternalDisplayManager: GameView on external screen")
    }
}
