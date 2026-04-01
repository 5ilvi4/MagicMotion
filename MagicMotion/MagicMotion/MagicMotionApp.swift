//
//  MagicMotionApp.swift
//  MagicMotion
//
//  Created by silvia adinda on 24/03/2026.
//

import SwiftUI

@main
struct MagicMotionApp: App {

    // Bridge UIKit app lifecycle (background tasks, scene delegate)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
