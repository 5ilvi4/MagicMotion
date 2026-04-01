# HID Report Descriptor — Technical Reference

## Overview

The band uses the **ESP32-BLE-Keyboard** library which implements a standard USB HID keyboard report descriptor. iOS treats the band as a wireless keyboard and routes keystrokes to the foreground app.

## Keyboard HID Report (8 bytes)

```
Byte 0: Modifier keys bitmask
        Bit 0: Left Ctrl
        Bit 1: Left Shift
        Bit 2: Left Alt
        Bit 3: Left GUI (Cmd)
        Bit 4: Right Ctrl
        Bit 5: Right Shift
        Bit 6: Right Alt
        Bit 7: Right GUI

Byte 1: Reserved (0x00)

Bytes 2–7: Up to 6 simultaneous keycodes (USB HID Usage IDs)
```

## Keycodes Used

| USB HID Usage ID | Key | Gesture |
|-----------------|-----|---------|
| 0x50 | LEFT ARROW | LEAN_LEFT |
| 0x4F | RIGHT ARROW | LEAN_RIGHT |
| 0x2C | SPACEBAR | JUMP |
| 0x2D | - (MINUS) | SQUAT / DUCK |
| 0x52 | UP ARROW | TWIST (future) |
| 0x51 | DOWN ARROW | (reserved) |

## Press + Release Protocol

Each gesture fires a **press** report followed 50ms later by a **release** report:

```
t=0ms:   [0x00, 0x00, 0x50, 0x00, 0x00, 0x00, 0x00, 0x00]  ← LEFT pressed
t=50ms:  [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]  ← release all
```

The 50ms hold is intentional — Subway Surfers requires a held keydown to register direction changes reliably.

## HID Service UUIDs (BLE)

| UUID | Description |
|------|-------------|
| 0x1812 | HID Service |
| 0x2A4E | HID Protocol Mode |
| 0x2A4D | HID Report |
| 0x2A4B | HID Report Map |
| 0x2A4A | HID Information |
| 0x2A33 | Boot Keyboard Input Report |

## Dual-Role Advertising Note

ESP32 cannot advertise two independent GAP roles simultaneously, but it **can**:
1. Run a GATT server (custom 0xFFF0 service) in one advertising payload
2. Run a HID profile (0x1812) in a second advertising payload

The `ESP32-BLE-Keyboard` library manages its own `BLEServer` instance. Our `BLEGATTServer` uses the same underlying `BLEDevice` stack. Both services are registered before advertising starts, so iOS sees both:
- "MotionMind Band" in Bluetooth settings (HID pairing)
- Service 0xFFF0 discoverable via GATT scan (nRF Connect)

## iOS Compatibility

- iOS 14+: BLE HID keyboards supported without MFi certification
- The band must be **paired** (not just connected) for keystrokes to route to apps
- Pairing prompt appears on first connection via iOS Settings → Bluetooth
