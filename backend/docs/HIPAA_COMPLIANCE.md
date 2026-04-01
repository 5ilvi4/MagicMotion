# HIPAA Compliance Checklist

## Encryption

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| Encryption at rest | PostgreSQL on AWS RDS with AES-256 | ✅ |
| Encryption at rest (reports) | S3 `ServerSideEncryption: AES256` on every `putObject` | ✅ |
| Encryption in transit | HTTPS / TLS 1.2+ via ALB / Heroku | ✅ |
| Keys managed | AWS KMS or Heroku-managed certs | ✅ |

## Access Control

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| Authentication | JWT (24h expiry) + refresh tokens | ✅ |
| OAuth2 | Google sign-in for therapists | ✅ |
| Role-based access | Therapists only see own patients | ✅ |
| API key expiry | Device keys expire after 1 year | ✅ |

## Audit Logging

Every data access (read, write, delete) is written to `audit_logs`:
- `userID`, `userType`, `action`, `resourceType`, `resourceID`
- `ipAddress`, `requestId`, `createdAt`

Table is **append-only** (no updates, no deletes).

## Data Retention

| Policy | Implementation |
|--------|---------------|
| Active records | Kept indefinitely |
| GDPR soft-delete | `deletedAt` set on player; records purged after `GDPR_SOFT_DELETE_EXPIRY_DAYS` (default 30) |
| Archive | Sessions marked archived after 7 years (cron job) |

## Privacy by Design

- **Minimum data collection**: landmarks stored per-gesture, not as video
- **Pseudonymisation**: `playerID` UUIDs; no PII in gesture/metrics tables
- **Right to deletion**: `DELETE /api/players/:id` initiates GDPR soft-delete
- **Portability**: `GET /api/sessions/player/:id` returns full JSON export

## Operational Requirements

| Requirement | Action Required |
|-------------|-----------------|
| BAA | Sign Business Associate Agreement with AWS / Heroku before go-live |
| Penetration testing | Annual third-party security audit |
| Incident response | 72-hour breach notification to patients per HIPAA rule |
| Employee training | All staff with PHI access complete HIPAA training annually |
| Risk analysis | Annual HIPAA Security Rule risk analysis |

## Outstanding (Before Clinical Use)

- [ ] Sign BAA with cloud provider
- [ ] Enable VPC + private subnets for RDS
- [ ] Enable CloudTrail / GuardDuty on AWS account
- [ ] Set S3 bucket policy: no public access
- [ ] Complete IRB protocol (Prompt 12)
- [ ] Obtain HIPAA attestation from hosting provider
