// ============================================================
// services/MetricsQueue.js — Bull async job queue for metrics
// Keeps the upload endpoint fast (<500ms) by computing metrics
// in the background.
// ============================================================

'use strict';

const Bull         = require('bull');
const MetricsService = require('./MetricsService');
const logger       = require('./LoggerService');

const queue = new Bull('metricsComputation', process.env.REDIS_URL);

// ── Worker ────────────────────────────────────────────────────
queue.process(async job => {
    const { sessionID, gestures } = job.data;
    logger.info(`[Queue] Computing metrics for session ${sessionID}`);
    await MetricsService.computeAndStore(sessionID, gestures);
    logger.info(`[Queue] Metrics done for session ${sessionID}`);
});

queue.on('failed', (job, err) => {
    logger.error(`[Queue] Job ${job.id} failed: ${err.message}`);
});

// ── Add a job ─────────────────────────────────────────────────
function enqueue(sessionID, gestures) {
    queue.add({ sessionID, gestures }, {
        attempts: 3,
        backoff: { type: 'exponential', delay: 2000 }
    });
}

module.exports = { enqueue };
