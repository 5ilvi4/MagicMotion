//
//  GameView.swift
//  MagicMotion
//
//  The main endless runner game view
//

import SwiftUI

struct GameView: View {
    
    @StateObject private var gameState = GameState()
    @StateObject private var player = Player()
    
    // Gesture callbacks from parent (ContentView)
    var onGestureNeeded: ((Gesture) -> Void)?
    
    var body: some View {
        ZStack {
            // Background
            gameBackground
            
            if gameState.isPlaying {
                // Game elements
                GeometryReader { geometry in
                    ZStack {
                        // Road lanes
                        roadLanes
                        
                        // Obstacles
                        ForEach(gameState.obstacles) { obstacle in
                            ObstacleView(obstacle: obstacle)
                                .position(
                                    x: laneXPosition(obstacle.lane, in: geometry.size),
                                    y: obstacle.yPosition
                                )
                        }
                        
                        // Coins
                        ForEach(gameState.coins) { coin in
                            CoinView()
                                .position(
                                    x: laneXPosition(coin.lane, in: geometry.size),
                                    y: coin.yPosition
                                )
                        }
                        
                        // Player
                        PlayerView(player: player)
                            .position(
                                x: laneXPosition(player.lane, in: geometry.size),
                                y: geometry.size.height * 0.7 + player.position
                            )
                    }
                }
                
                // HUD
                VStack {
                    HStack {
                        Text("Score: \(gameState.score)")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(10)
                        
                        Spacer()
                        
                        Text("Distance: \(gameState.distance)m")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(10)
                    }
                    .padding()
                    
                    Spacer()
                }
                
            } else if gameState.gameOver {
                // Game Over screen
                gameOverScreen
                
            } else {
                // Start screen
                startScreen
            }
        }
        .onReceive(gameState.$isPlaying) { playing in
            if playing {
                startGameLoop()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var gameBackground: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.3), Color.green.opacity(0.3)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var roadLanes: some View {
        HStack(spacing: 0) {
            ForEach(0..<3) { lane in
                Rectangle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var startScreen: some View {
        VStack(spacing: 30) {
            Text("🏃 Gesture Runner")
                .font(.system(size: 50, weight: .black))
                .foregroundColor(.white)
            
            Text("Control with your body!")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 10) {
                Label("Swipe Left/Right - Change lanes", systemImage: "arrow.left.arrow.right")
                Label("Swipe Up - Jump over barriers", systemImage: "arrow.up")
                Label("Swipe Down - Slide under ceiling", systemImage: "arrow.down")
            }
            .foregroundColor(.white)
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(15)
            
            Button(action: {
                gameState.startGame()
            }) {
                Text("START GAME")
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)
                    .background(Color.green)
                    .cornerRadius(20)
            }
        }
    }
    
    private var gameOverScreen: some View {
        VStack(spacing: 30) {
            Text("GAME OVER!")
                .font(.system(size: 60, weight: .black))
                .foregroundColor(.red)
            
            Text("Score: \(gameState.score)")
                .font(.title.bold())
                .foregroundColor(.white)
            
            Text("Distance: \(gameState.distance)m")
                .font(.title2)
                .foregroundColor(.white)
            
            Button(action: {
                gameState.gameOver = false
                gameState.startGame()
            }) {
                Text("PLAY AGAIN")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .cornerRadius(15)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(20)
    }
    
    // MARK: - Game Logic
    
    private func laneXPosition(_ lane: Int, in size: CGSize) -> CGFloat {
        let laneWidth = size.width / 3
        return laneWidth * CGFloat(lane) + laneWidth / 2
    }
    
    private func startGameLoop() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            guard gameState.isPlaying else {
                timer.invalidate()
                return
            }
            
            // Check collisions
            if gameState.checkCollision(player: player) {
                gameState.stopGame()
                gameState.gameOver = true
                timer.invalidate()
            }
            
            // Check coin collection
            gameState.checkCoinCollection(player: player)
        }
    }
    
    // MARK: - Public Methods
    
    /// Called from parent when gesture is detected
    func handleGesture(_ gesture: Gesture) {
        guard gameState.isPlaying else { return }
        
        switch gesture {
        case .swipeLeft:
            player.moveLeft()
        case .swipeRight:
            player.moveRight()
        case .swipeUp:
            player.jump()
        case .swipeDown:
            player.slide()
        case .jump:
            player.jump()
        case .none:
            break
        }
    }
}

// MARK: - Player View

struct PlayerView: View {
    @ObservedObject var player: Player
    
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
                    .overlay(
                        Text("🚧")
                            .font(.title)
                    )
            case .ceiling:
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 80, height: 30)
                    .overlay(
                        Text("⬇️")
                            .font(.title)
                    )
            case .train:
                Rectangle()
                    .fill(Color.purple)
                    .frame(width: 80, height: 100)
                    .overlay(
                        Text("🚆")
                            .font(.largeTitle)
                    )
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
        GameView()
    }
}
#endif
