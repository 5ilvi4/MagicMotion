// CalibrationPhaseInstructionView.swift
// MagicMotion
//
// Phase-specific instruction card shown at the bottom of CalibrationOverlayView.
// Tells the child what to do right now, shows success/failure feedback,
// and surfaces framing sub-prompt when the body is not yet correctly positioned.
//
// Uses .regularMaterial so the card floats visibly over camera or list content.

import SwiftUI

struct CalibrationPhaseInstructionView: View {

    let phase: CalibrationPhase
    let framingGuidance: FramingGuidance

    var body: some View {
        VStack(spacing: 14) {

            // ── Phase icon ──────────────────────────────────────────────
            Image(systemName: phaseIcon)
                .font(.system(size: 52))
                .foregroundColor(iconColor)

            // ── Phase headline ──────────────────────────────────────────
            Text(phase.instruction)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // ── Framing sub-prompt (only during active phases) ──────────
            if isActivePhase, !framingGuidance.isReady {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill.viewfinder")
                        .font(.system(size: 13))
                    Text(framingGuidance.prompt)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(framingSubColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(framingSubBG, in: Capsule())
            }

            // ── "Hold still" nudge during neutral capture ───────────────
            if case .neutralStance = phase, framingGuidance.isReady {
                Label("Hold still", systemImage: "scope")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            // ── "Jump now!" prompt when ready and in jump phase ─────────
            if case .jump = phase, framingGuidance.isReady {
                Text("Jump now!")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.yellow)
            }

            // ── "Duck now!" prompt when ready and in squat phase ────────
            if case .squat = phase, framingGuidance.isReady {
                Text("Duck now!")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.yellow)
            }

            // ── Completion badge ────────────────────────────────────────
            if case .complete = phase {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("You're ready to play!")
                }
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.green)

                // Completed step summary
                HStack(spacing: 16) {
                    completedStep(icon: "figure.stand",       label: "Stand")
                    completedStep(icon: "figure.jumprope",    label: "Jump")
                    completedStep(icon: "figure.flexibility", label: "Duck")
                }
                .padding(.top, 4)
            }

            // ── Failure message ─────────────────────────────────────────
            if case .failed(let reason) = phase {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                    Text(reason)
                        .multilineTextAlignment(.center)
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.orange)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
        .animation(.easeInOut(duration: 0.25), value: phase)
        .animation(.easeInOut(duration: 0.2),  value: framingGuidance)
    }

    // MARK: - Helpers

    private var isActivePhase: Bool {
        switch phase {
        case .neutralStance, .jump, .squat: return true
        default: return false
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .neutralStance: return "figure.stand"
        case .jump:          return "figure.jumprope"
        case .squat:         return "figure.flexibility"
        case .complete:      return "star.fill"
        case .failed:        return "arrow.counterclockwise.circle"
        default:             return "figure.stand"
        }
    }

    private var iconColor: Color {
        switch phase {
        case .complete: return .green
        case .failed:   return .orange
        case .jump:     return .yellow
        default:        return .yellow
        }
    }

    private var framingSubColor: Color {
        framingGuidance == .noTracking ? .red : .yellow
    }

    private var framingSubBG: Color {
        framingGuidance == .noTracking ? .red.opacity(0.18) : .yellow.opacity(0.18)
    }

    private func completedStep(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.green)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CalibrationPhaseInstructionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CalibrationPhaseInstructionView(phase: .neutralStance(secondsRemaining: 3), framingGuidance: .good)
                .previewDisplayName("Neutral — ready")
            CalibrationPhaseInstructionView(phase: .jump(secondsRemaining: 2), framingGuidance: .tooClose)
                .previewDisplayName("Jump — framing off")
            CalibrationPhaseInstructionView(phase: .complete(.uncalibrated), framingGuidance: .good)
                .previewDisplayName("Complete")
            CalibrationPhaseInstructionView(phase: .failed(reason: "Try a bigger jump!"), framingGuidance: .good)
                .previewDisplayName("Failed")
        }
        .padding()
        .background(Color.gray.opacity(0.3))
        .preferredColorScheme(.dark)
    }
}
#endif
