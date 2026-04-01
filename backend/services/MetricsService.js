// ============================================================
// services/MetricsService.js — Clinical motor quality computation
// ============================================================

'use strict';

const { Session, Metrics } = require('../models');
const logger = require('./LoggerService');

// ── Landmark name pairs for symmetry analysis ─────────────────
const SYMMETRY_PAIRS = [
    ['leftShoulder',  'rightShoulder'],
    ['leftElbow',     'rightElbow'],
    ['leftWrist',     'rightWrist'],
    ['leftHip',       'rightHip'],
    ['leftKnee',      'rightKnee'],
    ['leftAnkle',     'rightAnkle']
];

class MetricsService {

    // ──────────────────────────────────────────────────────────
    // PUBLIC: computeAndStore
    // Entry point called by the job queue.
    // ──────────────────────────────────────────────────────────
    static async computeAndStore(sessionID, gestures) {
        try {
            const landmarkHistory = gestures
                .filter(g => g.landmarks)
                .map(g => g.landmarks);

            const timestamps = gestures.map(g => g.timestamp);

            // Collect left-shoulder position history for smoothness
            const leftShoulderHistory = landmarkHistory
                .map(lm => lm.leftShoulder)
                .filter(Boolean);

            const symmetryScore    = this.computeSymmetryScore(landmarkHistory);
            const smoothnessScore  = this.computeSmoothnessScore(leftShoulderHistory);
            const rom              = this.computeROM(landmarkHistory);
            const romScore         = this._romToScore(rom);
            const reactionTime     = this.computeReactionTime(timestamps);
            const reactionScore    = this._reactionTimeToScore(reactionTime);

            const overallMotorScore = this.computeOverallScore(
                symmetryScore, smoothnessScore, romScore, reactionScore
            );

            const gestureSuccessRate = this._gestureSuccessRate(gestures);

            // Compare to previous session for improvement %
            const session       = await Session.findByPk(sessionID, { attributes: ['playerID'] });
            const motorImprovement = session
                ? await this.computeMotorImprovement(session.playerID, overallMotorScore)
                : null;

            const [metrics, created] = await Metrics.upsert({
                sessionID,
                symmetryScore,
                smoothnessScore,
                rom,
                reactionTime,
                overallMotorScore,
                motorImprovement: motorImprovement ?? null,
                gestureSuccessRate,
                computedAt: new Date()
            }, { returning: true });

            logger.info(`Metrics computed for session ${sessionID}`, {
                overallMotorScore, symmetryScore, smoothnessScore
            });

            return metrics;
        } catch (err) {
            logger.error(`Metrics computation failed for session ${sessionID}`, { err: err.message });
            throw err;
        }
    }

    // ──────────────────────────────────────────────────────────
    // Symmetry score (0–100)
    // Compares left vs right limb distances from body centre
    // across all frames where landmarks are available.
    // ──────────────────────────────────────────────────────────
    static computeSymmetryScore(landmarkHistory) {
        if (!landmarkHistory.length) return 50;   // neutral default

        const deviations = [];

        for (const frame of landmarkHistory) {
            for (const [leftKey, rightKey] of SYMMETRY_PAIRS) {
                const L = frame[leftKey];
                const R = frame[rightKey];
                if (!L || !R) continue;

                const dL = Math.hypot(L.x, L.y);
                const dR = Math.hypot(R.x, R.y);
                const max = Math.max(dL, dR);
                if (max < 1e-6) continue;

                deviations.push(Math.abs(dL - dR) / max);
            }
        }

        if (!deviations.length) return 50;

        const avgDeviation = deviations.reduce((a, b) => a + b, 0) / deviations.length;
        return Math.max(0, Math.min(100, 100 - avgDeviation * 100));
    }

    // ──────────────────────────────────────────────────────────
    // Smoothness score (0–100)
    // Based on mean jerk (rate of change of acceleration)
    // applied to a single tracking landmark trajectory.
    // ──────────────────────────────────────────────────────────
    static computeSmoothnessScore(positionHistory) {
        if (positionHistory.length < 4) return 100;

        const velocities     = [];
        const accelerations  = [];

        for (let i = 1; i < positionHistory.length; i++) {
            velocities.push({
                x: positionHistory[i].x - positionHistory[i - 1].x,
                y: positionHistory[i].y - positionHistory[i - 1].y
            });
        }
        for (let i = 1; i < velocities.length; i++) {
            accelerations.push({
                x: velocities[i].x - velocities[i - 1].x,
                y: velocities[i].y - velocities[i - 1].y
            });
        }

        const jerks = [];
        for (let i = 1; i < accelerations.length; i++) {
            const j = Math.hypot(
                accelerations[i].x - accelerations[i - 1].x,
                accelerations[i].y - accelerations[i - 1].y
            );
            jerks.push(j);
        }

        if (!jerks.length) return 100;

        const meanJerk = jerks.reduce((a, b) => a + b, 0) / jerks.length;
        // Empirical: meanJerk ~ 0 → smooth (100), ~ 0.05+ → jerky (<60)
        const score = Math.max(0, Math.min(100, 100 - meanJerk * 800));
        return score;
    }

