-- ============================================================
-- seeds/demo.sql — Test data for development
-- Run with: psql $DATABASE_URL -f seeds/demo.sql
-- ============================================================

-- Demo therapist (password: "password123")
INSERT INTO therapists ("therapistID", name, email, "passwordHash", clinic, license)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Dr. Sarah Chen',
    'sarah.chen@motionclinic.example',
    '$2b$12$K8G3f9n1v7mR2L4pQ6tX8uY5wJ0eH3iA9cB7dE1fG2hI4jK6lM8n',  -- bcrypt of "password123"
    'Motion Rehab Clinic',
    'PT-12345'
)
ON CONFLICT DO NOTHING;

-- Demo player
INSERT INTO players ("playerID", "therapistID", name, "dateOfBirth", diagnosis)
VALUES (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001',
    'Alex Chen',
    '2018-03-15',
    'Hemiplegic cerebral palsy (left side)'
)
ON CONFLICT DO NOTHING;

-- Demo session
INSERT INTO sessions ("sessionID", "playerID", "therapistID", "gameType", "gameDuration", "gameScore", "startedAt", "completedAt", "deviceInfo")
VALUES (
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001',
    'subway_surfers',
    30,
    850,
    NOW() - INTERVAL '7 days',
    NOW() - INTERVAL '7 days' + INTERVAL '30 seconds',
    '{"model":"iPad Pro 12.9","osVersion":"17.4","appVersion":"1.0"}'
)
ON CONFLICT DO NOTHING;

-- Demo metrics
INSERT INTO metrics ("metricID", "sessionID", "symmetryScore", "smoothnessScore", rom, "reactionTime", "overallMotorScore", "motorImprovement", "gestureSuccessRate")
VALUES (
    '00000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000003',
    72.5,
    80.0,
    '{"shoulderAbduction":38.2,"hipFlexion":42.1,"elbowFlexion":65.3,"wristReach":28.9}',
    420,
    74,
    NULL,
    88.9
)
ON CONFLICT DO NOTHING;
