// GameSession.swift
// MotionMind
//
// Layer 4 — Game Runtime.
// Finite state machine + game loop. Replaces the boolean GameState.

import Foundation
import Combine
import SwiftUI

// MARK: - State types

enum GameSessionState: Equatable {
    case idle
    case calibrating
    case countdown(Int)
    case active
    case paused(reason: PauseReason)
    case roundOver(score: Int)
    case completed(score: Int)
}

enum PauseReason: Equatable {
    case trackingLost
    case appBackgrounded
}

// MARK: - GameSession

class GameSession: ObservableObject {

    // MARK: - Published

    @Published private(set) var state: GameSessionState = .idle
    @Published var score: Int = 0
    @Published var distance: Int = 0
    @Published var obstacles: [Obstacle] = []
    @Published var coins: [Coin] = []
    @Published var speed: Double = 5.0

    // Player model (owned here so GameView can observe it)
    let player = Player()

    // MARK: - Private timers

    private var gameTimer: Timer?
    private var spawnTimer: Timer?
    private var countdownTimer: Timer?

    // MARK: - State transitions (the ONLY way to mutate `state`)

    func beginCalibration() {
        guard case .idle = state else { return }
        state = .calibrating
    }

    func calibrationComplete() {
        guard case .calibrating = state else { return }
        startCountdown()
    }

    func startCountdown() {
        state = .countdown(3)
        runCountdown(from: 3)
    }

    func goActive() {
        guard case .countdown(_) = state else { return }
        state = .active
        startTimers()
    }

    func pause(reason: PauseReason) {
        guard case .active = state else { return }
        state = .paused(reason: reason)
        stopTimers()
    }

    func resume() {
        guard case .paused(_) = state else { return }
        state = .active
        startTimers()
    }

    func playerDied() {
        guard case .active = state else { return }
        stopTimers()
        state = .roundOver(score: score)
    }

    func retry() {
        resetGameData()
        startCountdown()
    }

    func reset() {
        stopTimers()
        resetGameData()
        state = .idle
    }

    // MARK: - Motion input

    func handle(event: MotionEvent) {
        guard case .active = state else { return }

        switch event {
        case .leanLeft:   player.moveLeft()
        case .leanRight:  player.moveRight()
        case .jump:       player.jump()
        case .squat:      player.slide()
        case .handsUp:    player.jump()
        case .handsDown:  player.slide()
        case .freeze, .none: break
        }
    }

    // MARK: - Private helpers

    private func runCountdown(from n: Int) {
        countdownTimer?.invalidate()
        var remaining = n
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            remaining -= 1
            if remaining <= 0 {
                t.invalidate()
                self.goActive()
            } else {
                self.state = .countdown(remaining)
            }
        }
    }

    private func startTimers() {
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateGame()
        }
        spawnTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.spawnObstacle()
            self?.spawnCoins()
        }
    }

    private func stopTimers() {
        gameTimer?.invalidate();  gameTimer  = nil
        spawnTimer?.invalidate(); spawnTimer = nil
        countdownTimer?.invalidate(); countdownTimer = nil
    }

    private func resetGameData() {
        score = 0
        distance = 0
        speed = 5.0
        obstacles = []
        coins = []
        player.lane = 1
        player.isJumping = false
        player.isSliding = false
        player.position = 0
    }

    // MARK: - Game loop

    private func updateGame() {
        for i in 0..<obstacles.count { obstacles[i].yPosition += speed }
        for i in 0..<coins.count    { coins[i].yPosition    += speed }

        obstacles.removeAll { $0.yPosition > 1000 }
        coins.removeAll     { $0.yPosition > 1000 }

        distance += 1
        if distance % 500 == 0 { speed += 0.5 }

        // Collision
        for obstacle in obstacles {
            guard obstacle.yPosition > 600 && obstacle.yPosition < 750 else { continue }
            guard obstacle.lane == player.lane else { continue }
            var hit = false
            switch obstacle.type {
            case .barrier: hit = !player.isJumping
            case .ceiling: hit = !player.isSliding
            case .train:   hit = true
            }
            if hit { playerDied(); return }
        }

        // Coin collection
        for (idx, coin) in coins.enumerated().reversed() {
            if coin.yPosition > 650 && coin.yPosition < 750 && coin.lane == player.lane {
                score += 10
                coins.remove(at: idx)
            }
        }
    }

    private func spawnObstacle() {
        obstacles.append(Obstacle(
            lane: Int.random(in: 0...2),
            yPosition: -200,
            type: [.barrier, .ceiling, .train].randomElement()!
        ))
    }

    private func spawnCoins() {
        let n = Int.random(in: 1...3)
        for _ in 0..<n {
            coins.append(Coin(lane: Int.random(in: 0...2), yPosition: -150))
        }
    }
}
