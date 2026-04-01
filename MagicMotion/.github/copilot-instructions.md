# MotionMind — GitHub Copilot Instructions

## Product Identity
- **Product name**: MotionMind (do not use "MagicMotion" or "SubwaySurferMotion" in new code or copy)
- **Tagline**: "Your child's hands are the controller."
- **Mission**: Detect 7/8 developmental gaps in children ages 3–11 through camera-based gesture gameplay. Prescribe gap-closing household activities. Zero parent effort.
- **System layers**: Wearable Band (future) + Camera System (current) + AI Platform (future)
- **Stage**: Camera system MVP — gesture game on iPad using Google MediaPipe

## User Personas
- **Lena** — Age 6. Loves drawing but her hand gives out after 2 minutes. The child user.
- **Maya** — Age 34. Product manager, Lena's mom. Worried, no tool to act with. The parent user.
- Both are **composite personas** grounded in field research. Do not present them as real testimonials.

## Business Context
- **Market**: $103B child developmental health market by 2034 (7% CAGR)
- **White space**: Between screen management tools (Bark, Apple Screen Time) and clinical OT — no product serves the pre-clinical family
- **Competitors**: Nex Playground, Osmo, GoNoodle, Apple Screen Time — none detect AND prescribe
- **Regulatory**: FDA General Wellness (Jan 2026) for camera + activity prescription. COPPA 2025 compliant required. No child account registration.
- **Revenue**: Free tier + $9.99/mo premium + $49 wearable band (future) + $499/site/yr B2B

## Architecture (strict layer separation — do not mix layers)
| Layer | File(s) | Responsibility |
|---|---|---|
| Capture | `CameraManager.swift` | AVCaptureSession, frame delivery |
| MotionEngine | `PoseDetector.swift`, `MediaPipePoseDetector.swift` | MediaPipe landmark extraction |
| MotionInterpreter | `GestureClassifier.swift` | Gesture recognition from PoseFrame |
| GameRuntime | `GameViewModel.swift`, `AppSessionState.swift`, `GameModels.swift` | State, scoring, session |
| Presentation | `ContentView.swift`, `GameView.swift`, `SkeletonOverlayView.swift` | SwiftUI UI only |
| Diagnostics | `#if DEBUG` blocks in `GameView.swift` | Operator panel, tuning sliders |

## Coding Constraints (playtest-tuning mode)
1. **One fix, one file** — each change should touch the minimal surface area
2. **No new dependencies** without explicit approval
3. **No layer violations** — Presentation must not import MediaPipe; MotionEngine must not import SwiftUI
4. **Debug-only diagnostics** — all operator panels and sliders must be inside `#if DEBUG`
5. **COPPA compliance** — never collect, log, or transmit any child identifier, face data, or biometric without explicit parent consent gating
6. **Branding** — always use "MotionMind" in UI copy, never old names

## Key State Flow
```
CameraManager → PoseDetector.onPoseDetected → GestureClassifier.addFrame()
                                             → AppSessionState.updateTracking(confidence:)
                                             → ContentView (currentPose → SkeletonOverlayView)
GestureClassifier.onGestureDetected → TouchInjector.inject(gesture:)
AppSessionState → GameViewModel (Combine subscription) → GameView overlayState
```

## AppSessionState Tuning Parameters
| Parameter | Default | Notes |
|---|---|---|
| `confidenceThreshold` | 0.5 | Pose confidence below this → tracking lost |
| `overlayDwellSeconds` | 1.0 | How long confidence must be stable before state flips |
| `calibrationFramesRequired` | 30 | Frames needed before calibration is complete |
| `gestureSensitivity` | 0.15 | Normalized delta threshold for gesture detection |

## Gesture Vocabulary (current)
| Gesture | Trigger |
|---|---|
| `leanLeft` | Hip X < 0.35 |
| `leanRight` | Hip X > 0.65 |
| `jump` | Ankles rise > 0.20 in 3 frames |
| `squat` | Hips drop > 0.20 in 3 frames |
| `swipeLeft` / `swipeRight` | Wrist delta X > 0.15 |
| `swipeUp` / `swipeDown` | Wrist delta Y > 0.15 |

## Known Issues / Do Not Re-Introduce
- ~~Dual `poseDetector.onPoseDetected` assignment~~ — fixed; second assignment silently overwrites the first
- ~~`TrackingState.ready` does not exist~~ — correct cases are `.tracking(confidence:)`, `.lost`, `.notReady`, `.searching`
- ~~`GameView` receiving `sessionState` as `@ObservedObject` without injection~~ — fixed; passed via init in DEBUG builds

## Developmental Gaps Detected by Camera (current)
1. Gross motor activation
2. Body schema / spatial cognition
3. Visual-motor integration (VMI)
4. Vestibular (full-body movement)
5. Fine motor precision (partially — wrist tracking)
6. Proprioceptive load (partially — body pose)
7. Visual-motor reaction timing

Gap 8 (relational/social) cannot be detected by camera — requires human.

## Roadmap Context
- **Now → Q2 2026**: Field validation, COPPA architecture, gesture prototype (MediaPipe) — this codebase
- **Q3 2026**: App store launch (iOS), free tier + premium, OT pilot, PDF report
- **Q4 2026**: Wearable band v1 (grip + accel + gyro), school B2B, FHIR
- **2027–2028**: FDA De Novo, Medicaid/CHIP, Epic/Cerner integration
