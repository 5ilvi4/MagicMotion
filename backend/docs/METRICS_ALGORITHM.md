# Metrics Algorithm Reference

## Score Components

| Component | Weight | Description |
|-----------|--------|-------------|
| Symmetry | 40% | Left vs right limb balance |
| Smoothness | 30% | Movement jerkiness |
| ROM | 20% | Range of motion vs normalised baseline |
| Reaction Time | 10% | Speed of gesture response |

**Overall = 0.40·symmetry + 0.30·smooth + 0.20·ROM + 0.10·reaction**

---

## Symmetry Score (0–100)

For each frame with landmarks, compare the Euclidean distance from the body centre for each symmetric joint pair: `(leftShoulder, rightShoulder)`, `(leftHip, rightHip)`, etc.

```
deviation = |dist(L) - dist(R)| / max(dist(L), dist(R))
symmetryScore = 100 - (avgDeviation × 100)
```

Score 100 = perfectly symmetric. Score 50 = neutral. Score 0 = severe asymmetry.

---

## Smoothness Score (0–100)

Measures **mean jerk** (third derivative of position) on the left-shoulder trajectory.

1. Compute velocity: `v[i] = pos[i] - pos[i-1]`
2. Compute acceleration: `a[i] = v[i] - v[i-1]`
3. Compute jerk: `j[i] = |a[i] - a[i-1]|`
4. `smoothnessScore = max(0, 100 - meanJerk × 800)`

Empirical calibration: 30-fps MediaPipe stream, landmark positions normalised 0–1. Mean jerk ~0.01 → score ~92.

---

## ROM Score (0–100)

MediaPipe landmarks are normalised (0–1) relative to image frame.

| Measure | Landmark axis | Clinical joint |
|---------|--------------|----------------|
| shoulderAbduction | leftShoulder.x range | Shoulder lateral raise |
| hipFlexion | leftHip.y range | Hip forward bend |
| elbowFlexion | leftElbow.y range | Elbow curl |
| wristReach | leftWrist.x range | Reach distance |

Each value expressed as % of frame width/height. Sum of all four → ROM score (capped at 100).

---

## Reaction Time Score

Average inter-gesture interval in ms:

```
intervals = [t1-t0, t2-t1, ...]
reactionTime = mean(intervals)
```

Mapped to score:
- 200ms → 100  
- 1000ms → 20  
- Linear clamp: `score = 100 - ((ms - 200) / 800) × 80`

---

## Motor Improvement

Percentage change in `overallMotorScore` vs the immediately preceding session:

```
improvement = ((current - previous) / previous) × 100
```

`null` when no prior session exists.

---

## Clinical Interpretation

| Score | Interpretation |
|-------|---------------|
| ≥ 70 | Mild — within expected range |
| 50–69 | Moderate — continued therapy recommended |
| < 50 | Severe — significant impairment noted |
