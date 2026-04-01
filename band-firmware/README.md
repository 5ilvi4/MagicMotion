# MotionMind Band Firmware — README

## Overview

Firmware for M5StickC PLUS2 that bridges iPad gesture commands to HID keystrokes for Subway Surfers.

```
iPad (MotionMind app)
  → BLE Write [0x01] on GATT characteristic 0xFFF1
  → Band receives, maps to HID_KEY_LEFT_ARROW (0x50)
  → Band broadcasts as BLE HID keyboard
  → iOS routes keystroke to foreground app (Subway Surfers)
  → Character moves left ✓
```

## Hardware

| Component | Detail |
|-----------|--------|
| MCU | ESP32-PICO-V3-02 (240MHz dual-core) |
| RAM | 520KB SRAM + 2MB PSRAM |
| Flash | 8MB |
| Display | ST7789 TFT, 1.14", 135×240, SPI |
| IMU | MPU6886 (6-axis accel + gyro) |
| BLE | Bluetooth 5.0 |
| Battery | 200mAh LiPo, USB-C charge |
| PMIC | AXP2101 (PLUS2 model) |

## File Structure

```
band-firmware/
├── MotionMindBandFirmware.ino   Main sketch
├── BLEGATTServer.h              BLE GATT peripheral (0xFFF0)
├── HIDGamepad.h                 BLE HID keyboard device
├── GestureMapping.h             Gesture ↔ HID codec
├── DisplayManager.h             ST7789 TFT abstraction
├── IMUSensor.h                  MPU6886 wrapper
├── Config.h                     Constants + UUIDs
├── platformio.ini               PlatformIO build config
├── requirements.txt             Arduino IDE library list
└── docs/
    ├── FLASHING.md              How to flash firmware
    ├── DEBUGGING.md             Serial monitor guide
    ├── CALIBRATION.md           IMU calibration
    └── HID_REPORT_DESCRIPTOR.md HID technical specs
```

## Quick Start (PlatformIO)

```bash
cd band-firmware/
pio run -t upload
pio device monitor -b 115200
```

## Quick Start (Arduino IDE)

See [docs/FLASHING.md](docs/FLASHING.md).

## Gesture → HID Mapping

| Gesture Code | Name | HID Key |
|---|---|---|
| 0x01 | LEAN_LEFT | LEFT_ARROW (0x50) |
| 0x02 | LEAN_RIGHT | RIGHT_ARROW (0x4F) |
| 0x03 | JUMP | SPACEBAR (0x2C) |
| 0x04 | SQUAT | MINUS (0x2D) |
| 0x05 | DUCK | MINUS (0x2D) |
| 0xFF | END_SESSION | (summary screen) |

## BLE Services

| UUID | Role | Description |
|------|------|-------------|
| 0xFFF0 | GATT Service | MotionMind gesture service |
| 0xFFF1 | Characteristic | Gesture write (iPad → Band) |
| 0xFFF2 | Characteristic | Session metadata write (iPad → Band) |
| HID (0x1812) | HID Service | Keyboard device |

## Power Budget

| Mode | Current | Runtime |
|------|---------|---------|
| Active gameplay | ~150mA | ~80 min |
| Idle (BLE listening) | ~50mA | ~4 hours |
| Screen off | ~30mA | ~6.5 hours |
| Critical (<5%) | — | Shutdown |
