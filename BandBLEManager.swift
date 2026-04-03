// BandBLEManager.swift
// MagicMotion
//
// CoreBluetooth Central manager for the MotionMind wrist band.
//
// The band acts as both:
//   • GATT server  — receives 1-byte gesture codes from this file
//   • HID keyboard — fires keystrokes to the active game
//
// GATT layout (mirrors band-firmware/BLEGATTServer.h):
//   Service  0000fff0-0000-1000-8000-00805f9b34fb
//   Char     0000fff1-0000-1000-8000-00805f9b34fb  (write-without-response)
//
// DetectedGesture → byte map (mirrors band-firmware/Config.h):
//   0x01  LEAN_LEFT   → LEFT ARROW
//   0x02  LEAN_RIGHT  → RIGHT ARROW
//   0x03  JUMP        → SPACEBAR
//   0x04  SQUAT       → DOWN ARROW
//   0x03  HOVERBOARD  → SPACEBAR (mapped to jump)
//   0xFF  END_SESSION → band resets

import CoreBluetooth
import Foundation

// MARK: - Constants

private enum BandBLE {
    static let serviceUUID     = CBUUID(string: "0000fff0-0000-1000-8000-00805f9b34fb")
    static let gestureCharUUID = CBUUID(string: "0000fff1-0000-1000-8000-00805f9b34fb")
    static let deviceNameMatch = "MotionMind"
    static let reconnectDelay: TimeInterval = 3.0
}

// MARK: - BandBLEManager

/// Manages the CoreBluetooth Central role: scans, connects, and writes
/// gesture bytes to the MotionMind wrist band over BLE.
///
/// Usage in SwiftUI:
/// ```swift
/// @StateObject private var band = BandBLEManager()
/// // then in connectPipeline():
/// classifier.onGestureDetected = { [injector, band] gesture in
///     injector.inject(gesture: gesture)
///     band.send(gesture: gesture)
/// }
/// ```
final class BandBLEManager: NSObject, ObservableObject {

    // MARK: - Published state (drives UI indicators)

    /// `true` once the gesture characteristic is ready for writes.
    @Published private(set) var isConnected: Bool = false

    /// Human-readable status suitable for display in the status bar.
    @Published private(set) var statusText: String = "Band: Off"

    // MARK: - Private CoreBluetooth

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var gestureCharacteristic: CBCharacteristic?

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue(label: "com.magicmotion.ble", qos: .userInitiated),
            options: [CBCentralManagerOptionRestoreIdentifierKey: "MagicMotionBandCentral"]
        )
    }

    // MARK: - Public API

    /// Write a gesture byte to the band. No-op when not connected or gesture is `.none`.
    func send(gesture: DetectedGesture) {
        guard isConnected,
              let peripheral = peripheral,
              let characteristic = gestureCharacteristic else { return }

        let byte: UInt8
        switch gesture {
        case .leanLeft:   byte = 0x01
        case .leanRight:  byte = 0x02
        case .jump:       byte = 0x03
        case .hoverboard: byte = 0x03   // mapped to SPACEBAR like jump
        case .squat:      byte = 0x04
        case .none:       return        // nothing to send
        }

        peripheral.writeValue(Data([byte]), for: characteristic, type: .withoutResponse)
        log("📡 \(gesture.rawValue) → 0x\(String(format: "%02X", byte))")
    }

    /// Signal the band to reset (e.g. on app backgrounding).
    func sendEndSession() {
        guard isConnected,
              let peripheral = peripheral,
              let characteristic = gestureCharacteristic else { return }
        peripheral.writeValue(Data([0xFF]), for: characteristic, type: .withoutResponse)
        log("📡 END_SESSION → 0xFF")
    }

    // MARK: - Private helpers

    private func startScan() {
        guard centralManager.state == .poweredOn, !centralManager.isScanning else { return }
        DispatchQueue.main.async { self.statusText = "Band: Scanning…" }
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

    private func setConnected(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = connected
            self?.statusText  = connected ? "Band ✓" : "Band: Disconnected"
        }
    }

    private func log(_ msg: String) {
        #if DEBUG
        print("[BandBLEManager] \(msg)")
        #endif
    }
}

// MARK: - CBCentralManagerDelegate

extension BandBLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("✅ Bluetooth powered on — starting scan")
            DispatchQueue.main.async { self.statusText = "Band: Ready" }
            startScan()
        case .poweredOff:
            log("⚠️ Bluetooth off")
            setConnected(false)
            DispatchQueue.main.async { self.statusText = "Band: BT Off" }
        case .unauthorized:
            DispatchQueue.main.async { self.statusText = "Band: No Permission" }
        case .unsupported:
            DispatchQueue.main.async { self.statusText = "Band: Unsupported" }
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? ""
        guard name.contains(BandBLE.deviceNameMatch) else { return }

        log("📡 Found: \(name) — connecting…")
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
        DispatchQueue.main.async { self.statusText = "Band: Connecting…" }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("🔗 Connected to \(peripheral.name ?? "band")")
        DispatchQueue.main.async { self.statusText = "Band: Connected" }
        peripheral.discoverServices([BandBLE.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log("❌ Failed to connect: \(error?.localizedDescription ?? "?")")
        setConnected(false)
        reconnectAfterDelay()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log("🔌 Disconnected: \(error?.localizedDescription ?? "clean")")
        gestureCharacteristic = nil
        self.peripheral = nil
        setConnected(false)
        reconnectAfterDelay()
    }

    // Background state restoration
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            log("♻️ Restoring \(restored.name ?? "peripheral")")
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
        if let err = error { log("❌ Service discovery: \(err.localizedDescription)"); return }
        peripheral.services?
            .filter { $0.uuid == BandBLE.serviceUUID }
            .forEach { peripheral.discoverCharacteristics([BandBLE.gestureCharUUID], for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let err = error { log("❌ Char discovery: \(err.localizedDescription)"); return }
        if let char = service.characteristics?.first(where: { $0.uuid == BandBLE.gestureCharUUID }) {
            gestureCharacteristic = char
            setConnected(true)
            log("✅ Gesture characteristic ready — band fully online")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let err = error { log("❌ Write error: \(err.localizedDescription)") }
    }
}
