// ============================================================
// server.js — MotionMind Backend Entry Point
// Node.js / Express + PostgreSQL + Redis
// ============================================================

'use strict';

require('dotenv').config();

const express    = require('express');
const helmet     = require('helmet');
const cors       = require('cors');
const compression = require('compression');
const morgan     = require('morgan');

const { sequelize } = require('./models');
const logger        = require('./services/LoggerService');

const app = express();

// ── Security & Transport Middleware ──────────────────────────
app.use(helmet());
app.use(cors({
    origin: process.env.CORS_ORIGIN || '*',
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(compression());
app.use(express.json({ limit: '10mb' }));   // accommodate large landmark payloads
app.use(express.urlencoded({ extended: true }));

// ── Request Logging ──────────────────────────────────────────
app.use(morgan('combined', {
    stream: { write: msg => logger.info(msg.trim()) }
}));

// ── Audit Log Middleware ──────────────────────────────────────
// Attaches a requestID to every request for HIPAA audit trail.
app.use((req, _res, next) => {
    req.requestId = require('uuid').v4();
    next();
});

// ── Routes ────────────────────────────────────────────────────
app.use('/api/auth',     require('./routes/auth'));
app.use('/api/players',  require('./routes/players'));
app.use('/api/sessions', require('./routes/sessions'));
app.use('/api/metrics',  require('./routes/metrics'));
app.use('/api/reports',  require('./routes/reports'));

// ── Health Check ──────────────────────────────────────────────
app.get('/health', async (_req, res) => {
    let dbStatus = 'ok';
    try { await sequelize.authenticate(); }
    catch { dbStatus = 'error'; }

    res.json({
        status: dbStatus === 'ok' ? 'ok' : 'degraded',
        db: dbStatus,
        timestamp: new Date().toISOString(),
        version: '1.0.0'
    });
});

// ── 404 handler ───────────────────────────────────────────────
app.use((_req, res) => {
    res.status(404).json({ error: 'Not found' });
});

// ── Global Error Handler ──────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, _next) => {
    logger.error(`[${req.requestId}] ${err.message}`, { stack: err.stack });
    res.status(err.statusCode || 500).json({
        error: err.message || 'Internal server error',
        code:  err.code    || 'INTERNAL_ERROR',
        requestId: req.requestId
    });
});

// ── Startup ───────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;

(async () => {
    try {
        await sequelize.authenticate();
        logger.info('✓ PostgreSQL connected');

        // Sync models in development only (use migrations in production)
        if (process.env.NODE_ENV === 'development') {
            await sequelize.sync({ alter: true });
            logger.info('✓ Database schema synced');
        }

        app.listen(PORT, () => {
            logger.info(`✓ MotionMind backend listening on port ${PORT} (${process.env.NODE_ENV})`);
        });
    } catch (err) {
        logger.error('✗ Failed to start server', { error: err.message });
        process.exit(1);
    }
})();

module.exports = app;   // export for testing
