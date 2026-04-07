// BackgroundTaskManager.swift
// MotionMind
//
// Keeps the app alive when backgrounded so MediaPipe + gesture detection
// + BLE writes continue uninterrupted while the kid plays Subway Surfers.

import UIKit

class BackgroundTaskManager {

    // MARK: - Singleton

    static let shared = BackgroundTaskManager()
    private init() {}

    // MARK: - Lifecycle callbacks
    // Wire these in ContentView.setupLayers() to react to app backgrounding/foregrounding.

    /// Called on the main thread when the app is about to enter the background.
    /// Use to pause any active controller session.
    var onDidEnterBackground: (() -> Void)?

    /// Called on the main thread when the app has returned to the foreground.
    /// Use to assess whether a paused session should present a resume prompt.
    var onWillEnterForeground: (() -> Void)?

    // MARK: - State

    private(set) var isInBackground = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var keepAliveTimer: Timer?

    // MARK: - Public API

    /// Call when the app moves to background (camera + MediaPipe must survive).
    func beginBackgroundProcessing() {
        guard !isInBackground else { return }
        isInBackground = true
        print("🔄 BackgroundTaskManager: starting background processing")
        DispatchQueue.main.async { [weak self] in self?.onDidEnterBackground?() }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MotionMind.KeepAlive") {
            print("⏰ BackgroundTaskManager: task expiring — renewing")
            self.renewBackgroundTask()
        }

        startKeepAliveTimer()
    }

    /// Call when the app returns to foreground.
    func endBackgroundProcessing() {
        guard isInBackground else { return }
        isInBackground = false
        print("🔄 BackgroundTaskManager: ending background processing")
        DispatchQueue.main.async { [weak self] in self?.onWillEnterForeground?() }

        stopKeepAliveTimer()

        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - Private

    /// Renew the background task before it expires (iOS allows ~30s windows).
    private func renewBackgroundTask() {
        let old = backgroundTaskID
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MotionMind.KeepAlive.Renewed") {
            self.renewBackgroundTask()
        }
        if old != .invalid {
            UIApplication.shared.endBackgroundTask(old)
        }
        print("🔄 BackgroundTaskManager: background task renewed (remaining: \(UIApplication.shared.backgroundTimeRemaining)s)")
    }

    /// Periodic no-op ping to signal the app is still doing meaningful work.
    private func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            let remaining = UIApplication.shared.backgroundTimeRemaining
            print("⏱ Background keep-alive tick — remaining: \(String(format: "%.0f", remaining))s")
            // Log a heartbeat so session data reflects continuous activity
            MotionSessionLogger.shared.logHeartbeat()
        }
    }

    private func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
}
