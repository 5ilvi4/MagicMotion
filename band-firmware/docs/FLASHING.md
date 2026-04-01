# Flashing Guide

## Option A — PlatformIO (Recommended)

```bash
# Install PlatformIO CLI
pip install platformio

# From band-firmware/ directory
cd band-firmware/
pio run -t upload

# Open serial monitor
pio device monitor -b 115200
```

## Option B — Arduino IDE

### 1. Install ESP32 Board Package
- Open Arduino IDE → Preferences
- Add to "Additional boards manager URLs":
  ```
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
  ```
- Tools → Board Manager → search "ESP32 by Espressif" → Install (≥ 2.0.14)

### 2. Install Libraries
Search in Library Manager (Sketch → Include Library → Manage Libraries):
- `M5StickCPlus2` by M5Stack
- `ESP32 BLE Keyboard` by T-vK

### 3. Configure TFT_eSPI (if used standalone)
Edit `Arduino/libraries/TFT_eSPI/User_Setup.h`:
```cpp
#define ST7789_DRIVER
#define TFT_WIDTH  135
#define TFT_HEIGHT 240
#define TFT_MOSI   15
#define TFT_SCLK   13
#define TFT_CS     5
#define TFT_DC     23
#define TFT_RST    18
#define TFT_BL     -1   // Backlight via AXP2101
```

### 4. Board Settings
- Board: **M5StickC** (or ESP32 Dev Module)
- Partition Scheme: **Huge APP (3MB No OTA/1MB SPIFFS)**
- Upload Speed: **921600**
- Port: `/dev/cu.usbserial-*` (macOS) or `COM*` (Windows)

### 5. Upload
- Sketch → Upload (⌘U)
- Expected output:
  ```
  Connecting......
  Chip is ESP32-PICO-V3-02
  Uploading... 100%
  Hard resetting via RTS pin...
  ```

## Verify Boot

Open Serial Monitor (115200 baud). Expected output:
```
==============================
 MotionMind Band Firmware v1.0
==============================
[IMU] MPU6886 init OK
[IMU] Calibrating — hold device still for 1 second...
[IMU] Calibration done — baseline G = 1.003
[BLE] GATT server started — advertising as "MotionMind Band"
[HID] BLE Keyboard advertising started
[Setup] Complete — waiting for iPad...
```

TFT should show: **MotionMind / Band Ready / BLE: Waiting...**
