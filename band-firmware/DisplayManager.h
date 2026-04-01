#pragma once

// ============================================================
// DisplayManager.h — TFT display abstraction (ST7789, 135×240)
// Uses M5StickC built-in M5.Lcd (TFT_eSPI under the hood).
// ============================================================

#include <M5StickCPlus2.h>
#include "Config.h"
#include "BLEGATTServer.h"  // SessionMetadata

// Forward-declare SessionState so header is self-contained
struct SessionState;

// ============================================================
class DisplayManager {
public:

    // --------------------------------------------------------
    // Initialise display; call once in setup()
    // --------------------------------------------------------
    void begin() {
        M5.Lcd.setRotation(0);              // Portrait (135 wide, 240 tall)
        M5.Lcd.fillScreen(TFT_BLACK);
        M5.Lcd.setTextColor(TFT_WHITE, TFT_BLACK);
        M5.Lcd.setTextSize(1);
        // AXP192-based backlight (PLUS2 uses AXP2101 but same API)
        // M5.Axp.SetLcdEnable(true);
        Serial.println("[Display] Initialised 135×240 TFT");
    }

    // --------------------------------------------------------
    // Default idle screen
    // --------------------------------------------------------
    void showDefault(bool bleConnected = false, uint8_t battPct = 100) {
        if (!_dirty(ScreenID::DEFAULT)) return;

        M5.Lcd.fillScreen(TFT_BLACK);

        // Header
        _drawHeader("MotionMind", TFT_GREEN);

        // Status
        M5.Lcd.setTextColor(TFT_WHITE, TFT_BLACK);
        M5.Lcd.setCursor(8, 45);
        M5.Lcd.println("Band Ready");

        M5.Lcd.setCursor(8, 65);
        if (bleConnected) {
            M5.Lcd.setTextColor(TFT_GREEN, TFT_BLACK);
            M5.Lcd.println("BLE: Connected");
        } else {
            M5.Lcd.setTextColor(TFT_YELLOW, TFT_BLACK);
            M5.Lcd.println("BLE: Waiting...");
        }

        // Battery bar
        _drawBattery(battPct, 100);
    }

    // --------------------------------------------------------
    // Live session screen (called ~10 Hz during gameplay)
    // --------------------------------------------------------
    void showSession(const SessionState& s, uint8_t battPct = 100) {
        if (millis() - _lastSessionUpdate < DISPLAY_UPDATE_INTERVAL) return;
        _lastSessionUpdate = millis();
        _currentScreen = ScreenID::SESSION;

        M5.Lcd.fillScreen(TFT_BLACK);
        _drawHeader("GAME ON", TFT_CYAN);

        M5.Lcd.setTextColor(TFT_WHITE, TFT_BLACK);

        M5.Lcd.setCursor(8, 45);
        M5.Lcd.printf("Gesture: %s", s.lastGestureName);

        M5.Lcd.setCursor(8, 65);
        M5.Lcd.printf("Count:   %lu", s.gestureCount);

        M5.Lcd.setCursor(8, 83);
        M5.Lcd.printf("Conf:    %.0f%%", s.avgConfidence * 100.0f);

        M5.Lcd.setCursor(8, 101);
        M5.Lcd.printf("Accuracy:%.0f%%", s.accuracy * 100.0f);

        M5.Lcd.setCursor(8, 119);
        M5.Lcd.printf("Score:   %u/100", s.score);

        _drawBattery(battPct, 155);
    }

    // --------------------------------------------------------
    // Post-game summary (auto-clears after SESSION_SUMMARY_DISPLAY_MS)
    // --------------------------------------------------------
    void showSummary(const SessionState& s, uint8_t battPct = 100) {
        _currentScreen = ScreenID::SUMMARY;

        M5.Lcd.fillScreen(TFT_BLACK);
        _drawHeader("Game Over!", TFT_GREEN);

        M5.Lcd.setTextColor(TFT_WHITE, TFT_BLACK);

        M5.Lcd.setCursor(8, 50);
        M5.Lcd.printf("Gestures: %lu", s.gestureCount);

        M5.Lcd.setCursor(8, 68);
        M5.Lcd.printf("Success:  %lu", s.successCount);

        M5.Lcd.setCursor(8, 86);
        M5.Lcd.printf("Conf: %.0f%%", s.avgConfidence * 100.0f);

        M5.Lcd.setCursor(8, 104);
        M5.Lcd.printf("Score: %u/100", s.score);

        _drawBattery(battPct, 140);

        // Summary auto-expires after SESSION_SUMMARY_DISPLAY_MS
        _summaryShownAt = millis();
    }

    // --------------------------------------------------------
    // One-line status overlay (error / warning messages)
    // --------------------------------------------------------
    void showStatus(const char* msg, uint16_t color = TFT_YELLOW) {
        M5.Lcd.setTextColor(color, TFT_BLACK);
        M5.Lcd.setCursor(8, 180);
        M5.Lcd.fillRect(0, 175, 135, 20, TFT_BLACK);
        M5.Lcd.println(msg);
        M5.Lcd.setTextColor(TFT_WHITE, TFT_BLACK);
    }

    // --------------------------------------------------------
    // Call from main loop to auto-return from summary screen
    // --------------------------------------------------------
    bool summaryExpired() const {
        return _currentScreen == ScreenID::SUMMARY &&
               millis() - _summaryShownAt >= SESSION_SUMMARY_DISPLAY_MS;
    }

    // --------------------------------------------------------
    // Force redraw on next call (e.g. after BLE state change)
    // --------------------------------------------------------
    void invalidate() { _currentScreen = ScreenID::NONE; }

private:
    enum class ScreenID { NONE, DEFAULT, SESSION, SUMMARY };

    ScreenID _currentScreen    = ScreenID::NONE;
    uint32_t _lastSessionUpdate = 0;
    uint32_t _summaryShownAt   = 0;

    bool _dirty(ScreenID id) {
        if (_currentScreen == id) return false;
        _currentScreen = id;
        return true;
    }

    // Centred header bar
    void _drawHeader(const char* title, uint16_t color) {
        M5.Lcd.fillRect(0, 0, 135, 32, color);
        M5.Lcd.setTextColor(TFT_BLACK, color);
        M5.Lcd.setTextSize(2);

        // Rough centre: 6px/char × 2 size = 12px per char
        int x = (135 - (strlen(title) * 12)) / 2;
        if (x < 4) x = 4;
        M5.Lcd.setCursor(x, 8);
        M5.Lcd.print(title);
        M5.Lcd.setTextSize(1);
        M5.Lcd.setTextColor(TFT_WHITE, TFT_BLACK);
    }

    // Battery indicator at given y position
    void _drawBattery(uint8_t pct, int y) {
        uint16_t color = (pct < BATTERY_CRITICAL_THRESHOLD) ? TFT_RED :
                         (pct < BATTERY_WARN_THRESHOLD)     ? TFT_YELLOW :
                                                               TFT_GREEN;
        M5.Lcd.setTextColor(color, TFT_BLACK);
        M5.Lcd.setCursor(8, y);
        M5.Lcd.printf("Battery: %3d%%", pct);
        M5.Lcd.setTextColor(TFT_WHITE, TFT_BLACK);
    }
};

// ============================================================
// SessionState — shared across DisplayManager + main sketch
// ============================================================
struct SessionState {
    bool        gameRunning     = false;
    uint32_t    gestureCount    = 0;
    uint32_t    successCount    = 0;
    float       avgConfidence   = 0.0f;
    float       accuracy        = 0.0f;
    uint8_t     score           = 0;
    const char* lastGestureName = "---";
    uint32_t    sessionStartMs  = 0;
};
