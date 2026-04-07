// GameSession.swift
// MagicMotion — LEGACY DEMO
//
// Endless-runner demo game state machine and loop.
// This is NOT part of the MagicMotion Home controller runtime.
//
// Kept temporarily because:
//   - ContentView references it in the fallback debug layout (GameView)
//   - ExternalDisplayManager.connect(to:session:) accepts it for ParentMonitorView
//
// Once the external display shows ControllerSession state instead of game state,
// and the fallback layout is removed or replaced, this file can be deleted.
//
// DO NOT add new controller-runtime features here.

import Foundation
import Combine
import SwiftUI
import QuartzCore

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

@MainActor
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

    // MARK: - Private loop state

    /// CADisplayLink drives the game loop at native display refresh rate (~60 fps).
    private var displayLink: CADisplayLink?
    private var spawnTimer: Timer?
    private var countdownTimer: Timer?
    /// Frame counter for SwiftUI debatch: only publish obstacles/coins every 3rd frame.
    private var frameCount: Int = 0
    /// Shadow copies mutated every frame; pushed to @Published only on publish frames.
    private var shadowObstacles: [Obstacle] = []
    private var shadowCoins: [Coin] = []

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
        // Auto-transition to completed after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            complete()
        }
    }

    /// Transitions from roundOver → completed. Can also be called directly
    /// by a "Continue" button in GameView.
    func complete() {
        guard case .roundOver(let finalScore) = state else { return }
        state = .completed(score: finalScore)
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
        // CADisplayLink for the game loop — more accurate than Timer at 60 fps.
        let link = CADisplayLink(target: self, selector: #selector(gameLoopTick))
        link.add(to: .main, forMode: .common)
        displayLink = link

        spawnTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.spawnObstacle()
            self?.spawnCoins()
        }
    }

    private func stopTimers() {
        displayLink?.invalidate(); displayLink = nil
        spawnTimer?.invalidate();  spawnTimer  = nil
        countdownTimer?.invalidate(); countdownTimer = nil
    }

    private func resetGameData() {
        score = 0
        distance = 0
        speed = 5.0
        shadowObstacles = []
        shadowCoins = []
        obstacles = []
        coins = []
        frameCount = 0
        player.lane = 1
        player.isJumping = false
        player.isSliding = false
        player.position = 0
    }

    // MARK: - Game loop

    /// Called by CADisplayLink every display frame (~16.7 ms at 60 Hz).
    @objc private func gameLoopTick() {
        updateGame()
    }

    private func updateGame() {
        frameCount += 1

        for i in 0..<shadowObstacles.count { shadowObstacles[i].yPosition += speed }
        for i in 0..<shadowCoins.count     { shadowCoins[i].yPosition     += speed }

        shadowObstacles.removeAll { $0.yPosition > 1000 }
        shadowCoins.removeAll     { $0.yPosition > 1000 }

        distance += 1
        if distance % 500 == 0 { speed += 0.5 }

        // Collision check (every frame — needed for accuracy)
        for obstacle in shadowObstacles {
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

        // Coin collection (every frame)
        for (idx, coin) in shadowCoins.enumerated().reversed() {
            if coin.yPosition > 650 && coin.yPosition < 750 && coin.lane == player.lane {
                score += 10
                shadowCoins.remove(at: idx)
            }
        }

        // Publish to SwiftUI only every 3rd frame to reduce diffing overhead
        if frameCount % 3 == 0 {
            obstacles = shadowObstacles
            coins     = shadowCoins
        }
    }

    private func spawnObstacle() {
        shadowObstacles.append(Obstacle(
            lane: Int.random(in: 0...2),
            yPosition: -200,
            type: [.barrier, .ceiling, .train].randomElement()!
        ))
    }

    private func spawnCoins() {
        let n = Int.random(in: 1...3)
        for _ in 0..<n {
            shadowCoins.append(Coin(lane: Int.random(in: 0...2), yPosition: -150))
        }
    }
}
