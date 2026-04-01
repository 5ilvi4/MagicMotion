//
//  GameView.swift
//  MotionMind
//
//  Kid-facing game view. Consumes GameSession (FSM) + renders player, obstacles, coins.
//  Designed for both embedded (iPad) and external (TV) displays.

import SwiftUI

struct GameView: View {
    let session: GameSession

    var body: some View {
        ZStack {
            gameBackground
            
            // Render game content based on FSM state
            switch session.state {
            case .idle:
                startScreen

            case .calibrating:
                calibratingScreen

            case .countdown(let n):
                countdownScreen(n)

            case .active:
                activeGameScreen

            case .paused(let reason):
                pausedScreen(reason)

            case .roundOver:
                roundOverScreen

            case .completed(let finalScore):
                completedScreen(finalScore)
            }

            // Always-on status bar
            VStack {
                HStack {
                    Text("MotionMind").font(.caption.bold()).foregroundColor(.cyan)
                    Spacer()
                    if case .active = session.state {
                        Text("Score: \(session.player.score)").font(.caption.bold()).foregroundColor(.white)
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.7))
                Spacer()
            }
        }
        .onAppear { session.beginCalibration() }
    }

    // MARK: - Game Screens

    private var gameBackground: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.3), Color.green.opacity(0.3)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var startScreen: some View {
        VStack(spacing: 30) {
            Text("🤚 MotionMind")
                .font(.system(size: 50, weight: .black))
                .foregroundColor(.white)

            Text("Move your body. Grow your skills.")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))

            VStack(alignment: .leading, spacing: 10) {
                Label("Lean Left / Right", systemImage: "arrow.left.arrow.right")
                Label("Jump — Leap Over", systemImage: "arrow.up")
                Label("Squat — Slide Under", systemImage: "arrow.down")
            }
            .foregroundColor(.white)
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(15)

            Button(action: { session.beginCalibration() }) {
                Text("START GAME")
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)
                    .background(Color.green)
                    .cornerRadius(20)
            }

            Spacer()
        }
        .padding()
    }

    private var calibratingScreen: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(2.0)
                .tint(.cyan)

            Text("📍 Getting Ready")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Stand 3–4 feet away from the camera")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    private func countdownScreen(_ n: Int) -> some View {
        VStack(spacing: 40) {
            Text("\(n)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
                .scaleEffect(1.2)

            Text("Get Ready!")
                .font(.title.bold())
                .foregroundColor(.white)

            Spacer()
        }
        .padding()
    }

    private var activeGameScreen: some View {
        GeometryReader { geo in
            ZStack {
                roadLanes
                
                // Obstacles
                ForEach(session.player.obstacles) { obstacle in
                    ObstacleView(obstacle: obstacle)
                        .position(
                            x: laneXPosition(obstacle.lane, in: geo.size),
                            y: obstacle.yPosition
                        )
                }

                // Coins
                ForEach(session.player.coins) { coin in
                    CoinView()
                        .position(
                            x: laneXPosition(coin.lane, in: geo.size),
                            y: coin.yPosition
                        )
                }

                // Player
                PlayerView(player: session.player)
                    .position(
                        x: laneXPosition(session.player.lane, in: geo.size),
                        y: geo.size.height * 0.7 + session.player.position
                    )

                // HUD
                VStack {
                    HStack {
                        Text("Score: \(session.player.score)")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(10)

                        Spacer()

                        Text("Distance: \(session.player.distance)m")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(10)
                    }
                    .padding()
                    Spacer()
                }
            }
        }
    }

    private func pausedScreen(_ reason: String) -> some View {
        VStack(spacing: 20) {
            Text("⏸️ PAUSED")
                .font(.title.bold())
                .foregroundColor(.orange)

            Text(reason)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))

            VStack(spacing: 10) {
                Button(action: { session.resume() }) {
                    Text("RESUME")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(15)
                        .background(Color.green)
                        .cornerRadius(12)
                }

                Button(action: { session.reset() }) {
                    Text("RESET")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(15)
                        .background(Color.gray)
                        .cornerRadius(12)
                }
            }
            .padding()

            Spacer()
        }
        .padding()
    }

    private var roundOverScreen: some View {
        VStack(spacing: 30) {
            Text("GAME OVER!")
                .font(.system(size: 60, weight: .black))
                .foregroundColor(.red)

            Text("Score: \(session.player.score)")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Distance: \(session.player.distance)m")
                .font(.title2)
                .foregroundColor(.white)

            Button(action: { session.reset() }) {
                Text("PLAY AGAIN")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .cornerRadius(15)
            }

            Spacer()
        }
        .padding()
    }

    private func completedScreen(_ finalScore: Int) -> some View {
        VStack(spacing: 30) {
            Text("✅ AWESOME JOB!")
                .font(.title.bold())
                .foregroundColor(.green)

            Text("Final Score: \(finalScore)")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("You gained: \(finalScore / 100) XP")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))

            Button(action: { session.reset() }) {
                Text("NEXT ROUND")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .cornerRadius(15)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private var roadLanes: some View {
        HStack(spacing: 0) {
            ForEach(0..<3) { _ in
                Rectangle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func laneXPosition(_ lane: Int, in size: CGSize) -> CGFloat {
        let laneWidth = size.width / 3
        return laneWidth * CGFloat(lane) + laneWidth / 2
    }
}

// MARK: - Player View

struct PlayerView: View {
    let player: Player

    var body: some View {
        Text(player.isSliding ? "🧎" : "🏃")
            .font(.system(size: 60))
            .scaleEffect(player.isJumping ? 1.2 : 1.0)
    }
}

// MARK: - Obstacle View

struct ObstacleView: View {
    let obstacle: Obstacle

    var body: some View {
        Group {
            switch obstacle.type {
            case .barrier:
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 80, height: 40)
                    .overlay(Text("🚧").font(.title))
            case .ceiling:
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 80, height: 30)
                    .overlay(Text("⬇️").font(.title))
            case .train:
                Rectangle()
                    .fill(Color.purple)
                    .frame(width: 80, height: 100)
                    .overlay(Text("🚆").font(.largeTitle))
            }
        }
    }
}

// MARK: - Coin View

struct CoinView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Text("🪙")
            .font(.title)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Preview

#if DEBUG
struct GameView_Previews: PreviewProvider {
    static var previews: some View {
        GameView(session: GameSession())
            .previewDevice("iPad Air (5th generation)")
    }
}
#endif
