// ============================================================
// middleware/auth.js — JWT verification + rate-limiting
// ============================================================

'use strict';

const jwt        = require('jsonwebtoken');
const rateLimit  = require('express-rate-limit');
const { createClient } = require('redis');
const { RedisStore }   = require('rate-limit-redis');
const { AuditLog }     = require('../models');
const logger           = require('../services/LoggerService');

// ── Redis client (shared) ─────────────────────────────────────
let redisClient;
async function getRedis() {
    if (!redisClient) {
        redisClient = createClient({ url: process.env.REDIS_URL });
        redisClient.on('error', err => logger.error('Redis error', { err }));
        await redisClient.connect();
    }
    return redisClient;
}

// ── Verify JWT Bearer token ────────────────────────────────────
async function authenticateToken(req, res, next) {
    const header = req.headers['authorization'];
    const token  = header && header.startsWith('Bearer ') && header.slice(7);

    if (!token) {
        return res.status(401).json({ error: 'No token provided', code: 'AUTH_MISSING' });
    }

    try {
        const payload = jwt.verify(token, process.env.JWT_SECRET);
        req.user = payload;                 // { therapistID, email, iat, exp }
        await _audit(req, 'auth_token_used');
        next();
    } catch (err) {
        const code = err.name === 'TokenExpiredError' ? 'AUTH_EXPIRED' : 'AUTH_INVALID';
        return res.status(403).json({ error: 'Invalid or expired token', code });
    }
}

// ── Verify therapist owns the player resource ──────────────────
async function authorizeTherapist(req, res, next) {
    try {
        const { Player } = require('../models');
        const playerID   = req.params.playerID || req.body.playerID;

        if (!playerID) return next();

        const player = await Player.findByPk(playerID, { attributes: ['therapistID'] });
        if (!player) {
            return res.status(404).json({ error: 'Player not found' });
        }
        if (player.therapistID !== req.user.therapistID) {
            return res.status(403).json({ error: 'Access denied', code: 'FORBIDDEN' });
        }
        next();
    } catch (err) {
        next(err);
    }
}

// ── Rate limiter: 100 uploads / therapist / day ────────────────
async function buildUploadRateLimiter() {
    const redis = await getRedis();
    return rateLimit({
        windowMs: 24 * 60 * 60 * 1000,  // 24 hours
        max: parseInt(process.env.UPLOAD_RATE_LIMIT_PER_DAY || '100', 10),
        keyGenerator: req => req.user ? req.user.therapistID : req.ip,
        store: new RedisStore({ sendCommand: (...args) => redis.sendCommand(args) }),
        handler: (_req, res) => res.status(429).json({
            error: 'Upload rate limit exceeded (max 100 per day)',
            code: 'RATE_LIMIT_UPLOAD'
        })
    });
}

// ── Rate limiter: 60 requests / IP / minute (general API) ─────
async function buildApiRateLimiter() {
    const redis = await getRedis();
    return rateLimit({
        windowMs: 60 * 1000,
        max: parseInt(process.env.API_RATE_LIMIT_PER_MIN || '60', 10),
        store: new RedisStore({ sendCommand: (...args) => redis.sendCommand(args) }),
        handler: (_req, res) => res.status(429).json({
            error: 'Too many requests',
            code: 'RATE_LIMIT_API'
        })
    });
}

// ── HIPAA Audit log helper ─────────────────────────────────────
async function _audit(req, action, resourceType = null, resourceID = null) {
    try {
        await AuditLog.create({
            userID:       req.user?.therapistID || null,
            userType:     req.user ? 'therapist' : 'anonymous',
            action,
            resourceType,
            resourceID,
            ipAddress:    req.ip,
            requestId:    req.requestId
        });
    } catch (e) {
        logger.warn('Audit log write failed', { e: e.message });
    }
}

// Export audit helper so routes can use it
authenticateToken.audit = _audit;

module.exports = {
    authenticateToken,
    authorizeTherapist,
    buildUploadRateLimiter,
    buildApiRateLimiter
};
