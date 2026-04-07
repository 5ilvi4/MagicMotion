// PauseBannerView.swift
// MagicMotion
//
// Full-screen overlay shown in ControllerModeView when the controller session is
// paused. Uses product-language messaging, not demo-game messaging.
//
// Resume button is shown when the pause reason is one the user can clear manually.
// Safety-zone and tracking-lost pauses resolve themselves as soon as the player
// moves back into frame — the Resume tap is a manual fallback for edge cases.

import SwiftUI

struct PauseBannerView: View {

    let reason: ControllerPauseReason
    let onResume: () -> Void
    let onStop: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: reason.symbolName)
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(reason.accentColor)

                Text(reason.headline)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(reason.guidance)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                HStack(spacing: 16) {
                    Button {
                        onResume()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .frame(minWidth: 130)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(reason.accentColor)

                    Button(role: .destructive) {
                        onStop()
                    } label: {
                        Label("End Session", systemImage: "xmark")
                            .frame(minWidth: 130)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(32)
        }
    }
}

// MARK: - ControllerPauseReason display helpers

extension ControllerPauseReason {

    var headline: String {
        switch self {
        case .trackingLost:        return "We lost sight of you"
        case .safetyZoneViolation: return "Take a step back"
        case .appBackgrounded:     return "Controller paused"
        }
    }

    var guidance: String {
        switch self {
        case .trackingLost:
            return "Make sure your full body is visible to the iPad camera, then tap Resume."
        case .safetyZoneViolation:
            return "You're too close to the camera. Step back until the camera can see your whole body."
        case .appBackgrounded:
            return "Return to MagicMotion to continue controlling the game."
        }
    }

    var symbolName: String {
        switch self {
        case .trackingLost:        return "eye.slash.circle"
        case .safetyZoneViolation: return "exclamationmark.triangle"
        case .appBackgrounded:     return "pause.circle"
        }
    }

    var accentColor: Color {
        switch self {
        case .trackingLost:        return .red
        case .safetyZoneViolation: return .orange
        case .appBackgrounded:     return .yellow
        }
    }
}
