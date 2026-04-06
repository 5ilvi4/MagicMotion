// HandOverlayView.swift
// MagicMotion
//
// Draws finger joints and connections for up to 2 hands on top of the
// front-camera portrait preview.
//
// Coordinate transform is identical to DebugOverlayView:
//   screen_x = y_mp * W                        (landscape y → portrait x, no mirror)
//   screen_y = x_mp * scaledH - cropTop        (landscape x → portrait y, no invert)
//   scaledH  = W * (1280 / 720)
//   cropTop  = max(0, (scaledH - H) / 2)

import SwiftUI

struct HandOverlayView: View {
    let hands: [HandSnapshot]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard !hands.isEmpty else { return }
                let bufAspect: CGFloat = 1280.0 / 720.0
                let scaledH = size.width * bufAspect
                let cropTop = max(0, (scaledH - size.height) / 2)

                func pt(_ lm: HandSnapshot.Landmark) -> CGPoint {
                    CGPoint(
                        x: CGFloat(lm.y) * size.width,
                        y: CGFloat(lm.x) * scaledH - cropTop
                    )
                }

                for (handIdx, hand) in hands.enumerated() {
                    let lineColor: Color = .cyan

                    // ── Connections: black underlay + cyan overlay ──────────────
                    for (i, j) in handConnections {
                        guard i < hand.landmarks.count, j < hand.landmarks.count,
                              let a = hand.landmarks[i],
                              let b = hand.landmarks[j] else { continue }
                        var path = Path()
                        path.move(to: pt(a))
                        path.addLine(to: pt(b))
                        // underlay
                        ctx.stroke(path, with: .color(.black.opacity(0.85)), lineWidth: 8)
                        // overlay
                        ctx.stroke(path, with: .color(lineColor), lineWidth: 4)
                    }

                    // ── Joint dots: black outer + green inner ──────────────────
                    for (idx, lm) in hand.landmarks.enumerated() {
                        guard let lm else { continue }
                        let p = pt(lm)
                        let outerR: CGFloat = 10
                        let innerR: CGFloat = 6
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: p.x - outerR, y: p.y - outerR,
                                                   width: outerR*2, height: outerR*2)),
                            with: .color(.black)
                        )
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: p.x - innerR, y: p.y - innerR,
                                                   width: innerR*2, height: innerR*2)),
                            with: .color(.green)
                        )
                        // Fingertip labels: indices 4, 8, 12, 16, 20
                        let tipLabels: [Int: String] = [4:"T", 8:"I", 12:"M", 16:"R", 20:"P"]
                        if let label = tipLabels[idx] {
                            ctx.draw(
                                Text(label).font(.system(size: 10, weight: .black)).foregroundColor(.yellow),
                                at: CGPoint(x: p.x, y: p.y - 16)
                            )
                        }
                    }

                    // ── Wrist handedness label ─────────────────────────────────
                    if let wrist = hand.wrist {
                        let label = hand.handedness == .left ? "L" : hand.handedness == .right ? "R" : "?"
                        let p = pt(wrist)
                        ctx.draw(
                            Text(label).font(.system(size: 14, weight: .black)).foregroundColor(.cyan),
                            at: CGPoint(x: p.x, y: p.y - 20)
                        )
                    }

                    _ = handIdx
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Preview

#if DEBUG
struct HandOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            HandOverlayView(hands: [])
        }
    }
}
#endif
