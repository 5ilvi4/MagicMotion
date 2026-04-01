// ============================================================
// MotionMindBandFirmware.ino — Main Sketch
// M5StickC PLUS2 (ESP32-PICO-V3-02)
// Firmware v1.0
//
// Roles:
//   • BLE GATT Peripheral — receives gesture bytes from iPad
//   • BLE HID Keyboard    — broadcasts keystrokes to iOS game
//   • IMU direct path     — jump detection without iPad round-trip
//
// Data flow:
//   iPad → BLE Write [0x01] → GATT onWrite → GestureMapping
//       → HID sendKey(LEFT_ARROW) → iOS foreground app
// ============================================================

#include <Arduino.h>
#include <M5StickCPlus2.h>

#include "Config.h"
#include "BLEGATTServer.h"
#include "HIDGamepad.h"
#include "GestureMapping.h"
#include "DisplayManager.h"
#include "IMUSensor.h"

// ============================================================
// Global instances
// ============================================================
BLEGATTServer  bleServer;
HIDGamepad     hidGamepad;
DisplayManager display;
IMUSensor      imuSensor;

// Shared mutable session state (updated by BLE callbacks + loop)
SessionState session;

// Timing
uint32_t lastBatteryCheckMs  = 0;
uint32_t lastDisplayUpdateMs = 0;

// ============================================================
// Forward declarations
// ============================================================
void onGestureReceived(uint8_t code);
void onSessionUpdate(const SessionMetadata& meta);
void onBLEConnect();
void onBLEDisconnect();
void handleEndSession();
void vibrate(uint16_t ms);
void updateBatteryDisplay();

// ============================================================
// setup()
// ============================================================
void setup() {
    // 1. Init M5StickC PLUS2 hardware
    M5.begin();
    delay(100);

    // 2. GPIO4 pull-HIGH (AXP192 PMIC removal workaround on PLUS2)
    pinMode(GPIO4_PMIC_WORKAROUND, OUTPUT);
    digitalWrite(GPIO4_PMIC_WORKAROUND, HIGH);

    // 3. Serial debug
    Serial.begin(115200);
    Serial.println("==============================");
    Serial.println(" MotionMind Band Firmware v1.0");
    Serial.println("==============================");

    // 4. TFT display
    display.begin();
    display.showStatus("Booting...", TFT_WHITE);

    // 5. IMU (non-fatal if absent)
    imuSensor.begin();
    if (!imuSensor.isAvailable()) {
        display.showStatus("IMU: FAIL (BLE only)", TFT_RED);
        delay(1000);
    }

    // 6. BLE GATT server (advertises 0xFFF0 service)
    bleServer.onGesture(onGestureReceived);
    bleServer.onSessionUpdate(onSessionUpdate);
    bleServer.onConnect(onBLEConnect);
    bleServer.onDisconnect(onBLEDisconnect);
    bleServer.begin();

    // 7. BLE HID keyboard (advertises as wireless keyboard)
    hidGamepad.begin();

    // 8. Initial idle screen
    display.showDefault(false, 100);

    Serial.println("[Setup] Complete — waiting for iPad...");
}

