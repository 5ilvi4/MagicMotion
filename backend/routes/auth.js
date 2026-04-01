// ============================================================
// routes/auth.js — Login, refresh, Google OAuth, API keys
// ============================================================

'use strict';

const express       = require('express');
const router        = express.Router();
const passport      = require('passport');
const GoogleStrategy= require('passport-google-oauth20').Strategy;
const AuthService   = require('../services/AuthService');
const { authenticateToken } = require('../middleware/auth');

// ── Configure Google OAuth strategy ─────────────────────────
passport.use(new GoogleStrategy({
    clientID:     process.env.GOOGLE_CLIENT_ID,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET,
    callbackURL:  process.env.GOOGLE_CALLBACK_URL
}, async (_accessToken, _refreshToken, profile, done) => {
    try {
        const result = await AuthService.upsertGoogleUser(profile);
        done(null, result);
    } catch (err) {
        done(err);
    }
}));

// ── POST /api/auth/login — email + password ───────────────────
router.post('/login', async (req, res, next) => {
    try {
        const { email, password } = req.body;
        if (!email || !password) {
            return res.status(400).json({ error: 'email and password required' });
        }

        const result = await AuthService.loginWithPassword(email, password);
        if (!result.success) {
            return res.status(401).json({ error: result.error });
        }

        res.json(result);
    } catch (err) {
        next(err);
    }
});

// ── POST /api/auth/refresh — swap refresh token for new access token
router.post('/refresh', async (req, res, next) => {
    try {
        const { refreshToken } = req.body;
        if (!refreshToken) {
            return res.status(400).json({ error: 'refreshToken required' });
        }

        const payload = AuthService.verifyToken(refreshToken);
        if (payload.type !== 'refresh') {
            return res.status(403).json({ error: 'Not a refresh token' });
        }

        const { Therapist } = require('../models');
        const therapist = await Therapist.findByPk(payload.therapistID);
        if (!therapist || therapist.deletedAt) {
            return res.status(403).json({ error: 'Account not found' });
        }

        res.json({ accessToken: AuthService.signAccessToken(therapist) });
    } catch (err) {
        if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError') {
            return res.status(403).json({ error: 'Invalid refresh token' });
        }
        next(err);
    }
});

// ── Google OAuth ─────────────────────────────────────────────
router.get('/google',
    passport.authenticate('google', { scope: ['profile', 'email'], session: false })
);

router.get('/google/callback',
    passport.authenticate('google', { session: false, failureRedirect: '/api/auth/google/fail' }),
    (req, res) => {
        // On success req.user = { accessToken, refreshToken, therapist }
        res.json(req.user);
    }
);

router.get('/google/fail', (_req, res) => {
    res.status(401).json({ error: 'Google authentication failed' });
});

// ── POST /api/auth/apikey — generate device API key ──────────
router.post('/apikey', authenticateToken, async (req, res, next) => {
    try {
        const { name } = req.body;
        const result = await AuthService.generateApiKey(
            req.user.therapistID,
            name || 'iPad Device'
        );
        res.json(result);
    } catch (err) {
        next(err);
    }
});

module.exports = router;
