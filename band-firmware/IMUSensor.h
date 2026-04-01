#pragma once

// ============================================================
// IMUSensor.h — MPU6886 wrapper (M5StickC PLUS2)
// Samples at IMU_SAMPLE_RATE_HZ, detects gross motor events.
// ============================================================

#include <Arduino.h>
#include <M5StickCPlus2.h>
#include "Config.h"

// ============================================================
class IMUSensor {
public:

    // --------------------------------------------------------
    // Initialise MPU6886 and run baseline calibration.
    // Call once in setup().
    // --------------------------------------------------------
    void begin() {
        int rc = M5.IMU.Init();
        if (rc != 0) {
            Serial.printf("[IMU] Init failed (rc=%d) — IMU disabled\n", rc);
            _available = false;
            return;
        }
        _available = true;
        Serial.println("[IMU] MPU6886 init OK");
        _calibrate();
    }

    bool isAvailable() const { return _available; }

    // --------------------------------------------------------
    // Read latest accel + gyro data from MPU6886.
    // Call at IMU_SAMPLE_RATE_HZ or faster.
    // --------------------------------------------------------
    void update() {
        if (!_available) return;
        M5.IMU.getAccelData(&_aX, &_aY, &_aZ);
        M5.IMU.getGyroData (&_gX, &_gY, &_gZ);
    }

    // --------------------------------------------------------
    // Returns true once when a jump is detected.
    // Debounced — fires at most once per JUMP_DEBOUNCE_MS.
    // --------------------------------------------------------
    bool detectJump() {
        if (!_available) return false;
        update();

        // Total acceleration magnitude (gravity-compensated)
        float mag = sqrtf(_aX*_aX + _aY*_aY + _aZ*_aZ);

        // Remove baseline gravity (measured during calibration)
        float delta = fabsf(mag - _baselineMag);

        if (delta > JUMP_THRESHOLD) {
            uint32_t now = millis();
            if (now - _lastJumpMs > JUMP_DEBOUNCE_MS) {
                _lastJumpMs = now;
                Serial.printf("[IMU] Jump detected (mag=%.2f, delta=%.2f)\n", mag, delta);
                return true;
            }
        }
        return false;
    }

    // --------------------------------------------------------
    // Returns true when a shake is detected (high Δaccel).
    // --------------------------------------------------------
    bool detectShake() {
        if (!_available) return false;
        update();

        float delta = fabsf(_aX - _prevAX) +
                      fabsf(_aY - _prevAY) +
                      fabsf(_aZ - _prevAZ);

        _prevAX = _aX; _prevAY = _aY; _prevAZ = _aZ;

        return delta > SHAKE_THRESHOLD;
    }

    // --------------------------------------------------------
    // Raw getters (for future gesture ML on-device)
    // --------------------------------------------------------
    float accelX() const { return _aX; }
    float accelY() const { return _aY; }
    float accelZ() const { return _aZ; }
    float gyroX()  const { return _gX; }
    float gyroY()  const { return _gY; }
    float gyroZ()  const { return _gZ; }

private:
    bool  _available   = false;

    float _aX = 0, _aY = 0, _aZ = 0;
    float _gX = 0, _gY = 0, _gZ = 0;

    float _prevAX = 0, _prevAY = 0, _prevAZ = 0;
    float _baselineMag = 1.0f;  // Approximately 1G at rest

    uint32_t _lastJumpMs = 0;

    // --------------------------------------------------------
    // Average IMU_CALIBRATION_SAMPLES readings at rest to
    // establish gravity baseline (should be ~1.0 G).
    // --------------------------------------------------------
    void _calibrate() {
        Serial.println("[IMU] Calibrating — hold device still for 1 second...");

        float sumMag = 0;
        for (int i = 0; i < IMU_CALIBRATION_SAMPLES; i++) {
            M5.IMU.getAccelData(&_aX, &_aY, &_aZ);
            sumMag += sqrtf(_aX*_aX + _aY*_aY + _aZ*_aZ);
            delay(10);
        }
        _baselineMag = sumMag / IMU_CALIBRATION_SAMPLES;

        Serial.printf("[IMU] Calibration done — baseline G = %.3f\n", _baselineMag);
    }
};
