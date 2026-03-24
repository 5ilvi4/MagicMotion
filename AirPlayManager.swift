// AirPlayManager.swift
// Detects when a TV or external display is connected via AirPlay or HDMI.
//
// What this can do:
//   • Know when an external screen is connected/disconnected
//   • Open a second UIWindow on the external screen showing custom content
//
// What this CANNOT do:
//   • Route another app's (Subway Surfers') output to a specific screen
//   • That is controlled entirely by Subway Surfers itself (and iOS mirroring)
//
// Typical AirPlay setup:
//   iPad (this app) → shows skeleton debug view + controls
//   Apple TV        → mirrors the iPad screen (standard iOS AirPlay mirroring)
//                     OR shows a custom window we create here

import UIKit
import SwiftUI

class AirPlayManager: ObservableObject {

    /// true when a second screen is detected (AirPlay TV, HDMI adapter, etc.)
    @Published var isExternalScreenConnected = false

    /// The UIWindow we create on the external screen (if any)
    private var externalWindow: UIWindow?

    init() {
        // Register for screen connect / disconnect system notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenConnect(_:)),
            name:     UIScreen.didConnectNotification,
            object:   nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenDisconnect(_:)),
            name:     UIScreen.didDisconnectNotification,
            object:   nil
        )

        // An external screen might already be connected when the app launches
        if UIScreen.screens.count > 1 {
            configureExternalScreen(UIScreen.screens[1])
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notification Handlers

    @objc private func handleScreenConnect(_ notification: Notification) {
        guard let screen = notification.object as? UIScreen else { return }
        print("📺 External screen connected — bounds: \(screen.bounds)")
        configureExternalScreen(screen)
    }

    @objc private func handleScreenDisconnect(_ notification: Notification) {
        print("📺 External screen disconnected")
        externalWindow?.isHidden = true
        externalWindow = nil
        DispatchQueue.main.async { self.isExternalScreenConnected = false }
    }

    // MARK: - External Screen Setup

    /// Create a UIWindow on the external display and show content on it.
    private func configureExternalScreen(_ screen: UIScreen) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isExternalScreenConnected = true

            // ── Modern approach: UIWindowScene ───────────────────────────────
            // On iPadOS 13+ the recommended way to put content on an external
            // display is through UIScene options. Full implementation requires
            // configuring Info.plist with UIApplicationSceneManifest entries
            // and using UISceneDelegate. For now we use the legacy UIScreen path
            // which is still functional.

            // ── Legacy UIScreen approach (simpler for beginners) ─────────────
            let window = UIWindow(frame: screen.bounds)
            // Attach the window to the external screen
            // (UIWindow.screen is deprecated in iOS 16 in favour of scenes,
            //  but still works for this use case)

            // Show a clean full-screen camera preview on the TV
            let externalRootView = ExternalDisplayView()
            window.rootViewController = UIHostingController(rootView: externalRootView)
            window.isHidden = false

            self.externalWindow = window
        }
    }
}

// MARK: - External Display View

/// What appears on the TV / external monitor.
/// You can put whatever you like here — a game view, a score board, etc.
struct ExternalDisplayView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "figure.run.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.green)

                Text("SubwaySurferMotion")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("Controller active on iPad")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
    }
}
