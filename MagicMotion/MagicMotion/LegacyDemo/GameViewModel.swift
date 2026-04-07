// GameViewModel.swift
// MagicMotion — LEGACY DEMO
//
// Overlay state machine for the endless-runner demo game, driven by AppSessionState.
// This is NOT part of the MagicMotion Home controller runtime.
//
// Never wired into ContentView. Can be deleted together with AppSessionState.swift.

import Foundation
import Combine

/// Enum for overlay states
enum OverlayState: Equatable {
    case none
    case ready
    case calibrating
    case trackingLost
    case reposition
    case playing
    case error(String)
}

/// ViewModel for GameView overlays and camera preview
class GameViewModel: ObservableObject {
    @Published var overlayState: OverlayState = .ready
    @Published var showCameraPreview: Bool = true
    private var cancellables = Set<AnyCancellable>()

    init(session: AppSessionState) {
        // Subscribe to canonical app session state
        session.$error
            .sink { [weak self] error in
                if let error = error {
                    self?.overlayState = .error(error)
                    session.overlayReason = "Error: \(error)"
                }
            }
            .store(in: &cancellables)

        session.$calibrationState
            .combineLatest(session.$trackingState)
            .sink { [weak self] calibration, tracking in
                guard self?.overlayState != .error("") else { return }
                switch calibration {
                case .notStarted:
                    self?.overlayState = .ready
                    session.overlayReason = "Ready: Awaiting calibration"
                case .inProgress:
                    self?.overlayState = .calibrating
                    session.overlayReason = "Calibrating"
                case .complete:
                    switch tracking {
                    case .notReady, .searching:
                        self?.overlayState = .ready
                        session.overlayReason = "Ready: Searching for pose"
                    case .tracking(let confidence):
                        self?.overlayState = .playing
                        session.overlayReason = "Playing (confidence: \(String(format: "%.2f", confidence)))"
                    case .lost:
                        self?.overlayState = .trackingLost
                        session.overlayReason = "Tracking lost"
                    }
                }
            }
            .store(in: &cancellables)
    }
}
