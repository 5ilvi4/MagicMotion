// AppDelegate.swift
// MotionMind
//
// UIKit application delegate bridged into the SwiftUI app lifecycle.
// Responsibilities:
//   - Background task registration (keeps camera + MediaPipe alive)
//   - Scene lifecycle hooks (foreground / background transitions)

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Background Task

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - App Launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("📱 AppDelegate: application didFinishLaunching")
        return true
    }

    // MARK: - Background / Foreground Transitions

    func applicationDidEnterBackground(_ application: UIApplication) {
        print("📱 AppDelegate: entering background — requesting extended time")

        backgroundTaskID = application.beginBackgroundTask(withName: "MotionMind.BackgroundProcessing") {
            // Expiry handler — iOS is about to kill the task
            print("⚠️ Background task expiring — ending gracefully")
            application.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }

        // Notify BackgroundTaskManager
        BackgroundTaskManager.shared.beginBackgroundProcessing()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        print("📱 AppDelegate: returning to foreground")

        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        BackgroundTaskManager.shared.endBackgroundProcessing()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        print("📱 AppDelegate: terminating — flushing session log")
        MotionSessionLogger.shared.flush()
    }
}
