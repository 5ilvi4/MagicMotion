#pragma once

// ============================================================
// HIDGamepad.h — BLE HID Keyboard Device
//
// Uses the NimBLE-based ESP32-BLE-Keyboard library (chegewara).
// Band advertises simultaneously as GATT peripheral (0xFFF0)
// AND as a BLE HID keyboard so iOS routes keystrokes to the
// foreground app (Subway Surfers).
//
// Dual-advertising note: ESP32 can run one advertising set.
// We achieve dual-role by combining both GATT service UUID and
// HID appearance in a single advertisement payload.
// ============================================================

#include <Arduino.h>
#include <BleKeyboard.h>   // ESP32-BLE-Keyboard by chegewara
#include "Config.h"

// ============================================================
class HIDGamepad {
public:

    // --------------------------------------------------------
    // Initialise BLE HID device.
    // Call AFTER BLEGATTServer::begin() — shares the BLE stack.
    // --------------------------------------------------------
    void begin() {
        // BleKeyboard uses a separate BLE advertising handle;
        // on ESP32 both GATT server + HID keyboard can coexist.
        _keyboard.begin();
        Serial.println("[HID] BLE Keyboard advertising started");
    }

    // --------------------------------------------------------
    // Returns true when an iOS device has accepted the HID pairing
    // --------------------------------------------------------
    bool isConnected() const {
        return _keyboard.isConnected();
    }

    // --------------------------------------------------------
    // Send a key press + release for the given USB HID keycode.
    // Press held for KEY_HOLD_MS then released.
    // --------------------------------------------------------
    void sendKey(uint8_t hidKeyCode) {
        if (!_keyboard.isConnected()) {
            Serial.println("[HID] Not connected — dropping key");
            return;
        }

        MediaKeyReport noop = {0, 0};  // silence unused-variable warning

        // BleKeyboard accepts KeyboardKeycode (uint8_t)
        _keyboard.press(hidKeyCode);
        delay(KEY_HOLD_MS);
        _keyboard.release(hidKeyCode);

        Serial.printf("[HID] Key sent: 0x%02X (%dms hold)\n", hidKeyCode, KEY_HOLD_MS);
    }

    // --------------------------------------------------------
    // Convenience wrappers for common game keys
    // --------------------------------------------------------
    void pressLeft()   { sendKey(KEY_LEFT_ARROW);  }
    void pressRight()  { sendKey(KEY_RIGHT_ARROW); }
    void pressUp()     { sendKey(KEY_UP_ARROW);    }
    void pressDown()   { sendKey(KEY_DOWN_ARROW);  }
    void pressSpace()  { sendKey(' ');              }

    // --------------------------------------------------------
    // Set battery level reported in HID device info
    // --------------------------------------------------------
    void setBatteryLevel(uint8_t pct) {
        _keyboard.setBatteryLevel(pct);
    }

private:
    // BleKeyboard("Name", "Manufacturer", initialBatteryLevel)
    BleKeyboard _keyboard { BLE_DEVICE_NAME, "MotionMind", 100 };

    static constexpr uint8_t KEY_HOLD_MS = 50;  // ms key is held before release
};
