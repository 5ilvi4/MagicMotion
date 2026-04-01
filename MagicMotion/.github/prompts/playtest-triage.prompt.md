# MagicMotion Playtest Triage

MagicMotion is in validation and playtest-tuning mode.

Use the workspace instructions and preserve the current architecture.

## Task

Diagnose and fix the specific issue below with the smallest safe change.

Issue:
{{input:issue}}

## Required workflow

1. Restate the issue precisely
2. Identify the most likely root causes
3. Propose the smallest bounded fix
4. List the files/modules that should change
5. Implement only that fix
6. Add or update tests if practical
7. Briefly self-review for regressions, coupling, or architecture leakage
8. Stop

## Constraints

- No major subsystem proposals
- No broad refactors
- No unrelated cleanup
- No feature creep
- No new motion stack
- Preserve MediaPipe-only sensing
- Preserve fake mode and current debug/tuning flows

## Focus

Optimize for:

- real playtest reliability
- calibration/tracking stability
- clean recovery from tracking loss
- operator clarity
- repeatable reset/restart behavior
