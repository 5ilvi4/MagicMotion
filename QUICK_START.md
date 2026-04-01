# Quick Start: 6-Layer Architecture

## What Just Happened

All 6 layers have been created and integrated. ContentView now orchestrates the entire pipeline:

```
Camera/Fake Input (L1)
        ↓
  MotionEngine (L2)
        ↓
 MotionInterpreter (L3)
        ↓
   GameSession (L4)
        ↓
   GameView (L5)
        ↓
    Rendered UI
```

## Running the App

### DEBUG Mode (Testing without Camera)

Set in ContentView.swift:

```swift
#if DEBUG
@State private var useSyntheticInput = true  // ← Set to true
#endif
```

Then app will:
1. Use `FakeMotionSource` to replay scripted poses
2. Skip real camera init
3. Show debug panel (event, confidence %, FPS)
4. No permissions needed

### RELEASE Mode (Real Camera)

Set to `false` or remove the override. App will:
1. Use `CameraManager` (real camera)
2. Request permissions
3. Hide debug UI
4. Run full pipeline

## Key Classes You Need to Know

### MotionEvent (Layer 3)
```swift
enum MotionEvent {
    case handsUp, handsDown, leanLeft, leanRight, jump, squat, freeze(duration: TimeInterval), none
    var displayName: String { ... }
}
```

Used in:
- `interpreter.onMotionEvent { event in ... }` — Fires when event confirmed
- `session.handle(event:)` — Maps to player actions

### GameSessionState (Layer 4)
```swift
enum GameSessionState {
    case idle, calibrating, countdown(Int), active, paused(String), roundOver, completed(Int)
}
```

Accessed in:
- `session.state` — Current FSM state
- `session.player` — Current player (lane, score, obstacles, coins)

### How to Test a Gesture

1. Open ContentView.swift, set `useSyntheticInput = true`
2. Run app in Simulator (any iPad)
3. Tap "START GAME"
4. App goes: idle → calibrating → countdown → active
5. In DEBUG panel, you'll see events firing (FakeMotionSource replays them)
6. Watch player respond (move left/right, jump, slide)

## Key Integration Points

### If you need to add a new gesture:

1. Add to `MotionEvent` enum (Layer 3)
2. Implement classifier in `MotionInterpreter.classifyPose()` (Layer 3)
3. Add to `session.handle(event:)` case in `GameSession` (Layer 4)
4. Add fixture script to `FakeMotionSource` (Layer 6)
5. Update `GameView` to show new player state if needed (Layer 5)

### If you need to add a new game mechanic:

1. Add property to `Player` in `GameModels.swift` (Layer 4)
2. Update `GameSession.gameLoop()` to update it (Layer 4)
3. Render it in `GameView` (Layer 5)

### If you need to test with a real camera:

1. Set `useSyntheticInput = false` in ContentView.swift
2. Request camera permission in Info.plist
3. Run on device or Simulator with camera simulation
4. App will use `CameraManager` (real camera) → `MotionEngine` (real MediaPipe) → rest of pipeline

## Debugging Checklist

- [ ] No compilation errors? Run `xcodebuild build` or try building in Xcode
- [ ] Camera permission granted? (if using real camera)
- [ ] MediaPipe frameworks in Pods? (should be, but check Pod install)
- [ ] External screen connected? (ExternalDisplayManager should detect and show operator panel)
- [ ] Tracking lost? (GameSession pauses with reason)
- [ ] FPS dropping? (check MotionEngine confidence threshold — lower = more processing)
- [ ] Events not firing? (check MotionInterpreter confirmation gate — need 3 frames)

## File You Should NOT Edit

These are auto-generated or deprecated:

- `Pods/` — Pod dependencies (run `pod install` if missing)
- `PoseDetector.swift`, `GestureClassifier.swift`, `GameState.swift` — Old code (delete later)
- `project.pbxproj` — Build config (edit via Xcode)

## Files You MIGHT Edit

- `ContentView.swift` — Change layout, debug panel
- `GameView.swift` — Change game UI, screens
- `GameSession.swift` — Change game loop, FSM transitions
- `MotionInterpreter.swift` — Tune gesture thresholds (0.08 for lean/jump/squat)
- `MotionEngine.swift` — Tune confidence threshold (0.5 default)
- `FakeMotionSource.swift` — Add more fixture scripts

## Example: Tuning Lean Gesture

If "leanLeft" is too sensitive or not sensitive enough:

Open `MotionInterpreter.swift`, line ~150:
```swift
private func classifyLean(_ buffer: RingBuffer<PoseSnapshot>) -> MotionEvent? {
    let threshold = 0.08  // ← Tune this (0.05 = more sensitive, 0.10 = less)
    // ...
}
```

Lower = easier to trigger (more false positives)  
Higher = harder to trigger (might miss real gestures)

## Example: Adding a New Gesture

Let's say you want to add "armsCrossed":

**Step 1: Layer 3 — Add to MotionEvent**
```swift
enum MotionEvent {
    // ... existing ...
    case armsCrossed
}
```

**Step 2: Layer 3 — Add classifier in MotionInterpreter**
```swift
private func classifyArmsCrossed(_ buffer: RingBuffer<PoseSnapshot>) -> MotionEvent? {
    let latest = buffer.last
    let leftWrist = latest?.leftWrist, rightWrist = latest?.rightWrist
    let shoulderDist = abs(leftWrist?.x ?? 0 - rightWrist?.x ?? 0)
    if shoulderDist < 0.15 { return .armsCrossed }
    return nil
}
```

**Step 3: Layer 4 — Map to player action in GameSession**
```swift
case .armsCrossed:
    player.spin()  // or whatever action
```

**Step 4: Layer 6 — Add test fixture**
```swift
static let armsCrossedScript: [PoseSnapshot] = [
    // Wrists close together, repeat 15 times
    PoseSnapshot(leftWrist: Landmark(x: 0.45, y: 0.5, z: 0.0, visibility: 0.9), 
                 rightWrist: Landmark(x: 0.55, y: 0.5, z: 0.0, visibility: 0.9),
                 // ... rest of landmarks
    )
]
```

**Step 5: Layer 5 — Render in GameView**
```swift
struct PlayerView: View {
    let player: Player
    var body: some View {
        Text(player.isSpinning ? "🌪️" : "🏃")  // etc.
    }
}
```

Done! Now:
- Detector will recognize armsCrossed
- Player will perform action
- GameView will render it
- FakeMotionSource can test it

---

## Next: What to Do Now

1. **Build**: `xcodebuild build` or Xcode build button
2. **Run**: Select device/simulator, run
3. **Test DEBUG**: Set `useSyntheticInput = true`, tap START
4. **Test RELEASE**: Set `useSyntheticInput = false`, allow camera
5. **Check logs**: Watch Xcode console for events, confidence, FPS

All 6 layers are ready. The pipeline is wired. Go forth and ship! 🚀
