// CalibrationFitGuideView.swift
// MagicMotion
//
// Ghost body guide + framing direction arrows.
// Shown in the transparent middle layer of CalibrationOverlayView so the
// child sees both the live camera and a target silhouette to align to.
//
// Inputs:
//   framingGuidance — from CalibrationEngine.framingGuidance (live, every frame)
//   phase           — drives which SF Symbols figure is shown

import SwiftUI

struct CalibrationFitGuideView: View {

    let framingGuidance: FramingGuidance
    let phase: CalibrationPhase

    // Drives the subtle jump pulse animation
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // ── Target zone — dashed border ──────────────────────────────
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    borderColor,
                    style: StrokeStyle(lineWidth: 3, dash: [12, 6])
                )
                .frame(width: 170, height: 300)
                .animation(.easeInOut(duration: 0.4), value: framingGuidance)

            // ── Ghost figure — phase-appropriate pose ────────────────────
            Image(systemName: phaseIcon)
                .font(.system(size: 110))
                .foregroundStyle(borderColor.opacity(0.45))
                .scaleEffect(pulseScale)
                .animation(.easeInOut(duration: 0.3), value: phase)

            // ── Direction arrows — tooLeft / tooRight only ───────────────
            if framingGuidance == .tooLeft {
                arrowIndicator(pointingRight: true)
            } else if framingGuidance == .tooRight {
                arrowIndicator(pointingRight: false)
            }

            // ── Framing prompt text ──────────────────────────────────────
            VStack {
                Spacer()
                Text(framingGuidance.prompt)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(promptBackground)
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                    .animation(.easeInOut(duration: 0.3), value: framingGuidance)
            }
            .frame(width: 300, height: 340)
        }
        .onAppear  { startPulseIfNeeded() }
        .onChange(of: phase) { _ in startPulseIfNeeded() }
    }

    // MARK: - Helpers

    private var phaseIcon: String {
        switch phase {
        case .neutralStance: return "figure.stand"
        case .jump:          return "figure.jumprope"
        case .squat:         return "figure.flexibility"
        case .complete:      return "figure.stand"
        default:             return "figure.stand"
        }
    }

    private var borderColor: Color {
        switch framingGuidance {
        case .good:       return .green
        case .noTracking: return .red.opacity(0.75)
        default:          return .yellow
        }
    }

    private var promptBackground: Color {
        switch framingGuidance {
        case .good:       return .green.opacity(0.75)
        case .noTracking: return .red.opacity(0.65)
        default:          return Color.black.opacity(0.55)
        }
    }

    private func arrowIndicator(pointingRight: Bool) -> some View {
        Image(systemName: pointingRight
              ? "arrow.right.circle.fill"
              : "arrow.left.circle.fill")
            .font(.system(size: 34))
            .foregroundColor(.yellow.opacity(0.9))
            .offset(x: pointingRight ? 108 : -108)
            .transition(.opacity)
    }

    // Pulse animation only during jump phase
    private func startPulseIfNeeded() {
        if case .jump = phase {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pulseScale = 1.12
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                pulseScale = 1.0
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CalibrationFitGuideView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CalibrationFitGuideView(framingGuidance: .good,    phase: .neutralStance(secondsRemaining: 2))
                .previewDisplayName("Good framing")
            CalibrationFitGuideView(framingGuidance: .tooLeft, phase: .jump(secondsRemaining: 1))
                .previewDisplayName("Too left + jump")
            CalibrationFitGuideView(framingGuidance: .noTracking, phase: .squat(secondsRemaining: 3))
                .previewDisplayName("No tracking")
        }
        .frame(width: 360, height: 400)
        .background(Color.gray.opacity(0.5))
        .preferredColorScheme(.dark)
    }
}
#endif
