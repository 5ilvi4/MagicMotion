// ============================================================
// routes/sessions.js — Upload, retrieve, list sessions
// ============================================================

'use strict';

const express    = require('express');
const router     = express.Router();
const { v4: uuidv4 } = require('uuid');
const { Op }     = require('sequelize');

const { Session, Gesture, Metrics } = require('../models');
const ValidationService = require('../services/ValidationService');
const { enqueue }       = require('../services/MetricsQueue');
const { authenticateToken, authorizeTherapist, buildUploadRateLimiter } = require('../middleware/auth');

let _uploadLimiter;
(async () => { _uploadLimiter = await buildUploadRateLimiter(); })();
const uploadLimiter = (req, res, next) => (_uploadLimiter ? _uploadLimiter(req, res, next) : next());

// ── POST /api/sessions/upload ─────────────────────────────────
router.post('/upload',
    authenticateToken,
    uploadLimiter,
    async (req, res, next) => {
        try {
            // 1. Validate schema
            const { valid, errors, value: payload } = ValidationService.validateSessionUpload(req.body);
            if (!valid) {
                return res.status(400).json({ error: 'Invalid session schema', details: errors });
            }

            const { playerID, therapistID, sessionData, bandMetadata } = payload;

            // 2. Authorisation: therapist may only upload for their own players
            const { Player } = require('../models');
            const player = await Player.findByPk(playerID, { attributes: ['therapistID'] });
            if (!player) {
                return res.status(404).json({ error: 'Player not found' });
            }
            if (player.therapistID !== req.user.therapistID) {
                return res.status(403).json({ error: 'Access denied', code: 'FORBIDDEN' });
            }

            // 3. Idempotency — duplicate within 5-minute window?
            const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
            const existing = await Session.findOne({
                where: {
                    playerID,
                    startedAt: { [Op.gte]: new Date(sessionData.startTime) },
                    createdAt: { [Op.gte]: fiveMinutesAgo }
                },
                attributes: ['sessionID']
            });

            if (existing) {
                return res.status(409).json({
                    error: 'Duplicate session detected',
                    sessionID: existing.sessionID
                });
            }

            // 4. Create session record
            const session = await Session.create({
                sessionID:   uuidv4(),
                playerID,
                therapistID,
                gameType:    sessionData.gameType,
                gameDuration:sessionData.duration,
                gameScore:   sessionData.score ?? null,
                startedAt:   new Date(sessionData.startTime),
                completedAt: new Date(sessionData.endTime),
                deviceInfo:  sessionData.deviceInfo ?? null
            });

            // 5. Bulk-insert gesture rows
            const gestureRows = sessionData.gestures.map(g => ({
                gestureID:    uuidv4(),
                sessionID:    session.sessionID,
                gestureType:  g.type,
                timestamp:    g.timestamp,
                confidence:   g.confidence,
                iPadDetected: g.iPadDetected,
                bandDetected: g.bandDetected,
                landmarks:    ValidationService.sanitiseLandmarks(g.landmarks)
            }));

            await Gesture.bulkCreate(gestureRows, { validate: true });

            // 6. Enqueue async metrics computation (non-blocking)
            enqueue(session.sessionID, gestureRows);

            await authenticateToken.audit(req, 'session_upload', 'session', session.sessionID);

            res.status(202).json({
                sessionID:  session.sessionID,
                status:     'processing',
                metricsURL: `/api/metrics/${session.sessionID}`,
                reportURL:  `/api/reports/${session.sessionID}`
            });

        } catch (err) {
            next(err);
        }
    }
);

// ── GET /api/sessions/:sessionID ──────────────────────────────
router.get('/:sessionID', authenticateToken, async (req, res, next) => {
    try {
        const session = await Session.findByPk(req.params.sessionID, {
            include: [
                { model: Gesture, as: 'gestures', attributes: { exclude: ['landmarks'] } },
                { model: Metrics, as: 'metrics' }
            ]
        });

        if (!session) return res.status(404).json({ error: 'Session not found' });

        // Therapist must own the player
        const { Player } = require('../models');
        const player = await Player.findByPk(session.playerID, { attributes: ['therapistID'] });
        if (player?.therapistID !== req.user.therapistID) {
            return res.status(403).json({ error: 'Access denied' });
        }

        await authenticateToken.audit(req, 'read_session', 'session', session.sessionID);
        res.json(session);
    } catch (err) {
        next(err);
    }
});

// ── GET /api/sessions/player/:playerID ───────────────────────
router.get('/player/:playerID',
    authenticateToken,
    authorizeTherapist,
    async (req, res, next) => {
        try {
            const { limit = 50, offset = 0, from, to } = req.query;

            const where = { playerID: req.params.playerID };
            if (from || to) {
                where.startedAt = {};
                if (from) where.startedAt[Op.gte] = new Date(from);
                if (to)   where.startedAt[Op.lte] = new Date(to);
            }

            const sessions = await Session.findAndCountAll({
                where,
                include: [{ model: Metrics, as: 'metrics', attributes: ['overallMotorScore', 'symmetryScore', 'smoothnessScore'] }],
                order:   [['startedAt', 'DESC']],
                limit:   Math.min(parseInt(limit, 10), 100),
                offset:  parseInt(offset, 10)
            });

            res.json({
                total: sessions.count,
                sessions: sessions.rows
            });
        } catch (err) {
            next(err);
        }
    }
);

module.exports = router;
