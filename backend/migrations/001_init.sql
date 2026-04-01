-- ============================================================
-- 001_init.sql — Initial MotionMind schema
-- Run with: psql $DATABASE_URL -f migrations/001_init.sql
-- ============================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Therapists ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS therapists (
    "therapistID"  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name           TEXT NOT NULL,
    email          TEXT UNIQUE NOT NULL,
    "passwordHash" TEXT,
    clinic         TEXT,
    license        TEXT,
    "googleID"     TEXT UNIQUE,
    "deletedAt"    TIMESTAMPTZ,
    "createdAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Players ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS players (
    "playerID"    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "therapistID" UUID NOT NULL REFERENCES therapists("therapistID"),
    name          TEXT NOT NULL,
    "dateOfBirth" DATE,
    diagnosis     TEXT,
    notes         TEXT,
    "deletedAt"   TIMESTAMPTZ,
    "createdAt"   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── API Keys ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS api_keys (
    "keyID"       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "therapistID" UUID NOT NULL REFERENCES therapists("therapistID"),
    key           TEXT UNIQUE NOT NULL,
    name          TEXT,
    "expiresAt"   TIMESTAMPTZ,
    "createdAt"   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Sessions ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sessions (
    "sessionID"   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "playerID"    UUID NOT NULL REFERENCES players("playerID"),
    "therapistID" UUID NOT NULL REFERENCES therapists("therapistID"),
    "gameType"    VARCHAR(64) NOT NULL DEFAULT 'subway_surfers',
    "gameDuration" INTEGER,
    "gameScore"   INTEGER,
    "startedAt"   TIMESTAMPTZ,
    "completedAt" TIMESTAMPTZ,
    "deviceInfo"  JSONB,
    "createdAt"   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Gestures ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS gestures (
    "gestureID"    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "sessionID"    UUID NOT NULL REFERENCES sessions("sessionID") ON DELETE CASCADE,
    "gestureType"  VARCHAR(64),
    "timestamp"    INTEGER,
    confidence     FLOAT,
    "iPadDetected" BOOLEAN DEFAULT FALSE,
    "bandDetected" BOOLEAN DEFAULT FALSE,
    landmarks      JSONB,
    "createdAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Metrics ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS metrics (
    "metricID"           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "sessionID"          UUID UNIQUE NOT NULL REFERENCES sessions("sessionID") ON DELETE CASCADE,
    "symmetryScore"      FLOAT,
    "smoothnessScore"    FLOAT,
    rom                  JSONB,
    "reactionTime"       FLOAT,
    "overallMotorScore"  FLOAT,
    "motorImprovement"   FLOAT,
    "gestureSuccessRate" FLOAT,
    "computedAt"         TIMESTAMPTZ DEFAULT NOW(),
    "createdAt"          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Reports ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reports (
    "reportID"   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "sessionID"  UUID NOT NULL REFERENCES sessions("sessionID"),
    "reportType" VARCHAR(64),
    "contentURL" TEXT,
    format       VARCHAR(16) DEFAULT 'pdf',
    "createdAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Audit Logs (HIPAA) ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_logs (
    "logID"        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "userID"       UUID,
    "userType"     VARCHAR(32),
    action         VARCHAR(64),
    "resourceType" VARCHAR(64),
    "resourceID"   UUID,
    "ipAddress"    VARCHAR(45),
    "requestId"    UUID,
    "createdAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ───────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_players_therapist   ON players("therapistID");
CREATE INDEX IF NOT EXISTS idx_sessions_player     ON sessions("playerID");
CREATE INDEX IF NOT EXISTS idx_sessions_therapist  ON sessions("therapistID");
CREATE INDEX IF NOT EXISTS idx_sessions_started    ON sessions("startedAt" DESC);
CREATE INDEX IF NOT EXISTS idx_gestures_session    ON gestures("sessionID");
CREATE INDEX IF NOT EXISTS idx_metrics_session     ON metrics("sessionID");
CREATE INDEX IF NOT EXISTS idx_audit_user_action   ON audit_logs("userID", action, "createdAt");
