# Debugging Guide

## Serial Monitor

Connect USB-C and open at **115200 baud**.

### Expected log flow

```
[Setup] Complete — waiting for iPad...
[BLE]   Advertising started
[BLE]   Client connected
[BLE]   Gesture received: 0x01
[Gesture] code=0x01 (LEAN_LEFT)
[HID]   → LEFT_ARROW (0x50)
[IMU]   Jump detected (mag=2.34, delta=1.34)
[IMU]   Jump → HID SPACEBAR
[BLE]   Session update: running=1 conf=0.94 acc=0.92 score=87
[Session] END_SESSION received from iPad
[BLE]   Client disconnected — restarting advertising
```

## Common Issues

### "BLE: Waiting..." never changes
- Check iPad Bluetooth is ON
- Confirm band advertises as "MotionMind Band" in iOS Settings → Bluetooth
- Restart the sketch (reset button on side)

### HID keystrokes not reaching Subway Surfers
- iOS must accept the HID pairing prompt
- Open Notes app first → test gestures → should see arrow characters
- Only works when game is in **foreground**

### IMU init failed
- Check I2C bus (GPIO21/22 on M5StickC)
- Firmware continues in BLE-only mode — band still works

### GPIO4 pull-high warning
- PLUS2 removed AXP192; GPIO4 floats otherwise
- Confirm `digitalWrite(4, HIGH)` in setup() runs (check serial)

## BLE GATT Test (without iPad)

Use **nRF Connect** app (iOS/Android):
1. Scan → "MotionMind Band"
2. Connect → expand service 0xFFF0
3. Write 0x01 to characteristic 0xFFF1
4. Serial monitor should show: `[Gesture] code=0x01 (LEAN_LEFT)`

## HID Test (without game)

1. Pair band in iOS Settings → Bluetooth
2. Open Notes app
3. Send gesture from nRF Connect or iPad app
4. Arrow character should appear in Notes

## Memory / Stack

Serial output during heavy BLE activity:
```
[BLE] MTU negotiated: 64
```

If heap is low you may see:
```
E (1234) BT: bt_mesh_adv: Unable to allocate buffer for adv
```
→ Increase `CONFIG_BT_NIMBLE_ENABLED` stack in `platformio.ini`.
