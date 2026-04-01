// ============================================================
// routes/reports.js — PDF / JSON session report generation
// Stores generated reports on S3; returns download URL.
// ============================================================

'use strict';

const express  = require('express');
const router   = express.Router();
const { v4: uuidv4 } = require('uuid');
const PDFDocument = require('pdfkit');
const AWS      = require('aws-sdk');

const { Session, Metrics, Gesture, Player, Report } = require('../models');
const { authenticateToken } = require('../middleware/auth');
const logger = require('../services/LoggerService');

const s3 = new AWS.S3({
    region:          process.env.AWS_REGION,
    accessKeyId:     process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
});

// ── POST /api/reports/generate/:sessionID ────────────────────
router.post('/generate/:sessionID', authenticateToken, async (req, res, next) => {
    try {
        const session = await _authorisedSession(req.params.sessionID, req.user.therapistID);
        if (!session) return res.status(404).json({ error: 'Session not found or access denied' });

        const metrics = await Metrics.findOne({ where: { sessionID: session.sessionID } });
        const player  = await Player.findByPk(session.playerID);

        if (!metrics) {
            return res.status(409).json({ error: 'Metrics not yet computed', code: 'METRICS_PENDING' });
        }

        const reportType = req.query.type || 'clinical_summary';
        const reportID   = uuidv4();

        const pdfBuffer = await _buildPDF(session, metrics, player, reportType);

        // Upload to S3
        const key = `reports/${session.playerID}/${session.sessionID}/${reportID}.pdf`;
        await s3.putObject({
            Bucket:      process.env.AWS_S3_BUCKET,
            Key:         key,
            Body:        pdfBuffer,
            ContentType: 'application/pdf',
            ServerSideEncryption: 'AES256'      // Encryption at rest (HIPAA)
        }).promise();

        const contentURL = `https://${process.env.AWS_S3_BUCKET}.s3.${process.env.AWS_REGION}.amazonaws.com/${key}`;

        const report = await Report.create({
            reportID,
            sessionID: session.sessionID,
            reportType,
            contentURL,
            format: 'pdf'
        });

        await authenticateToken.audit(req, 'generate_report', 'report', reportID);

        res.status(201).json({
            reportID: report.reportID,
            contentURL,
            generatedAt: report.createdAt
        });
    } catch (err) {
        next(err);
    }
});

// ── GET /api/reports/:reportID ────────────────────────────────
// Returns a signed S3 URL (valid 15 min) for secure download.
router.get('/:reportID', authenticateToken, async (req, res, next) => {
    try {
        const report  = await Report.findByPk(req.params.reportID);
        if (!report) return res.status(404).json({ error: 'Report not found' });

        // Authorisation
        const session = await _authorisedSession(report.sessionID, req.user.therapistID);
        if (!session) return res.status(403).json({ error: 'Access denied' });

        // Parse S3 key from full URL
        const key = report.contentURL.split('.amazonaws.com/')[1];
        const signedURL = s3.getSignedUrl('getObject', {
            Bucket:  process.env.AWS_S3_BUCKET,
            Key:     key,
            Expires: 900   // 15 minutes
        });

        await authenticateToken.audit(req, 'download_report', 'report', report.reportID);

        res.json({ signedURL, expiresIn: 900 });
    } catch (err) {
        next(err);
    }
});

// ── GET /api/reports/session/:sessionID ──────────────────────
router.get('/session/:sessionID', authenticateToken, async (req, res, next) => {
    try {
        const session = await _authorisedSession(req.params.sessionID, req.user.therapistID);
        if (!session) return res.status(404).json({ error: 'Session not found or access denied' });

        const reports = await Report.findAll({ where: { sessionID: req.params.sessionID } });
        res.json(reports);
    } catch (err) {
        next(err);
    }
});

// ── PDF Builder ───────────────────────────────────────────────
function _buildPDF(session, metrics, player, reportType) {
    return new Promise((resolve, reject) => {
        const doc    = new PDFDocument({ size: 'A4', margin: 50 });
        const chunks = [];

        doc.on('data',  chunk => chunks.push(chunk));
        doc.on('end',   ()    => resolve(Buffer.concat(chunks)));
        doc.on('error', reject);

        // Header
        doc.fontSize(20).text('MotionMind — Clinical Session Report', { align: 'center' });
        doc.moveDown(0.5);
        doc.fontSize(10).text(`Report type: ${reportType}`, { align: 'center' });
        doc.moveDown(1);

        // Patient info
        doc.fontSize(14).text('Patient Information');
        doc.moveTo(50, doc.y).lineTo(545, doc.y).stroke();
        doc.moveDown(0.3);
        doc.fontSize(11)
            .text(`Name:       ${player?.name || 'Unknown'}`)
            .text(`Diagnosis:  ${player?.diagnosis || '—'}`)
            .text(`Session ID: ${session.sessionID}`)
            .text(`Date:       ${session.startedAt?.toISOString().split('T')[0] || '—'}`)
            .text(`Duration:   ${session.gameDuration}s`)
            .text(`Game score: ${session.gameScore ?? '—'}`);

        doc.moveDown(1);

        // Clinical metrics
        doc.fontSize(14).text('Motor Quality Metrics');
        doc.moveTo(50, doc.y).lineTo(545, doc.y).stroke();
        doc.moveDown(0.3);
        doc.fontSize(11)
            .text(`Overall Motor Score: ${metrics.overallMotorScore?.toFixed(1) ?? '—'} / 100`)
            .text(`Symmetry Score:      ${metrics.symmetryScore?.toFixed(1) ?? '—'} / 100`)
            .text(`Smoothness Score:    ${metrics.smoothnessScore?.toFixed(1) ?? '—'} / 100`)
            .text(`Reaction Time:       ${metrics.reactionTime?.toFixed(0) ?? '—'} ms`)
            .text(`Gesture Success:     ${metrics.gestureSuccessRate?.toFixed(1) ?? '—'} %`)
            .text(`Motor Improvement:   ${metrics.motorImprovement != null ? metrics.motorImprovement.toFixed(1) + ' %' : 'N/A (first session)'}`);

        doc.moveDown(0.5);

        // ROM
        if (metrics.rom) {
            doc.fontSize(12).text('Range of Motion');
            for (const [k, v] of Object.entries(metrics.rom)) {
                doc.fontSize(11).text(`  ${k}: ${v}%`);
            }
        }

        doc.moveDown(1);

        // Interpretation
        const score = metrics.overallMotorScore ?? 0;
        const interp = score >= 70 ? 'Mild — within expected range for age group'
                     : score >= 50 ? 'Moderate — below average; continued therapy recommended'
                     :               'Severe — significant motor impairment noted';

        doc.fontSize(14).text('Clinical Interpretation');
        doc.moveTo(50, doc.y).lineTo(545, doc.y).stroke();
        doc.moveDown(0.3);
        doc.fontSize(11).text(interp);

        doc.moveDown(2);
        doc.fontSize(8).text(
            'This report is generated automatically from sensor data. Confirm findings with clinical assessment.',
            { align: 'center', color: 'grey' }
        );

        doc.end();
    });
}

// ── Auth helper ───────────────────────────────────────────────
async function _authorisedSession(sessionID, therapistID) {
    const session = await Session.findByPk(sessionID, { attributes: ['sessionID', 'playerID', 'startedAt', 'gameDuration', 'gameScore'] });
    if (!session) return null;

    const player = await Player.findByPk(session.playerID, { attributes: ['therapistID'] });
    if (player?.therapistID !== therapistID) return null;

    return session;
}

module.exports = router;
