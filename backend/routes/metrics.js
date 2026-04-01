// ============================================================
// routes/metrics.js — Metrics retrieval and progress trends
// ============================================================

'use strict';

const express  = require('express');
const router   = express.Router();
const { Op, fn, col, literal } = require('sequelize');
const { Session, Metrics, Player } = require('../models');
const { authenticateToken, authorizeTherapist } = require('../middleware/auth');

// ── GET /api/metrics/:sessionID ───────────────────────────────
router.get('/:sessionID', authenticateToken, async (req, res, next) => {
    try {
        const metrics = await Metrics.findOne({
            where: { sessionID: req.params.sessionID }
        });

        if (!metrics) {
            return res.status(404).json({
                error: 'Metrics not yet computed — try again shortly',
                code: 'METRICS_PENDING'
            });
        }

        // Authorisation: verify therapist owns this session's player
        const session = await Session.findByPk(req.params.sessionID, { attributes: ['playerID'] });
        const player  = await Player.findByPk(session?.playerID, { attributes: ['therapistID'] });
        if (player?.therapistID !== req.user.therapistID) {
            return res.status(403).json({ error: 'Access denied' });
        }

        await authenticateToken.audit(req, 'read_metrics', 'metrics', metrics.metricID);
        res.json(metrics);
    } catch (err) {
        next(err);
    }
});

// ── GET /api/metrics/player/:playerID/summary ─────────────────
// Aggregated metrics for a player across all sessions.
router.get('/player/:playerID/summary',
    authenticateToken,
    authorizeTherapist,
    async (req, res, next) => {
        try {
            const sessions = await Session.findAll({
                where:   { playerID: req.params.playerID },
                include: [{ model: Metrics, as: 'metrics', required: true }],
                order:   [['startedAt', 'ASC']]
            });

            if (!sessions.length) {
                return res.json({ sessionCount: 0, summary: null });
            }

            const metricsList = sessions.map(s => s.metrics);

            const avg = field => {
                const vals = metricsList.map(m => m[field]).filter(v => v != null);
                return vals.length ? +(vals.reduce((a, b) => a + b, 0) / vals.length).toFixed(1) : null;
            };

            res.json({
                playerID:       req.params.playerID,
                sessionCount:   sessions.length,
                dateRange: {
                    from: sessions[0].startedAt,
                    to:   sessions[sessions.length - 1].startedAt
                },
                summary: {
                    avgOverallMotorScore:  avg('overallMotorScore'),
                    avgSymmetryScore:      avg('symmetryScore'),
                    avgSmoothnessScore:    avg('smoothnessScore'),
                    avgReactionTime:       avg('reactionTime'),
                    avgGestureSuccessRate: avg('gestureSuccessRate'),
                    latestMotorScore:      metricsList[metricsList.length - 1]?.overallMotorScore
                }
            });
        } catch (err) {
            next(err);
        }
    }
);

// ── GET /api/metrics/player/:playerID/progress ────────────────
// Per-session motor score + improvement trend.
router.get('/player/:playerID/progress',
    authenticateToken,
    authorizeTherapist,
    async (req, res, next) => {
        try {
            const player = await Player.findByPk(req.params.playerID, {
                attributes: ['playerID', 'name', 'diagnosis']
            });
            if (!player) return res.status(404).json({ error: 'Player not found' });

            const sessions = await Session.findAll({
                where:   { playerID: req.params.playerID },
                include: [{ model: Metrics, as: 'metrics', required: true }],
                order:   [['startedAt', 'ASC']]
            });

            const trend = sessions.map(s => ({
                sessionID:        s.sessionID,
                date:             s.startedAt,
                overallMotorScore:s.metrics.overallMotorScore,
                motorImprovement: s.metrics.motorImprovement
            }));

            // Month-over-month improvement (last 30 days vs 30–60 days ago)
            const now     = Date.now();
            const last30  = sessions.filter(s => now - s.startedAt.getTime() <= 30 * 864e5);
            const prev30  = sessions.filter(s => {
                const age = now - s.startedAt.getTime();
                return age > 30 * 864e5 && age <= 60 * 864e5;
            });

            const avg = arr => {
                const scores = arr.map(s => s.metrics?.overallMotorScore).filter(Boolean);
                return scores.length ? scores.reduce((a, b) => a + b, 0) / scores.length : null;
            };

            const recentAvg = avg(last30);
            const priorAvg  = avg(prev30);
            const monthlyImprovement = (recentAvg != null && priorAvg != null)
                ? +( ((recentAvg - priorAvg) / priorAvg) * 100 ).toFixed(1)
                : null;

            const latestScore = trend[trend.length - 1]?.overallMotorScore;
            const status = latestScore == null   ? 'no_data'
                         : latestScore >= 70     ? 'mild'
                         : latestScore >= 50     ? 'moderate'
                         :                         'severe';

            res.json({
                playerID:           player.playerID,
                name:               player.name,
                diagnosis:          player.diagnosis,
                sessions:           sessions.length,
                motorScoreTrend:    trend,
                monthlyImprovement,
                status
            });
        } catch (err) {
            next(err);
        }
    }
);

module.exports = router;
