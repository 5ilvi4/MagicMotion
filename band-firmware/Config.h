#pragma once

// ============================================================
// Config.h — MotionMind Band Firmware Constants
// M5StickC PLUS2 (ESP32-PICO-V3-02)
// ============================================================

// ------------------------------------------------------------
// BLE UUIDs (Full 128-bit, SIG short form 0xFFF0 base)
// ------------------------------------------------------------
#define BLE_DEVICE_NAME       "MotionMind Band"
#define BLE_SERVICE_UUID      "0000fff0-0000-1000-8000-00805f9b34fb"
#define BLE_GESTURE_CHAR_UUID "0000fff1-0000-1000-8000-00805f9b34fb"
#define BLE_SESSION_CHAR_UUID "0000fff2-0000-1000-8000-00805f9b34fb"

// ------------------------------------------------------------
// Gesture Codes  (iPad → Band, 1-byte payload on 0xFFF1)
// ------------------------------------------------------------
#define GESTURE_CODE_NOP               0x00
#define GESTURE_CODE_LEAN_LEFT         0x01
#define GESTURE_CODE_LEAN_RIGHT        0x02
#define GESTURE_CODE_JUMP              0x03
#define GESTURE_CODE_SQUAT             0x04
#define GESTURE_CODE_DUCK              0x05
#define GESTURE_CODE_RAISE_ARM_LEFT    0x06
#define GESTURE_CODE_RAISE_ARM_RIGHT   0x07
#define GESTURE_CODE_TWIST             0x08
#define GESTURE_CODE_END_SESSION       0xFF

// ------------------------------------------------------------
// HID Keycodes  (USB HID Usage Table, Keyboard/Keypad page)
// ------------------------------------------------------------
#define HID_KEY_LEFT_ARROW    0x50
#define HID_KEY_RIGHT_ARROW   0x4F
#define HID_KEY_UP_ARROW      0x52
#define HID_KEY_DOWN_ARROW    0x51
#define HID_KEY_SPACEBAR      0x2C
#define HID_KEY_MINUS         0x2D
#define HID_KEY_NONE          0x00

// ------------------------------------------------------------
// Hardware Pin Assignments
// ------------------------------------------------------------
#define GPIO4_PMIC_WORKAROUND  4    // Must be pulled HIGH on PLUS2
#define VIBRATION_PIN          26   // Optional vibration motor GPIO

// ------------------------------------------------------------
// Power Management
// ------------------------------------------------------------
#define BATTERY_CRITICAL_THRESHOLD   5    // % → trigger shutdown
#define BATTERY_WARN_THRESHOLD       20   // % → show warning on TFT
#define BATTERY_CHECK_INTERVAL       10000 // ms between battery checks

// ------------------------------------------------------------
// IMU (MPU6886)
// ------------------------------------------------------------
#define IMU_SAMPLE_RATE_HZ     100   // Hz
#define JUMP_THRESHOLD         2.0f  // G-force to detect jump
#define SHAKE_THRESHOLD        1.5f  // Δ G-force to detect shake
#define JUMP_DEBOUNCE_MS       300   // ms minimum between jumps
#define IMU_CALIBRATION_SAMPLES 100  // Samples for baseline

// ------------------------------------------------------------
// Display
// ------------------------------------------------------------
#define DISPLAY_UPDATE_INTERVAL      100   // ms between screen refreshes
#define SESSION_SUMMARY_DISPLAY_MS   5000  // ms to show summary screen
#define DISPLAY_BRIGHTNESS           7     // 0–15 (AXP192 LCD backlight)

// ------------------------------------------------------------
// Loop Timing
// ------------------------------------------------------------
#define MAIN_LOOP_DELAY_MS     10    // 100Hz main loop
