// ============================================================
// services/ValidationService.js — Joi schema validation
// ============================================================

'use strict';

const Joi = require('joi');

// ── Individual landmark (MediaPipe NormalizedLandmark) ────────
const landmarkSchema = Joi.object({
    x:          Joi.number().min(0).max(1).required(),
    y:          Joi.number().min(0).max(1).required(),
    z:          Joi.number().required(),
    visibility: Joi.number().min(0).max(1)
}).unknown(false);

// ── Pose snapshot (33 MediaPipe landmarks) ────────────────────
// We accept the object keyed by landmark name or index.
const poseSchema = Joi.object().pattern(
    Joi.string(),
    landmarkSchema
);

// ── Single gesture entry ──────────────────────────────────────
const gestureSchema = Joi.object({
    type:         Joi.string().valid(
        'LEAN_LEFT','LEAN_RIGHT','JUMP','SQUAT','DUCK',
        'RAISE_ARM_LEFT','RAISE_ARM_RIGHT','TWIST','NOP'
    ).required(),
    timestamp:    Joi.number().integer().min(0).required(),
    confidence:   Joi.number().min(0).max(1).required(),
    iPadDetected: Joi.boolean().default(false),
    bandDetected: Joi.boolean().default(false),
    landmarks:    poseSchema.optional()
});

// ── Full session upload payload ────────────────────────────────
const sessionUploadSchema = Joi.object({
    playerID:    Joi.string().uuid({ version: 'uuidv4' }).required(),
    therapistID: Joi.string().uuid({ version: 'uuidv4' }).required(),
    sessionData: Joi.object({
        gameType:    Joi.string().default('subway_surfers'),
        duration:    Joi.number().integer().min(1).max(3600).required(),
        score:       Joi.number().integer().min(0),
        startTime:   Joi.string().isoDate().required(),
        endTime:     Joi.string().isoDate().required(),
        gestures:    Joi.array().items(gestureSchema).min(1).max(10000).required(),
        deviceInfo:  Joi.object({
            model:      Joi.string(),
            osVersion:  Joi.string(),
            appVersion: Joi.string()
        }).unknown(true)
    }).required(),
    bandMetadata: Joi.object({
        gestureCount:    Joi.number().integer().min(0),
        successCount:    Joi.number().integer().min(0),
        avgConfidence:   Joi.number().min(0).max(1),
        firmwareVersion: Joi.string()
    }).optional()
});

class ValidationService {
    /**
     * Validate a session upload payload.
     * Returns { valid: bool, errors: string[], value: sanitised }
     */
    static validateSessionUpload(payload) {
        const { error, value } = sessionUploadSchema.validate(payload, {
            abortEarly:  false,
            stripUnknown: true,
            convert:      true
        });

        if (error) {
            return {
                valid:  false,
                errors: error.details.map(d => d.message),
                value:  null
            };
        }

        // Business rule: endTime must be after startTime
        const start = new Date(value.sessionData.startTime);
        const end   = new Date(value.sessionData.endTime);
        if (end <= start) {
            return {
                valid:  false,
                errors: ['sessionData.endTime must be after sessionData.startTime'],
                value:  null
            };
        }

        return { valid: true, errors: [], value };
    }

    /**
     * Sanitise a landmarks object — replace any NaN/Infinity
     * values with null so JSON serialisation doesn't break.
     */
    static sanitiseLandmarks(landmarks) {
        if (!landmarks || typeof landmarks !== 'object') return null;

        const clean = {};
        for (const [key, lm] of Object.entries(landmarks)) {
            clean[key] = {
                x: isFinite(lm.x) ? lm.x : null,
                y: isFinite(lm.y) ? lm.y : null,
                z: isFinite(lm.z) ? lm.z : null,
                visibility: lm.visibility != null && isFinite(lm.visibility)
                    ? lm.visibility : null
            };
        }
        return clean;
    }
}

module.exports = ValidationService;
