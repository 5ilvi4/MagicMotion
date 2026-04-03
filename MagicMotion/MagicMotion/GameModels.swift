//
//  GameModels.swift
//  MagicMotion
//
//  Game data models for the endless runner
//

import Foundation
import Combine
import SwiftUI

/// Represents the player character
class Player: ObservableObject {
    @Published var lane: Int = 1 // 0 = left, 1 = center, 2 = right
    @Published var isJumping: Bool = false
    @Published var isSliding: Bool = false
    @Published var position: CGFloat = 0 // Vertical position for jump animation
    
    let jumpHeight: CGFloat = 150
    let jumpDuration: TimeInterval = 0.6
    let slideDuration: TimeInterval = 0.6
    
    /// Move player to the left lane
    func moveLeft() {
        guard lane > 0 else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            lane -= 1
        }
    }
    
    /// Move player to the right lane
    func moveRight() {
        guard lane < 2 else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            lane += 1
        }
    }
    
    /// Make player jump
    func jump() {
        guard !isJumping && !isSliding else { return }
        isJumping = true
        
        // Animate jump
        withAnimation(.easeOut(duration: jumpDuration / 2)) {
            position = -jumpHeight
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + jumpDuration / 2) { [weak self] in
            withAnimation(.easeIn(duration: self?.jumpDuration ?? 0.6 / 2)) {
                self?.position = 0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + jumpDuration) { [weak self] in
            self?.isJumping = false
        }
    }
    
    /// Make player slide
    func slide() {
        guard !isJumping && !isSliding else { return }
        isSliding = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + slideDuration) { [weak self] in
            self?.isSliding = false
        }
    }
}

/// Obstacle types
enum ObstacleType {
    case barrier  // Jump over
    case ceiling  // Slide under
    case train    // Move left/right to avoid
}

/// Single obstacle in the game
struct Obstacle: Identifiable {
    let id = UUID()
    var lane: Int  // 0, 1, or 2
    var yPosition: CGFloat  // Distance from player
    let type: ObstacleType
}

/// Collectible coin
struct Coin: Identifiable {
    let id = UUID()
    var lane: Int
    var yPosition: CGFloat
}

/// Game state manager
class GameState: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var score: Int = 0
    @Published var distance: Int = 0
    @Published var obstacles: [Obstacle] = []
    @Published var coins: [Coin] = []
    @Published var gameOver: Bool = false
    @Published var speed: Double = 5.0
    
    var gameTimer: Timer?
    var spawnTimer: Timer?
    
    /// Start the game
    func startGame() {
        isPlaying = true
        gameOver = false
        score = 0
        distance = 0
        speed = 5.0
        obstacles = []
        coins = []
        
        // Main game loop
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateGame()
        }
        
        // Spawn obstacles and coins
        spawnTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.spawnObstacle()
            self?.spawnCoins()
        }
    }
    
    /// Stop the game
    func stopGame() {
        isPlaying = false
        gameTimer?.invalidate()
        spawnTimer?.invalidate()
        gameTimer = nil
        spawnTimer = nil
    }
    
    /// Update game state each frame
    private func updateGame() {
        // Move obstacles closer
        for i in 0..<obstacles.count {
            obstacles[i].yPosition += speed
        }
        
        // Move coins closer
        for i in 0..<coins.count {
            coins[i].yPosition += speed
        }
        
        // Remove obstacles that passed the player
        obstacles.removeAll { $0.yPosition > 1000 }
        coins.removeAll { $0.yPosition > 1000 }
        
        // Update distance and speed
        distance += 1
        if distance % 500 == 0 {
            speed += 0.5 // Increase difficulty
        }
    }
    
    /// Spawn a random obstacle
    private func spawnObstacle() {
        let randomLane = Int.random(in: 0...2)
        let randomType: ObstacleType = [.barrier, .ceiling, .train].randomElement()!
        
        obstacles.append(Obstacle(
            lane: randomLane,
            yPosition: -200,
            type: randomType
        ))
    }
    
    /// Spawn coins
    private func spawnCoins() {
        // Spawn 1-3 coins
        let coinCount = Int.random(in: 1...3)
        for _ in 0..<coinCount {
            let randomLane = Int.random(in: 0...2)
            coins.append(Coin(lane: randomLane, yPosition: -150))
        }
    }
    
    /// Check collision with obstacle
    func checkCollision(player: Player) -> Bool {
        for obstacle in obstacles {
            // Check if obstacle is at player position
            if obstacle.yPosition > 600 && obstacle.yPosition < 750 {
                // Same lane?
                if obstacle.lane == player.lane {
                    // Check if player avoided it
                    switch obstacle.type {
                    case .barrier:
                        if !player.isJumping { return true }
                    case .ceiling:
                        if !player.isSliding { return true }
                    case .train:
                        return true // Must change lanes
                    }
                }
            }
        }
        return false
    }
    
    /// Check coin collection
    func checkCoinCollection(player: Player) {
        for (index, coin) in coins.enumerated().reversed() {
            if coin.yPosition > 650 && coin.yPosition < 750 {
                if coin.lane == player.lane {
                    // Collected!
                    score += 10
                    coins.remove(at: index)
                }
            }
        }
    }
}
