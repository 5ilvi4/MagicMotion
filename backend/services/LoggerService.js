// ============================================================
// services/LoggerService.js — Winston structured logger
// ============================================================

'use strict';

const { createLogger, format, transports } = require('winston');

const logger = createLogger({
    level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
    format: format.combine(
        format.timestamp(),
        format.errors({ stack: true }),
        process.env.NODE_ENV === 'production'
            ? format.json()
            : format.colorize({ all: true })
    ),
    transports: [
        new transports.Console(),
        // In production, add a file transport or ship to CloudWatch:
        // new transports.File({ filename: 'logs/error.log', level: 'error' })
    ]
});

module.exports = logger;
