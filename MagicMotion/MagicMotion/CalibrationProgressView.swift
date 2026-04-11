// CalibrationProgressView.swift
// MagicMotion
//
// Phase progress indicator: step dots (1 of 3) + animated countdown ring.
// Shown at the top of CalibrationOverlayView throughout the active flow.
//
// Uses .ultraThinMaterial so it floats over camera without fully blocking it.

import SwiftUI

struct CalibrationProgressView: View {

    let phase: CalibrationPhase

    var body: some View {
        HStack(spacing: 16) {

            // ── Step dots ────────────────────────────────────────────────
            if phase.phaseIndex > 0 {
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { i in
                        Capsule()
                            .fill(dotColor(for: i))
                            .frame(width: i == phase.phaseIndex ? 26 : 12, height: 10)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase.phaseIndex)
                    }
                }

                // Phase label
                Text("Step \(phase.phaseIndex) of 3  ·  \(phase.displayName)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // ── Countdown ring ───────────────────────────────────────────
            if let secs = phase.secondsRemaining {
                ZStack {
                    // Background track
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 5)
                        .frame(width: 52, height: 52)

                    // Animated progress arc (3 s total per phase)
                    Circle()
                        .trim(from: 0, to: CGFloat(secs) / 3.0)
                        .stroke(
                            ringColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.85), value: secs)

                    // Seconds label
                    Text("\(secs)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }

            // ── Completion checkmarks ────────────────────────────────────
            if case .complete = phase {
                HStack(spacing: 6) {
                    ForEach(0..<3) { _ in
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    // MARK: - Helpers

    private func dotColor(for index: Int) -> Color {
        if index < phase.phaseIndex  { return .green.opacity(0.8) }
        if index == phase.phaseIndex { return .yellow }
        return Color.white.opacity(0.2)
    }

    private var ringColor: Color {
        guard let secs = phase.secondsRemaining else { return .yellow }
        return secs <= 1 ? .orange : .yellow
    }
}

// MARK: - Preview

#if DEBUG
struct CalibrationProgressView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CalibrationProgressView(phase: .neutralStance(secondsRemaining: 3))
                .previewDisplayName("Neutral — 3s")
            CalibrationProgressView(phase: .jump(secondsRemaining: 1))
                .previewDisplayName("Jump — 1s")
            CalibrationProgressView(phase: .complete(.uncalibrated))
                .previewDisplayName("Complete")
        }
        .padding()
        .background(Color.gray.opacity(0.4))
        .preferredColorScheme(.dark)
    }
}
#endif
