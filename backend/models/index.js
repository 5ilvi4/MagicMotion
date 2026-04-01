// ============================================================
// models/index.js — Sequelize models + associations
// PostgreSQL (pg driver)
// ============================================================

'use strict';

const { Sequelize, DataTypes } = require('sequelize');

const sequelize = new Sequelize(process.env.DATABASE_URL, {
    dialect:  'postgres',
    logging:  process.env.NODE_ENV === 'development' ? console.log : false,
    pool: { max: 10, min: 2, idle: 30000 }
});

// ── Therapists ────────────────────────────────────────────────
const Therapist = sequelize.define('Therapist', {
    therapistID: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
    name:        { type: DataTypes.TEXT, allowNull: false },
    email:       { type: DataTypes.TEXT, unique: true, allowNull: false },
    passwordHash:{ type: DataTypes.TEXT },                 // null for OAuth-only accounts
    clinic:      { type: DataTypes.TEXT },
    license:     { type: DataTypes.TEXT },                 // medical license number
    googleID:    { type: DataTypes.TEXT, unique: true },   // OAuth2 sub
    deletedAt:   { type: DataTypes.DATE }                  // soft-delete
}, { timestamps: true, tableName: 'therapists' });

// ── Players ───────────────────────────────────────────────────
const Player = sequelize.define('Player', {
    playerID:    { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
    therapistID: { type: DataTypes.UUID, allowNull: false },
    name:        { type: DataTypes.TEXT, allowNull: false },
    dateOfBirth: { type: DataTypes.DATEONLY },
    diagnosis:   { type: DataTypes.TEXT },
    notes:       { type: DataTypes.TEXT },
    deletedAt:   { type: DataTypes.DATE }                  // GDPR soft-delete
}, { timestamps: true, tableName: 'players' });

// ── API Keys (iPad app auth) ──────────────────────────────────
const ApiKey = sequelize.define('ApiKey', {
    keyID:       { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
    therapistID: { type: DataTypes.UUID, allowNull: false },
    key:         { type: DataTypes.TEXT, unique: true, allowNull: false },
    name:        { type: DataTypes.TEXT },
    expiresAt:   { type: DataTypes.DATE }
}, { timestamps: true, tableName: 'api_keys' });

// ── Sessions ──────────────────────────────────────────────────
const Session = sequelize.define('Session', {
    sessionID:   { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
    playerID:    { type: DataTypes.UUID, allowNull: false },
    therapistID: { type: DataTypes.UUID, allowNull: false },
    gameType:    { type: DataTypes.STRING(64), defaultValue: 'subway_surfers' },
    gameDuration:{ type: DataTypes.INTEGER },               // seconds
    gameScore:   { type: DataTypes.INTEGER },
    startedAt:   { type: DataTypes.DATE },
    completedAt: { type: DataTypes.DATE },
    deviceInfo:  { type: DataTypes.JSONB }                  // iPad model, iOS version, etc.
}, { timestamps: true, tableName: 'sessions' });

// ── Gestures ──────────────────────────────────────────────────
const Gesture = sequelize.define('Gesture', {
    gestureID:    { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
    sessionID:    { type: DataTypes.UUID, allowNull: false },
    gestureType:  { type: DataTypes.STRING(64) },
    timestamp:    { type: DataTypes.INTEGER },               // ms into session
    confidence:   { type: DataTypes.FLOAT },                 // 0.0 – 1.0
    iPadDetected: { type: DataTypes.BOOLEAN, defaultValue: false },
    bandDetected: { type: DataTypes.BOOLEAN, defaultValue: false },
    landmarks:    { type: DataTypes.JSONB }                  // 33-point pose dict
}, { timestamps: true, tableName: 'gestures' });

// ── Metrics ───────────────────────────────────────────────────
const Metrics = sequelize.define('Metrics', {
    metricID:           { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
    sessionID:          { type: DataTypes.UUID, unique: true, allowNull: false },
    symmetryScore:      { type: DataTypes.FLOAT },           // 0 – 100
    smoothnessScore:    { type: DataTypes.FLOAT },           // 0 – 100
    rom:                { type: DataTypes.JSONB },            // { shoulder, hip, elbow }
    reactionTime:       { type: DataTypes.FLOAT },           // ms
    overallMotorScore:  { type: DataTypes.FLOAT },           // 0 – 100
    motorImprovement:   { type: DataTypes.FLOAT },           // % vs previous session
    gestureSuccessRate: { type: DataTypes.FLOAT },           // 0 – 100
    computedAt:         { type: DataTypes.DATE, defaultValue: DataTypes.NOW }
}, { timestamps: true, tableName: 'metrics' });

// ── Reports ───────────────────────────────────────────────────
const Report = sequelize.define('Report', {
    reportID:    { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
    sessionID:   { type: DataTypes.UUID, allowNull: false },
    reportType:  { type: DataTypes.STRING(64) },              // "clinical_summary", etc.
    contentURL:  { type: DataTypes.TEXT },                    // S3 URL
    format:      { type: DataTypes.STRING(16), defaultValue: 'pdf' }
}, { timestamps: true, tableName: 'reports' });

// ── Audit Log (HIPAA) ─────────────────────────────────────────
const AuditLog = sequelize.define('AuditLog', {
    logID:       { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
    userID:      { type: DataTypes.UUID },
    userType:    { type: DataTypes.STRING(32) },              // "therapist", "system"
    action:      { type: DataTypes.STRING(64) },              // "read_session", "upload", etc.
    resourceType:{ type: DataTypes.STRING(64) },
    resourceID:  { type: DataTypes.UUID },
    ipAddress:   { type: DataTypes.STRING(45) },
    requestId:   { type: DataTypes.UUID }
}, { timestamps: true, tableName: 'audit_logs', updatedAt: false });

// ── Associations ──────────────────────────────────────────────
Therapist.hasMany(Player,   { foreignKey: 'therapistID', as: 'players' });
Player.belongsTo(Therapist, { foreignKey: 'therapistID', as: 'therapist' });

Therapist.hasMany(ApiKey,   { foreignKey: 'therapistID', as: 'apiKeys' });
ApiKey.belongsTo(Therapist, { foreignKey: 'therapistID' });

Player.hasMany(Session,     { foreignKey: 'playerID', as: 'sessions' });
Session.belongsTo(Player,   { foreignKey: 'playerID', as: 'player' });

Session.hasMany(Gesture,    { foreignKey: 'sessionID', as: 'gestures' });
Gesture.belongsTo(Session,  { foreignKey: 'sessionID' });

Session.hasOne(Metrics,     { foreignKey: 'sessionID', as: 'metrics' });
Metrics.belongsTo(Session,  { foreignKey: 'sessionID' });

Session.hasMany(Report,     { foreignKey: 'sessionID', as: 'reports' });
Report.belongsTo(Session,   { foreignKey: 'sessionID' });

module.exports = {
    sequelize, Sequelize,
    Therapist, Player, ApiKey,
    Session, Gesture, Metrics, Report, AuditLog
};
