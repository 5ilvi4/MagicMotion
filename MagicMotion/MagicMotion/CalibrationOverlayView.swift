// CalibrationOverlayView.swift
// MagicMotion
//
// Child-friendly overlay displayed during the staged body calibration flow.
// Receives a CalibrationPhase value and renders the appropriate instruction,
// countdown, and progress indicator.
//
// ContentView shows this view whenever calibrationEngine.isActive is true.
// CalibrationEngine auto-dismisses after completion / failure, so no
// dismiss button is needed here.

import SwiftUI

struct CalibrationOverlayView: View {

    let phase: CalibrationPhase

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.80)
                .ignoresSafeArea()

            VStack(spacing: 28) {

                // ── Progress dots (1 of 3 / 2 of 3 / 3 of 3) ──────────────
                if phase.phaseIndex > 0 {
                    HStack(spacing: 12) {
                        ForEach(1...3, id: \.self) { i in
                            Circle()
                                .fill(i <= phase.phaseIndex ? Color.yellow : Color.white.opacity(0.25))
                                .frame(width: 14, height: 14)
                                .animation(.easeInOut, value: phase.phaseIndex)
                        }
                    }
                }

                // ── Phase icon ─────────────────────────────────────────────
                Image(systemName: phaseIcon)
                    .font(.system(size: 80))
                    .foregroundColor(phaseColor)
                    .padding(.bottom, 4)

                // ── Phase name ─────────────────────────────────────────────
                Text(phase.displayName)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // ── Child-friendly instruction ─────────────────────────────
                Text(phase.instruction)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // ── Countdown circle ───────────────────────────────────────
                if let seconds = phase.secondsRemaining {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 7)
                            .frame(width: 90, height: 90)
                        Text("\(seconds)")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .animation(.easeInOut, value: seconds)
                }

                // ── Completion badge ───────────────────────────────────────
                if case .complete = phase {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.green)
                }

                // ── Failure state ──────────────────────────────────────────
                if case .failed = phase {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Dismissing in a moment…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(40)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    // MARK: - Helpers

    private var phaseIcon: String {
        switch phase {
        case .neutralStance: return "figure.stand"
        case .jump:          return "figure.jumprope"
        case .squat:         return "figure.flexibility"
        case .complete:      return "star.fill"
        case .failed:        return "exclamationmark.triangle"
        default:             return "figure.stand"
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .complete: return .green
        case .failed:   return .orange
        default:        return .yellow
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CalibrationOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CalibrationOverlayView(phase: .neutralStance(secondsRemaining: 2))
                .previewDisplayName("Neutral stance")
            CalibrationOverlayView(phase: .jump(secondsRemaining: 1))
                .previewDisplayName("Jump")
            CalibrationOverlayView(phase: .complete(.uncalibrated))
                .previewDisplayName("Complete")
        }
        .preferredColorScheme(.dark)
    }
}
#endif
