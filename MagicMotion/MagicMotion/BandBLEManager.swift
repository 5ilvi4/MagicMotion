// BandBLEManager.swift
// MagicMotion
//
// CoreBluetooth Central manager for the MotionMind wrist band.
//
// ── Gesture delivery mechanism ────────────────────────────────
// Touch injection is NOT done via UIKit private APIs or TouchInjector.
// Instead: iPad → BLE (this file) → band firmware → USB HID (GameController
// framework / HIDGamepad.h) → OS routes keystrokes to the foreground game.
// This is the only App Store–safe, latency-acceptable mechanism.
//
// GATT layout (mirrors band-firmware/BLEGATTServer.h):
//   Service  0000fff0-0000-1000-8000-00805f9b34fb
//   Char     0000fff1-0000-1000-8000-00805f9b34fb  (write-without-response)
//
// MotionEvent → HID byte map (mirrors band-firmware/Config.h):
//   0x01 leanLeft   → LEFT_ARROW
//   0x02 leanRight  → RIGHT_ARROW
//   0x03 jump       → SPACEBAR
//   0x04 squat      → DOWN_ARROW
//   0xFF endSession → band resets
//
// Concurrency note:
//   This project sets SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which means
//   every type is @MainActor by default.  BandBLEManager opts out with
//   `nonisolated(unsafe)` on its CBCentral/CBPeripheral stored properties so
//   that CoreBluetooth can call delegate methods from its own queue without
//   actor-isolation violations.  All @Published mutations hop back to the
//   main actor explicitly.

import Combine
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

/// Manages the CoreBluetooth Central role for the MotionMind wrist band.
/// Gracefully degrades — all sends are no-ops when the band is off.
@MainActor
final class BandBLEManager: NSObject, ObservableObject {

    // MARK: - Published state (always mutated on MainActor)

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var statusText: String = "Band: Off"

    // MARK: - Private CoreBluetooth
    // nonisolated(unsafe): accessed from both the MainActor (init, send*)
    // and the BLE queue (delegate callbacks). CoreBluetooth serialises its
    // own callbacks; we never race on these from two non-BLE threads.

    nonisolated(unsafe) private var centralManager: CBCentralManager!
    nonisolated(unsafe) private var peripheral: CBPeripheral?
    nonisolated(unsafe) private var gestureCharacteristic: CBCharacteristic?
    private let bleQueue = DispatchQueue(label: "com.magicmotion.ble", qos: .userInitiated)

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "MagicMotionBand"]
        )
    }

    // MARK: - Public API (called from MainActor / SwiftUI)

    /// Send a MotionEvent to the band. No-op when not connected or unmapped.
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
        default:         return
        }
        // Capture locals before crossing actor boundary; dispatch write on BLE queue
        // to avoid nonisolated(unsafe) data race on CBPeripheral.
        let data = Data([byte])
        let eventName = event.displayName
        bleQueue.async {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }
        log("📡 \(eventName) → 0x\(String(format: "%02X", byte))")
    }

    /// Convenience bridge from the app's Gesture enum.
    func send(gesture: Gesture) {
        switch gesture {
        case .swipeLeft:       send(event: .leanLeft)
        case .swipeRight:      send(event: .leanRight)
        case .jump, .swipeUp: send(event: .jump)
        case .swipeDown:       send(event: .squat)
        case .none:            break
        }
    }

    /// Signal the band to reset (call on app background / session end).
    func sendEndSession() {
        guard isConnected,
              let peripheral = peripheral,
              let characteristic = gestureCharacteristic else { return }
        bleQueue.async {
            peripheral.writeValue(Data([0xFF]), for: characteristic, type: .withoutResponse)
        }
        log("📡 END_SESSION → 0xFF")
    }

    // MARK: - Private helpers

    nonisolated private func startScan() {
        guard centralManager.state == .poweredOn, !centralManager.isScanning else { return }
        setStatus("Band: Scanning…")
        centralManager.scanForPeripherals(
            withServices: [BandBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log("🔍 Scanning for MotionMind band…")
    }

    nonisolated private func stopScan() {
        if centralManager.isScanning { centralManager.stopScan() }
    }

    nonisolated private func reconnectAfterDelay() {
        DispatchQueue.global().asyncAfter(deadline: .now() + BandBLE.reconnectDelay) { [weak self] in
            self?.startScan()
        }
    }

    /// Hop to MainActor to mutate @Published properties.
    nonisolated private func setConnected(_ connected: Bool) {
        Task { @MainActor [weak self] in
            self?.isConnected = connected
            self?.statusText  = connected ? "Band ✓" : "Band: Disconnected"
        }
    }

    nonisolated private func setStatus(_ text: String) {
        Task { @MainActor [weak self] in self?.statusText = text }
    }

    nonisolated private func log(_ msg: String) {
#if DEBUG
        print("[BandBLEManager] \(msg)")
#endif
    }
}

// MARK: - CBCentralManagerDelegate

extension BandBLEManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("✅ Bluetooth on — scanning")
            setStatus("Band: Ready")
            startScan()
        case .poweredOff:
            setConnected(false)
            setStatus("Band: BT Off")
        case .unauthorized:
            setStatus("Band: No Permission")
        case .unsupported:
            setStatus("Band: Unsupported")
        default:
            break
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
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
        setStatus("Band: Connecting…")
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        log("🔗 Connected to \(peripheral.name ?? "band")")
        setStatus("Band: Discovering…")
        peripheral.discoverServices([BandBLE.serviceUUID])
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        log("❌ Failed: \(error?.localizedDescription ?? "?")")
        setConnected(false)
        reconnectAfterDelay()
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        log("🔌 Disconnected: \(error?.localizedDescription ?? "clean")")
        gestureCharacteristic = nil
        self.peripheral = nil
        setConnected(false)
        reconnectAfterDelay()
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    willRestoreState dict: [String: Any]) {
        guard let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first
        else { return }
        log("♻️ Restoring: \(restored.name ?? "peripheral")")
        self.peripheral = restored
        restored.delegate = self
        if restored.state == .connected {
            restored.discoverServices([BandBLE.serviceUUID])
        } else {
            central.connect(restored, options: nil)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BandBLEManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        if let err = error { log("❌ Services: \(err)"); return }
        peripheral.services?
            .filter { $0.uuid == BandBLE.serviceUUID }
            .forEach { peripheral.discoverCharacteristics([BandBLE.gestureCharUUID], for: $0) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        if let err = error { log("❌ Chars: \(err)"); return }
        if let char = service.characteristics?.first(where: { $0.uuid == BandBLE.gestureCharUUID }) {
            gestureCharacteristic = char
            setConnected(true)
            log("✅ Ready — band fully online")
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        if let err = error { log("❌ Write: \(err)") }
    }
}
