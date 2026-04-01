# IMU Calibration Guide

## What Calibration Does

On boot, `IMUSensor::begin()` samples the MPU6886 100 times over 1 second and records the **resting gravity magnitude** (~1.0 G).

This baseline is used so that `detectJump()` fires only when acceleration **exceeds** the resting level by `JUMP_THRESHOLD` (default: 2.0 G).

## During Boot

1. Place band on a flat surface (or hold completely still)
2. Do not move for 1 second after TFT shows "Booting..."
3. Serial output:
   ```
   [IMU] Calibrating — hold device still for 1 second...
   [IMU] Calibration done — baseline G = 1.003
   ```
4. If baseline G is outside 0.85–1.15, something moved — reset and recalibrate

## Tuning Thresholds

Edit `Config.h`:

```cpp
// Increase if too many false positives (random gestures trigger jump)
#define JUMP_THRESHOLD   2.0f   // G-force above baseline

// Decrease if IMU jumps not being detected
// #define JUMP_THRESHOLD   1.5f

// Minimum time between two jump detections
#define JUMP_DEBOUNCE_MS  300   // ms
```

## Test Calibration

With serial monitor open:
1. Hold band still: no `[IMU] Jump detected` messages
2. Lift arm sharply (simulate jump): `[IMU] Jump detected (mag=X.XX, delta=X.XX)` 
3. Rapid taps: only one detection per 300ms (debounce working)

## Re-Calibrate Without Reboot

Currently requires a hardware reset. Future firmware could expose a BLE characteristic to trigger recalibration on demand.