// ============================================================
// loop()
// ============================================================
void loop() {
    M5.update();  // Poll buttons

    // ----------------------------------------------------------
    // A. Process GATT gesture (poll-style fallback)
    //    Callbacks fire directly, but consuming here is safe too
    // ----------------------------------------------------------
    if (bleServer.hasNewGesture()) {
        uint8_t code = bleServer.consumeGesture();
        onGestureReceived(code);
    }

    // ----------------------------------------------------------
    // B. IMU gross motor — direct HID path (no iPad round-trip)
    // ----------------------------------------------------------
    if (imuSensor.isAvailable() && imuSensor.detectJump()) {
        Serial.println("[IMU] Jump → HID SPACEBAR");
        hidGamepad.sendKey(HID_KEY_SPACEBAR);
        session.gestureCount++;
        session.lastGestureName = "JUMP (IMU)";
        vibrate(80);
    }

    // ----------------------------------------------------------
    // C. Update display at DISPLAY_UPDATE_INTERVAL
    // ----------------------------------------------------------
    uint32_t now = millis();
    if (now - lastDisplayUpdateMs >= DISPLAY_UPDATE_INTERVAL) {
        lastDisplayUpdateMs = now;

        uint8_t batt = _batteryPercent();
        hidGamepad.setBatteryLevel(batt);

        if (display.summaryExpired()) {
            // Summary screen timeout → return to idle
            session = SessionState{};
            display.invalidate();
        }

        if (session.gameRunning) {
            display.showSession(session, batt);
        } else {
            display.showDefault(bleServer.isClientConnected(), batt);
        }
    }

    // ----------------------------------------------------------
    // D. Battery critical check
    // ----------------------------------------------------------
    if (now - lastBatteryCheckMs >= BATTERY_CHECK_INTERVAL) {
        lastBatteryCheckMs = now;
        uint8_t batt = _batteryPercent();
        if (batt < BATTERY_CRITICAL_THRESHOLD) {
            Serial.println("[Power] Battery critical — shutting down");
            display.showStatus("Battery Critical!", TFT_RED);
            delay(2000);
            M5.Power.powerOff();
        }
    }

    // ----------------------------------------------------------
    // E. Button A (big side button) — manual session reset
    // ----------------------------------------------------------
    if (M5.BtnA.wasPressed()) {
        Serial.println("[Button] Manual session reset");
        session = SessionState{};
        display.invalidate();
    }

    delay(MAIN_LOOP_DELAY_MS);
}

// ============================================================
// BLE Callbacks
// ============================================================

void onGestureReceived(uint8_t code) {
    Serial.printf("[Gesture] code=0x%02X (%s)\n",
                  code, GestureMapping::getName(code));

    // Handle end-of-session sentinel
    if (code == GESTURE_CODE_END_SESSION) {
        handleEndSession();
        return;
    }

    // Look up HID keycode
    uint8_t hidKey = GestureMapping::getHIDKey(code);

    if (hidKey != HID_KEY_NONE) {
        hidGamepad.sendKey(hidKey);
        session.gestureCount++;
        session.lastGestureName = GestureMapping::getName(code);
        vibrate(40);

        Serial.printf("[HID]     → %s (0x%02X)\n",
                      GestureMapping::hidKeyName(hidKey), hidKey);
    } else {
        // Valid code but no HID mapping (future gestures, NOP, etc.)
        if (code != GESTURE_CODE_NOP) {
            Serial.printf("[Gesture] No HID mapping for 0x%02X — ignoring\n", code);
        }
    }
}

void onSessionUpdate(const SessionMetadata& meta) {
    session.gameRunning   = meta.isRunning;
    session.avgConfidence = meta.confidence;
    session.accuracy      = meta.accuracy;
    session.score         = meta.score;

    if (meta.isRunning && session.sessionStartMs == 0) {
        session.sessionStartMs = millis();
        Serial.println("[Session] Game session started");
    }
}

void onBLEConnect() {
    Serial.println("[BLE] iPad connected");
    display.showStatus("BLE: Connected", TFT_GREEN);
    display.invalidate();
}

void onBLEDisconnect() {
    Serial.println("[BLE] iPad disconnected — IMU-only mode");
    session.gameRunning = false;
    display.showStatus("BLE: Lost", TFT_RED);
    display.invalidate();
    // bleServer auto-restarts advertising in its onDisconnect callback
}

// ============================================================
// Session lifecycle
// ============================================================

void handleEndSession() {
    Serial.println("[Session] END_SESSION received from iPad");
    session.gameRunning    = false;
    session.sessionStartMs = 0;

    display.showSummary(session, _batteryPercent());
    vibrate(200);

    // Summary auto-clears via display.summaryExpired() in loop
}

// ============================================================
// Hardware helpers
// ============================================================

// Short buzz on VIBRATION_PIN (optional motor wired to GPIO26)
void vibrate(uint16_t ms) {
#ifdef VIBRATION_PIN
    digitalWrite(VIBRATION_PIN, HIGH);
    delay(ms);
    digitalWrite(VIBRATION_PIN, LOW);
#endif
    (void)ms;  // suppress warning if pin not configured
}

// Returns battery percentage (0–100) via AXP2101 API on PLUS2
uint8_t _batteryPercent() {
    // M5StickC PLUS2 uses AXP2101; getBatteryLevel() returns 0–100
    int pct = M5.Power.getBatteryLevel();
    if (pct < 0)   pct = 0;
    if (pct > 100) pct = 100;
    return static_cast<uint8_t>(pct);
}
