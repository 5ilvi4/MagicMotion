// ============================================================
// routes/players.js — CRUD for therapy patients
// ============================================================

'use strict';

const express  = require('express');
const router   = express.Router();
const { v4: uuidv4 } = require('uuid');
const Joi      = require('joi');
const { Player } = require('../models');
const { authenticateToken } = require('../middleware/auth');

const playerSchema = Joi.object({
    name:        Joi.string().min(1).max(255).required(),
    dateOfBirth: Joi.string().isoDate().optional(),
    diagnosis:   Joi.string().max(512).optional(),
    notes:       Joi.string().max(2048).optional()
});

// ── POST /api/players — create new patient ───────────────────
router.post('/', authenticateToken, async (req, res, next) => {
    try {
        const { error, value } = playerSchema.validate(req.body);
        if (error) return res.status(400).json({ error: error.message });

        const player = await Player.create({
            playerID:    uuidv4(),
            therapistID: req.user.therapistID,
            ...value
        });

        await authenticateToken.audit(req, 'create_player', 'player', player.playerID);
        res.status(201).json(player);
    } catch (err) {
        next(err);
    }
});

// ── GET /api/players — list therapist's own patients ─────────
router.get('/', authenticateToken, async (req, res, next) => {
    try {
        const players = await Player.findAll({
            where: { therapistID: req.user.therapistID, deletedAt: null },
            order: [['name', 'ASC']]
        });
        res.json(players);
    } catch (err) {
        next(err);
    }
});

// ── GET /api/players/:playerID ────────────────────────────────
router.get('/:playerID', authenticateToken, async (req, res, next) => {
    try {
        const player = await _ownedPlayer(req.params.playerID, req.user.therapistID);
        if (!player) return res.status(404).json({ error: 'Player not found' });

        await authenticateToken.audit(req, 'read_player', 'player', player.playerID);
        res.json(player);
    } catch (err) {
        next(err);
    }
});

// ── PUT /api/players/:playerID — update patient record ───────
router.put('/:playerID', authenticateToken, async (req, res, next) => {
    try {
        const player = await _ownedPlayer(req.params.playerID, req.user.therapistID);
        if (!player) return res.status(404).json({ error: 'Player not found' });

        const { error, value } = playerSchema.validate(req.body);
        if (error) return res.status(400).json({ error: error.message });

        await player.update(value);
        await authenticateToken.audit(req, 'update_player', 'player', player.playerID);
        res.json(player);
    } catch (err) {
        next(err);
    }
});

// ── DELETE /api/players/:playerID — GDPR soft-delete ─────────
router.delete('/:playerID', authenticateToken, async (req, res, next) => {
    try {
        const player = await _ownedPlayer(req.params.playerID, req.user.therapistID);
        if (!player) return res.status(404).json({ error: 'Player not found' });

        // Soft-delete: set deletedAt; cron job purges after GDPR_SOFT_DELETE_EXPIRY_DAYS
        await player.update({ deletedAt: new Date() });
        await authenticateToken.audit(req, 'delete_player', 'player', player.playerID);

        res.json({ message: 'Player scheduled for deletion', deletedAt: player.deletedAt });
    } catch (err) {
        next(err);
    }
});

// ── Helper ────────────────────────────────────────────────────
async function _ownedPlayer(playerID, therapistID) {
    const p = await Player.findByPk(playerID);
    if (!p || p.deletedAt || p.therapistID !== therapistID) return null;
    return p;
}

module.exports = router;
