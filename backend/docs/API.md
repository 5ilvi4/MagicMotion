# REST API Reference

Base URL: `https://api.motionmind.app`  
Auth: `Authorization: Bearer <JWT>` on all endpoints except `/api/auth/login` and `/health`.

---

## Auth

### `POST /api/auth/login`
Email + password login.
```json
{ "email": "...", "password": "..." }
→ { "accessToken": "...", "refreshToken": "...", "therapist": {...} }
```

### `POST /api/auth/refresh`
```json
{ "refreshToken": "..." }
→ { "accessToken": "..." }
```

### `GET /api/auth/google` → redirect to Google OAuth
### `POST /api/auth/apikey` — generate iPad API key
```json
{ "name": "iPad Clinic #1" }
→ { "keyID": "uuid", "key": "mm_xxx...", "expiresAt": "..." }
```

---

## Players

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/players` | Create patient |
| `GET` | `/api/players` | List therapist's patients |
| `GET` | `/api/players/:id` | Get patient |
| `PUT` | `/api/players/:id` | Update patient |
| `DELETE` | `/api/players/:id` | Soft-delete (GDPR) |

---

## Sessions

### `POST /api/sessions/upload`
Upload a completed game session.
```json
{
  "playerID": "uuid",
  "therapistID": "uuid",
  "sessionData": {
    "gameType": "subway_surfers",
    "duration": 30,
    "score": 850,
    "startTime": "2026-04-01T14:00:00Z",
    "endTime":   "2026-04-01T14:00:30Z",
    "gestures": [
      {
        "type": "LEAN_LEFT", "timestamp": 1000,
        "confidence": 0.94,
        "iPadDetected": true, "bandDetected": false,
        "landmarks": { "leftShoulder": {"x":0.4,"y":0.3,"z":0} ... }
      }
    ],
    "deviceInfo": { "model": "iPad Pro 12.9", "osVersion": "17.4" }
  }
}
→ 202 { "sessionID": "uuid", "status": "processing", "metricsURL": "...", "reportURL": "..." }
```

### `GET /api/sessions/:id` — full session with gestures + metrics
### `GET /api/sessions/player/:playerID?limit=50&offset=0&from=...&to=...`

---

## Metrics

### `GET /api/metrics/:sessionID`
```json
{
  "metricID": "uuid",
  "sessionID": "uuid",
  "symmetryScore": 82.5,
  "smoothnessScore": 85.0,
  "rom": { "shoulderAbduction": 45, "hipFlexion": 78, "elbowFlexion": 92, "wristReach": 31 },
  "reactionTime": 380,
  "overallMotorScore": 87,
  "motorImprovement": 5.2,
  "gestureSuccessRate": 92.6,
  "computedAt": "2026-04-01T14:01:00Z"
}
```

### `GET /api/metrics/player/:playerID/summary`
Aggregated averages across all sessions.

### `GET /api/metrics/player/:playerID/progress`
Per-session trend + monthly improvement %.
```json
{
  "motorScoreTrend": [
    { "date": "2026-03-15", "overallMotorScore": 72, "motorImprovement": null },
    { "date": "2026-04-01", "overallMotorScore": 87, "motorImprovement": 11.5 }
  ],
  "monthlyImprovement": 20.8,
  "status": "mild"
}
```

---

## Reports

### `POST /api/reports/generate/:sessionID?type=clinical_summary`
Generates PDF, uploads to S3, returns URL.
```json
→ 201 { "reportID": "uuid", "contentURL": "https://s3...", "generatedAt": "..." }
```

### `GET /api/reports/:reportID` — returns signed S3 URL (15-min expiry)
### `GET /api/reports/session/:sessionID` — list all reports for a session

---

## Error Codes

| HTTP | Code | Meaning |
|------|------|---------|
| 400 | `VALIDATION_ERROR` | Schema invalid |
| 401 | `AUTH_MISSING` | No token |
| 403 | `AUTH_INVALID` / `FORBIDDEN` | Bad token or wrong therapist |
| 404 | — | Resource not found |
| 409 | — | Duplicate session |
| 429 | `RATE_LIMIT_UPLOAD` | >100 uploads/day |
| 500 | `INTERNAL_ERROR` | Server error |
