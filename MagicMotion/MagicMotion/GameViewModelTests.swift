// GameViewModelTests.swift
// MagicMotion
//
// Tests for overlay state mapping in GameViewModel

import XCTest
@testable import MagicMotion

class GameViewModelTests: XCTestCase {
    func testOverlayStateMappingFromSession() {
        let session = AppSessionState()
        let vm = GameViewModel(session: session)

        // Error state
        session.setError("Camera error")
        XCTAssertEqual(vm.overlayState, .error("Camera error"))
        XCTAssertTrue(session.overlayReason.contains("Error"))

        // Calibrating
        session.setError(nil)
        session.setCalibration(.inProgress)
        session.trackingState = .searching
        XCTAssertEqual(vm.overlayState, .calibrating)
        XCTAssertTrue(session.overlayReason.contains("Calibrating"))

        // Tracking lost after calibration
        session.setCalibration(.complete)
        session.trackingState = .lost
        XCTAssertEqual(vm.overlayState, .trackingLost)
        XCTAssertTrue(session.overlayReason.contains("Tracking lost"))

        // Playing (tracking confidence high)
        session.trackingState = .tracking(confidence: 0.9)
        XCTAssertEqual(vm.overlayState, .playing)
        XCTAssertTrue(session.overlayReason.contains("Playing"))

        // Ready (not started)
        session.setCalibration(.notStarted)
        XCTAssertEqual(vm.overlayState, .ready)
        XCTAssertTrue(session.overlayReason.contains("Ready"))
    }

    func testOverlayTransitionEdgeCases() {
        let session = AppSessionState()
        let vm = GameViewModel(session: session)

        // Rapid tracking loss/recovery
        session.setCalibration(.complete)
        session.trackingState = .tracking(confidence: 0.8)
        XCTAssertEqual(vm.overlayState, .playing)
        session.trackingState = .lost
        XCTAssertEqual(vm.overlayState, .trackingLost)
        session.trackingState = .tracking(confidence: 0.7)
        XCTAssertEqual(vm.overlayState, .playing)

        // Error overrides all
        session.setError("Critical failure")
        XCTAssertEqual(vm.overlayState, .error("Critical failure"))
        XCTAssertTrue(session.overlayReason.contains("Error"))
        // Clearing error resumes correct overlay
        session.setError(nil)
        XCTAssertEqual(vm.overlayState, .playing)
    }

    func testThresholdAndDiagnosticsMapping() {
        let session = AppSessionState()
        let _ = GameViewModel(session: session)

        // Change confidence threshold and check tracking state
        session.confidenceThreshold = 0.7
        session.updateTracking(confidence: 0.8)
        XCTAssertEqual(session.trackingState, .tracking(confidence: 0.8))
        session.updateTracking(confidence: 0.6)
        XCTAssertEqual(session.trackingState, .lost)

        // Diagnostics reflect state
        session.setCalibration(.inProgress)
        session.trackingState = .tracking(confidence: 0.9)
        let diag = session.diagnostics
        XCTAssertEqual(diag.calibrationState, .inProgress)
        XCTAssertEqual(diag.trackingConfidence, 0.9)
    }
}
