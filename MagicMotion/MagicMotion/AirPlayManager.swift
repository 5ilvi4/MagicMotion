//
//  AirPlayManager.swift
//  MagicMotion
//
//  Monitors external display connections (AirPlay, HDMI, etc.).
//

import UIKit
import Combine

/// Monitors and manages external display connections.
class AirPlayManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether an external screen (TV, monitor) is currently connected
    @Published var isExternalScreenConnected = false
    
    // MARK: - Properties
    
    private var screenObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    init() {
        setupScreenMonitoring()
        checkExternalScreen()
    }
    
    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Setup
    
    /// Start monitoring for screen connection/disconnection events
    private func setupScreenMonitoring() {
        // Listen for screen connect notifications
        screenObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.didConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkExternalScreen()
        }
        
        // Listen for screen disconnect notifications
        NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkExternalScreen()
        }
    }
    
    /// Check if any external screens are currently connected
    private func checkExternalScreen() {
        DispatchQueue.main.async { [weak self] in
            self?.isExternalScreenConnected = UIScreen.screens.count > 1
            
            if self?.isExternalScreenConnected == true {
                print("📺 External screen detected")
                self?.configureExternalDisplay()
            } else {
                print("📱 Only main screen available")
            }
        }
    }
    
    /// Configure the external display with a window
    private func configureExternalDisplay() {
        guard let externalScreen = UIScreen.screens.first(where: { $0 != UIScreen.main }) else {
            return
        }
        
        // Check if we already have a window scene for this screen
        let hasExistingScene = UIApplication.shared.connectedScenes.contains { scene in
            guard let windowScene = scene as? UIWindowScene else { return false }
            return windowScene.screen == externalScreen
        }
        
        if hasExistingScene {
            print("✅ External display already configured")
            return
        }
        
        // In a real app, you would create a UIWindowScene for the external display
        // and show your game or content there. For now, we just detect the connection.
        print("✅ External display ready for configuration")
    }
}
