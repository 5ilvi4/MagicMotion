// CalibrationOverlayView.swift
// MagicMotion
//
// Child-facing calibration shell.
//
// Layout (top → bottom):
//   ① CalibrationProgressView   — step dots + countdown ring (.ultraThinMaterial)
//   ② [transparent gap]         — camera visible here + CalibrationFitGuideView ghost
//   ③ CalibrationPhaseInstructionView — instruction card (.regularMaterial)
//
// The background is a light dim (not solid black) so the camera or app content
// remains visible through the middle layer. The ghost guide and target zone
// overlay the camera feed, giving the child real-time framing feedback.
//
// Call sites: SetupView, ControllerModeView
// Inputs: phase + framingGuidance — both from CalibrationEngine

import SwiftUI

struct CalibrationOverlayView: View {

    let phase: CalibrationPhase
    let framingGuidance: FramingGuidance

    var body: some View {
        ZStack(alignment: .top) {

            // ── Dim layer — transparent enough to see camera through ─────
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── ① Progress bar ───────────────────────────────────────
                CalibrationProgressView(phase: phase)
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                Spacer()

                // ── ② Ghost fit guide (transparent — camera shows here) ──
                CalibrationFitGuideView(
                    framingGuidance: framingGuidance,
                    phase: phase
                )

                Spacer()

                // ── ③ Phase instruction card ─────────────────────────────
                CalibrationPhaseInstructionView(
                    phase: phase,
                    framingGuidance: framingGuidance
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: phase)
    }
}

// MARK: - Preview

#if DEBUG
struct CalibrationOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CalibrationOverlayView(
                phase: .neutralStance(secondsRemaining: 3),
                framingGuidance: .tooLeft
            )
            .previewDisplayName("Neutral — framing off")

            CalibrationOverlayView(
                phase: .jump(secondsRemaining: 2),
                framingGuidance: .good
            )
            .previewDisplayName("Jump — ready")

            CalibrationOverlayView(
                phase: .squat(secondsRemaining: 1),
                framingGuidance: .good
            )
            .previewDisplayName("Squat — last second")

            CalibrationOverlayView(
                phase: .complete(.uncalibrated),
                framingGuidance: .good
            )
            .previewDisplayName("Complete")

            CalibrationOverlayView(
                phase: .failed(reason: "Try a bigger jump next time!"),
                framingGuidance: .good
            )
            .previewDisplayName("Failed")
        }
        .background(
            // Simulate camera beneath the overlay
            LinearGradient(colors: [.teal.opacity(0.6), .indigo.opacity(0.4)],
                           startPoint: .top, endPoint: .bottom)
        )
        .preferredColorScheme(.dark)
    }
}
#endif
