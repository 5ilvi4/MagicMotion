// GameLauncher.swift
// MotionMind
//
// Launches Subway Surfers (or any game) via URL scheme.
// MotionMind stays alive in background and MediaPipe continues processing.

import UIKit
import Combine

class GameLauncher: ObservableObject {

    // MARK: - Singleton

    static let shared = GameLauncher()
    private init() {}

    // MARK: - Published State

    @Published private(set) var gameRunning: Bool = false
    @Published private(set) var gameInstalled: Bool = false

    // MARK: - URL Schemes

    private let subwaySurfersScheme = "subwaysurfers://"
    private let subwaySurfersAppStoreID = "533239571"

    // MARK: - Init

    func checkInstallation() {
        guard let url = URL(string: subwaySurfersScheme) else { return }
        gameInstalled = UIApplication.shared.canOpenURL(url)
        print("🎮 GameLauncher: Subway Surfers installed = \(gameInstalled)")
    }

    // MARK: - Public API

    /// Launch Subway Surfers. Falls back to App Store if not installed.
    func launchSubwaySurfers() {
        checkInstallation()

        if gameInstalled, let url = URL(string: subwaySurfersScheme) {
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                DispatchQueue.main.async {
                    self?.gameRunning = success
                    print("🎮 GameLauncher: launch \(success ? "✅ succeeded" : "❌ failed")")
                }
            }
        } else {
            print("🎮 GameLauncher: Subway Surfers not installed — opening App Store")
            openAppStore()
        }
    }

    /// Launch any game via a custom URL scheme.
    func launch(urlScheme: String) {
        guard let url = URL(string: urlScheme) else {
            print("🎮 GameLauncher: invalid URL scheme '\(urlScheme)'")
            return
        }
        UIApplication.shared.open(url) { [weak self] success in
            DispatchQueue.main.async {
                self?.gameRunning = success
            }
        }
    }

    /// Launch the game associated with a GameID.
    /// Falls back to App Store if not installed or URL scheme is unknown.
    func launch(game: GameID) {
        guard let scheme = game.urlScheme else {
            print("🎮 GameLauncher: no URL scheme for \(game.rawValue)")
            return
        }
        guard let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) else {
            print("🎮 GameLauncher: \(game.rawValue) not installed — opening App Store")
            let appStoreURL = "https://apps.apple.com/app/id\(game.appStoreID)"
            if let storeURL = URL(string: appStoreURL) {
                UIApplication.shared.open(storeURL)
            }
            return
        }
        UIApplication.shared.open(url) { [weak self] success in
            DispatchQueue.main.async {
                self?.gameRunning = success
                print("🎮 GameLauncher: launch \(game.rawValue) \(success ? "✅" : "❌")")
            }
        }
    }

    /// Call when the user returns to MotionMind from the game.
    func returnFromGame() {
        gameRunning = false
        BackgroundTaskManager.shared.endBackgroundProcessing()
        print("🎮 GameLauncher: returned from game — background task ended")
    }

    // MARK: - Private

    private func openAppStore() {
        let appStoreURL = "https://apps.apple.com/app/id\(subwaySurfersAppStoreID)"
        if let url = URL(string: appStoreURL) {
            UIApplication.shared.open(url)
        }
    }
}
