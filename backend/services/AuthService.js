// ============================================================
// services/AuthService.js — JWT generation + OAuth2 helpers
// ============================================================

'use strict';

const jwt      = require('jsonwebtoken');
const bcrypt   = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const { Therapist, ApiKey } = require('../models');
const logger   = require('./LoggerService');

class AuthService {

    // ── Sign a short-lived access token ──────────────────────
    static signAccessToken(therapist) {
        return jwt.sign(
            { therapistID: therapist.therapistID, email: therapist.email },
            process.env.JWT_SECRET,
            { expiresIn: process.env.JWT_EXPIRES_IN || '24h' }
        );
    }

    // ── Sign a long-lived refresh token ──────────────────────
    static signRefreshToken(therapist) {
        return jwt.sign(
            { therapistID: therapist.therapistID, type: 'refresh' },
            process.env.JWT_REFRESH_SECRET,
            { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '7d' }
        );
    }

    // ── Verify a token — use correct secret by type ───────────
    static verifyToken(token) {
        // Decode header without verification to detect token type
        const decoded = jwt.decode(token);
        const secret = decoded?.type === 'refresh'
            ? process.env.JWT_REFRESH_SECRET
            : process.env.JWT_SECRET;
        return jwt.verify(token, secret);
    }

    // ── Email / password login ────────────────────────────────
    static async loginWithPassword(email, password) {
        const therapist = await Therapist.findOne({
            where: { email: email.toLowerCase().trim(), deletedAt: null }
        });

        if (!therapist || !therapist.passwordHash) {
            return { success: false, error: 'Invalid credentials' };
        }

        const valid = await bcrypt.compare(password, therapist.passwordHash);
        if (!valid) {
            return { success: false, error: 'Invalid credentials' };
        }

        logger.info('Therapist login', { therapistID: therapist.therapistID });
        return {
            success:      true,
            accessToken:  this.signAccessToken(therapist),
            refreshToken: this.signRefreshToken(therapist),
            therapist:    { therapistID: therapist.therapistID, email: therapist.email, name: therapist.name }
        };
    }

    // ── OAuth2 upsert (Google sign-in) ────────────────────────
    static async upsertGoogleUser(profile) {
        const email = profile.emails?.[0]?.value?.toLowerCase();
        if (!email) throw new Error('Google profile missing email');

        let therapist = await Therapist.findOne({ where: { googleID: profile.id } });

        if (!therapist) {
            therapist = await Therapist.findOne({ where: { email } });
        }

        if (therapist) {
            // Update google ID if missing
            if (!therapist.googleID) await therapist.update({ googleID: profile.id });
        } else {
            therapist = await Therapist.create({
                name:     profile.displayName,
                email,
                googleID: profile.id
            });
        }

        return {
            accessToken:  this.signAccessToken(therapist),
            refreshToken: this.signRefreshToken(therapist),
            therapist:    { therapistID: therapist.therapistID, email, name: therapist.name }
        };
    }

    // ── Generate device API key (for iPad) ───────────────────
    static async generateApiKey(therapistID, name) {
        const key = `mm_${uuidv4().replace(/-/g, '')}`;

        const apiKey = await ApiKey.create({
            therapistID,
            key,
            name,
            expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)  // 1 year
        });

        logger.info('API key generated', { therapistID, keyID: apiKey.keyID });
        return { keyID: apiKey.keyID, key, expiresAt: apiKey.expiresAt };
    }

    // ── Validate an API key (device auth path) ───────────────
    static async validateApiKey(rawKey) {
        const apiKey = await ApiKey.findOne({
            where:   { key: rawKey },
            include: ['therapist']
        });

        if (!apiKey) return null;
        if (apiKey.expiresAt && apiKey.expiresAt < new Date()) return null;

        return apiKey.therapist;
    }

    // ── Hash a password ───────────────────────────────────────
    static async hashPassword(plaintext) {
        return bcrypt.hash(plaintext, 12);
    }
}

module.exports = AuthService;
