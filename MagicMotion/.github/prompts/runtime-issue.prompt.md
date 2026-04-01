# MagicMotion Runtime Issue Fix

MagicMotion is in validation mode.

Focus only on the runtime-facing issue below.

Issue:
{{input:issue}}

Requirements:

- Preserve current architecture
- Keep runtime deterministic
- No UI-driven logic hacks
- No MotionEngine leakage into runtime
- Implement the smallest safe fix only
- Update tests if practical

Workflow:

1. Restate the runtime issue
2. Identify likely causes
3. Choose the smallest fix
4. List touched files
5. Implement only that fix
6. Add/update tests
7. Self-review
8. Stop
