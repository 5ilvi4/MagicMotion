//
//  Gesture.swift
//  MagicMotion
//
//  Defines the types of gestures we can recognize.
//

import Foundation

/// The different gestures the app can recognize from body pose.
enum Gesture: String {
    case none = "None"
    case swipeLeft = "Swipe Left"
    case swipeRight = "Swipe Right"
    case swipeUp = "Swipe Up"
    case swipeDown = "Swipe Down"
    case jump = "Jump"
}
