#pragma once

// ============================================================
// GestureMapping.h — Gesture ↔ HID codec
// ============================================================

#include <Arduino.h>
#include "Config.h"

namespace GestureMapping {

    // --------------------------------------------------------
    // Gesture enum (mirrors GESTURE_CODE_* defines for safety)
    // --------------------------------------------------------
    enum Gesture : uint8_t {
        NOP              = GESTURE_CODE_NOP,
        LEAN_LEFT        = GESTURE_CODE_LEAN_LEFT,
        LEAN_RIGHT       = GESTURE_CODE_LEAN_RIGHT,
        JUMP             = GESTURE_CODE_JUMP,
        SQUAT            = GESTURE_CODE_SQUAT,
        DUCK             = GESTURE_CODE_DUCK,
        RAISE_ARM_LEFT   = GESTURE_CODE_RAISE_ARM_LEFT,
        RAISE_ARM_RIGHT  = GESTURE_CODE_RAISE_ARM_RIGHT,
        TWIST            = GESTURE_CODE_TWIST,
        END_SESSION      = GESTURE_CODE_END_SESSION,
    };

    // --------------------------------------------------------
    // Gesture → HID keycode lookup
    // Returns HID_KEY_NONE (0x00) if no mapping exists.
    // --------------------------------------------------------
    inline uint8_t getHIDKey(uint8_t gestureCode) {
        switch (gestureCode) {
            case LEAN_LEFT:       return HID_KEY_LEFT_ARROW;
            case LEAN_RIGHT:      return HID_KEY_RIGHT_ARROW;
            case JUMP:            return HID_KEY_SPACEBAR;
            case SQUAT:           return HID_KEY_MINUS;
            case DUCK:            return HID_KEY_MINUS;
            case RAISE_ARM_LEFT:  return HID_KEY_LEFT_ARROW;   // future
            case RAISE_ARM_RIGHT: return HID_KEY_RIGHT_ARROW;  // future
            case TWIST:           return HID_KEY_UP_ARROW;     // future
            case NOP:
            case END_SESSION:
            default:
                return HID_KEY_NONE;
        }
    }

    // --------------------------------------------------------
    // Gesture → Human-readable display label (TFT)
    // --------------------------------------------------------
    inline const char* getName(uint8_t gestureCode) {
        switch (gestureCode) {
            case LEAN_LEFT:       return "<- Lean L";
            case LEAN_RIGHT:      return "Lean R ->";
            case JUMP:            return "JUMP ^";
            case SQUAT:           return "Squat v";
            case DUCK:            return "Duck";
            case RAISE_ARM_LEFT:  return "Raise L";
            case RAISE_ARM_RIGHT: return "Raise R";
            case TWIST:           return "Twist";
            case END_SESSION:     return "Session End";
            case NOP:             return "---";
            default:              return "???";
        }
    }

    // --------------------------------------------------------
    // HID keycode → display label (for serial debug)
    // --------------------------------------------------------
    inline const char* hidKeyName(uint8_t hidKey) {
        switch (hidKey) {
            case HID_KEY_LEFT_ARROW:  return "LEFT_ARROW";
            case HID_KEY_RIGHT_ARROW: return "RIGHT_ARROW";
            case HID_KEY_UP_ARROW:    return "UP_ARROW";
            case HID_KEY_DOWN_ARROW:  return "DOWN_ARROW";
            case HID_KEY_SPACEBAR:    return "SPACEBAR";
            case HID_KEY_MINUS:       return "MINUS";
            case HID_KEY_NONE:        return "NONE";
            default:                  return "UNKNOWN";
        }
    }

} // namespace GestureMapping