    // ──────────────────────────────────────────────────────────
    // ROM (Range of Motion) — returns object of normalised values
    // Landmark coordinates are normalised 0–1 by MediaPipe.
    // ──────────────────────────────────────────────────────────
    static computeROM(landmarkHistory) {
        if (!landmarkHistory.length) return {};

        const extract = key => landmarkHistory.map(lm => lm[key]).filter(Boolean);

        const rangeOf = (points, axis) => {
            const vals = points.map(p => p[axis]).filter(v => v != null);
            if (!vals.length) return 0;
            return Math.max(...vals) - Math.min(...vals);
        };

        const leftShoulder  = extract('leftShoulder');
        const leftElbow     = extract('leftElbow');
        const leftHip       = extract('leftHip');
        const leftWrist     = extract('leftWrist');

        return {
            // Shoulder abduction: horizontal range of shoulder
            shoulderAbduction: +(rangeOf(leftShoulder, 'x') * 100).toFixed(1),
            // Hip flexion: vertical range of hip
            hipFlexion:        +(rangeOf(leftHip,      'y') * 100).toFixed(1),
            // Elbow flexion: vertical range of elbow
            elbowFlexion:      +(rangeOf(leftElbow,    'y') * 100).toFixed(1),
            // Wrist reach: diagonal range of wrist
            wristReach:        +(rangeOf(leftWrist,    'x') * 100).toFixed(1)
        };
    }

    // ──────────────────────────────────────────────────────────
    // Reaction time — avg interval between gestures (ms)
    // ──────────────────────────────────────────────────────────
    static computeReactionTime(timestamps) {
        if (timestamps.length < 2) return 0;

        const sorted = [...timestamps].sort((a, b) => a - b);
        const intervals = [];
        for (let i = 1; i < sorted.length; i++) {
            intervals.push(sorted[i] - sorted[i - 1]);
        }
        return Math.round(intervals.reduce((a, b) => a + b, 0) / intervals.length);
    }

    // ──────────────────────────────────────────────────────────
    // Overall motor score (weighted average)
    // symmetry 40%, smoothness 30%, ROM 20%, reactionTime 10%
    // ──────────────────────────────────────────────────────────
    static computeOverallScore(symmetryScore, smoothnessScore, romScore, reactionTimeScore) {
        const weighted =
            symmetryScore    * 0.40 +
            smoothnessScore  * 0.30 +
            romScore         * 0.20 +
            reactionTimeScore* 0.10;
        return Math.round(Math.max(0, Math.min(100, weighted)));
    }

    // ──────────────────────────────────────────────────────────
    // Motor improvement vs previous session (%)
    // Returns null when no prior session exists.
    // ──────────────────────────────────────────────────────────
    static async computeMotorImprovement(playerID, currentScore) {
        const prev = await Session.findOne({
            where: { playerID },
            include: [{ model: Metrics, as: 'metrics', required: true }],
            order:  [['createdAt', 'DESC']],
            offset: 1,      // skip the current session (it's newest)
            limit:  1
        });

        if (!prev || !prev.metrics) return null;

        const prevScore = prev.metrics.overallMotorScore;
        if (!prevScore) return null;

        return +( ((currentScore - prevScore) / prevScore) * 100 ).toFixed(1);
    }

    // ── Private helpers ───────────────────────────────────────

    static _romToScore(rom) {
        // Map aggregate ROM to a 0–100 score.
        // Total summed ROM of ~100 (normalised units) → score = 100
        const total = Object.values(rom).reduce((a, b) => a + b, 0);
        return Math.min(100, total);
    }

    static _reactionTimeToScore(avgIntervalMs) {
        // Faster reaction = higher score.
        // 200ms → 100, 1000ms → 20, linear clamp.
        if (!avgIntervalMs || avgIntervalMs <= 0) return 50;
        const score = 100 - ((avgIntervalMs - 200) / 800) * 80;
        return Math.round(Math.max(0, Math.min(100, score)));
    }

    static _gestureSuccessRate(gestures) {
        if (!gestures.length) return 0;
        const detected = gestures.filter(g => g.iPadDetected || g.bandDetected).length;
        return +((detected / gestures.length) * 100).toFixed(1);
    }
}

module.exports = MetricsService;
