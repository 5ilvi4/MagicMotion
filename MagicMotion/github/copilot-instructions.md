# MagicMotion Copilot Instructions

MagicMotion is an iPad-based motion-interaction app for kids.
The iPad is the operator/setup surface.
An external monitor/TV is the kid-facing gameplay display.
Motion sensing must use MediaPipe only.

## Current mode

The project is in validation and playtest-tuning mode.

Do not propose a new major subsystem or broad implementation phase unless absolutely necessary.

## Architecture rules

Preserve the current architecture and boundaries:

- Capture layer: camera, permissions, orientation, throttling
- MotionEngine: MediaPipe wrapper only, app-level pose output only
- MotionInterpreter: pose/motion frames to MotionEvent
- GameRuntime: session flow, scoring, state machine, consumes MotionEvent only
- Presentation: operator UI, gameplay UI, external display handling
- Diagnostics/Test: fake input, fixtures, debug hooks, tests

Strict rules:

- No MediaPipe-specific types outside MotionEngine
- No camera logic in UI
- No gameplay logic in views
- No raw landmark math in UI
- No runtime logic in presentation
- No speculative refactors
- No unrelated cleanup
- No feature creep

## How to respond to issues

For each issue or bug report:

1. Restate the issue precisely
2. Identify the most likely root causes in the current architecture
3. Propose the smallest safe fix
4. State which files/modules should change
5. Implement only that fix
6. Add or update tests if practical
7. Briefly self-review for regressions or architectural leakage
8. Stop

## Priorities

Prioritize:

- playability
- calibration stability
- tracking recovery
- operator clarity
- repeatable reset/restart behavior
- external display safety
- minimal, maintainable changes

## Avoid

Avoid:

- broad redesigns
- introducing new frameworks without strong justification
- “future-proofing” abstractions that are not needed now
- cosmetic polish unless it directly improves usability or testing
- changing multiple layers when a local fix is enough

## Working style

Keep changes bounded, explicit, and testable.
Prefer canonical state flow over duplicated presentation state.
Prefer the smallest fix that improves real playtest reliability.
