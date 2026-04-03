// BandBLEManager.swift
// MagicMotion
//
// Manages CoreBluetooth Central connection to the MotionMind wrist band.
// Scans for a peripheral whose name contains "MotionMind", connects, discovers
// the FFF0 service and FFF1 gesture characteristic, then exposes `send(event:)`
// so the rest of the app can fire HID-keyed gestures to the band.
//
// GATT layout (mirrors band-firmware/BLEGATTServer.h):
//   Service  0000fff0-0000-1000-8000-00805f9b34fb
//   Char     0000fff1-0000-1000-8000-00805f9b34fb  (write-without-response)
//
// MotionEvent → HID byte map (mirrors band-firmware/GestureMapping.h):
//   0x01 → leanLeft   → LEFT_ARROW
//   0x02 → leanRight  → RIGHT_ARROW
//   0x03 → jump       → SPACEBAR
//   0x04 → squat      → DOWN_ARROW

import CoreBluetooth
import Combine
import Foundation

// MARK: - Constants

private enum BandBLE {
    static let serviceUUID     = CBUUID(string: "0000fff0-0000-1000-8000-00805f9b34fb")
    static let gestureCharUUID = CBUUID(string: "0000fff1-0000-1000-8000-00805f9b34fb")
    static let deviceNameMatch = "MotionMind"
    static let reconnectDelay: TimeInterval = 3.0
}

// MARK: - BandBLEManager

/// Singleton-style `ObservableObject` that manages the CoreBluetooth Central
/// session with the MotionMind wrist band.  Drop it into the SwiftUI environment
/// as an `@StateObject` and call `send(gesture:)` whenever a gesture fires.
final class BandBLEManager: NSObject, ObservableObject {

    // MARK: Published state (drives UI indicators)

    /// Whether the band is currently connected and the gesture characteristic
    /// is ready to accept writes.
    @Published private(set) var isConnected: Bool = false

    /// Human-readable status string for the debug/status panel.
    @Published private(set) var statusText: String = "BLE: Off"

    // MARK: Private CoreBluetooth objects

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var gestureCharacteristic: CBCharacteristic?

    // MARK: Init

    override init() {
        super.init()
        // Restore-identifier lets iOS re-instantiate us after background relaunch.
        centralManager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue(label: "com.magicmotion.ble", qos: .userInitiated),
            options: [CBCentralManagerOptionRestoreIdentifierKey: "MagicMotionBandCentral"]
        )
    }

    // MARK: Public API

    /// Forward a detected `MotionEvent` to the band as a single-byte GATT write.
    /// No-op if the characteristic is not yet ready or the event has no mapping.
    func send(event: MotionEvent) {
        guard isConnected,
              let peripheral = peripheral,
              let characteristic = gestureCharacteristic else { return }

        let byte: UInt8
        switch event {
        case .leanLeft:  byte = 0x01
        case .leanRight: byte = 0x02
        case .jump:      byte = 0x03
        case .squat:     byte = 0x04
        default:         return   // handsUp / handsDown / freeze / none — no HID mapping
        }

        let data = Data([byte])
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        log("📡 Sent event \(event.displayName) → 0x\(String(format: "%02X", byte))")
    }

    // For convenience when callers hold a `Gesture` value.
    // Maps the Gesture enum (pose-classifier output) onto MotionEvent space.
    func send(gesture: Gesture) {
        switch gesture {
        case .swipeLeft:  send(event: .leanLeft)
        case .swipeRight: send(event: .leanRight)
        case .jump, .swipeUp: send(event: .jump)
        case .swipeDown:  send(event: .squat)
        case .none:       break
        }
    }

    // MARK: Scanning helpers

    private func startScan() {
        guard centralManager.state == .poweredOn else { return }
        guard !centralManager.isScanning else { return }
        statusText = "BLE: Scanning…"
        centralManager.scanForPeripherals(
            withServices: [BandBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log("🔍 Scanning for MotionMind band…")
    }

    private func stopScan() {
        if centralManager.isScanning { centralManager.stopScan() }
    }

    private func reconnectAfterDelay() {
        DispatchQueue.global().asyncAfter(deadline: .now() + BandBLE.reconnectDelay) { [weak self] in
            self?.startScan()
        }
    }

    private func updateConnectedState(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = connected
            self?.statusText = connected ? "BLE: ✓ Band" : "BLE: Disconnected"
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[BandBLEManager] \(message)")
        #endif
    }
}

// MARK: - CBCentralManagerDelegate

extension BandBLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("✅ Bluetooth powered on")
            DispatchQueue.main.async { self.statusText = "BLE: Ready" }
            startScan()
        case .poweredOff:
            log("⚠️ Bluetooth powered off")
            updateConnectedState(false)
            DispatchQueue.main.async { self.statusText = "BLE: Off" }
        case .unauthorized:
            log("🚫 Bluetooth unauthorized")
            DispatchQueue.main.async { self.statusText = "BLE: No Permission" }
        case .unsupported:
            log("🚫 Bluetooth unsupported on this device")
            DispatchQueue.main.async { self.statusText = "BLE: Unsupported" }
        default:
            log("ℹ️ Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "")
        guard name.contains(BandBLE.deviceNameMatch) else { return }

        log("📡 Found peripheral: \(name) — connecting…")
        stopScan()
        self.peripheral = peripheral
        self.peripheral!.delegate = self
        central.connect(peripheral, options: nil)
        DispatchQueue.main.async { self.statusText = "BLE: Connecting…" }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("🔗 Connected to \(peripheral.name ?? "band")")
        DispatchQueue.main.async { self.statusText = "BLE: Discovering…" }
        peripheral.discoverServices([BandBLE.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log("❌ Failed to connect: \(error?.localizedDescription ?? "unknown")")
        updateConnectedState(false)
        reconnectAfterDelay()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log("🔌 Disconnected from \(peripheral.name ?? "band"): \(error?.localizedDescription ?? "clean")")
        gestureCharacteristic = nil
        self.peripheral = nil
        updateConnectedState(false)
        reconnectAfterDelay()
    }

    // MARK: State restoration

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored = peripherals.first {
            log("♻️ Restoring peripheral: \(restored.name ?? "unknown")")
            self.peripheral = restored
            restored.delegate = self
            if restored.state == .connected {
                restored.discoverServices([BandBLE.serviceUUID])
            } else {
                central.connect(restored, options: nil)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BandBLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log("❌ Service discovery error: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == BandBLE.serviceUUID {
            log("🔎 Discovered FFF0 service — looking for FFF1 characteristic…")
            peripheral.discoverCharacteristics([BandBLE.gestureCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            log("❌ Characteristic discovery error: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == BandBLE.gestureCharUUID {
            gestureCharacteristic = characteristic
            updateConnectedState(true)
            log("✅ Gesture characteristic ready — band fully connected")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            log("❌ Write error: \(error.localizedDescription)")
        }
    }
}
