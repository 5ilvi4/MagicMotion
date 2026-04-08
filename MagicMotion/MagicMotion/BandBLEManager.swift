// BandBLEManager.swift
// MagicMotion
//
// CoreBluetooth Central manager for the M5StickC Plus2 ("M5Gamepad") controller.
//
// ── Control flow ──────────────────────────────────────────────────────────────
//   iPad (MagicMotion) ──BLE write──► M5StickC Plus2 (CMD characteristic)
//                                          │
//                                          ▼
//                              NimBLE HID notify (D-pad hat switch)
//                                          │
//                                          ▼
//                            iOS HID subsystem → foreground game
//
// ── Two BLE roles on the same peripheral ─────────────────────────────────────
//   1. iOS Settings → Bluetooth: pair "M5Gamepad" as a game controller.
//      The HID service on the M5 is used by the OS to route D-pad input to games.
//      BandBLEManager does NOT handle this pairing — it happens in system Settings.
//
//   2. BandBLEManager (this file): CoreBluetooth Central connecting to the
//      custom CMD_SERVICE_UUID to write command bytes.  This is independent of
//      the HID pairing and requires no iOS Settings action beyond Bluetooth being on.
//
// ── GATT layout (matches M5Gamepad firmware) ─────────────────────────────────
//   CMD Service   4fafc201-1fb5-459e-8fcc-c5c9c331914b
//   CMD Char      beb5483e-36e1-4688-b7f5-ea07361b26a8  (write-without-response)
//
// ── Command bytes (write to CMD_CHAR from iOS) ────────────────────────────────
//   0x01  Move Left   → D-pad HAT_LEFT   (lane left)
//   0x02  Move Right  → D-pad HAT_RIGHT  (lane right)
//   0x03  Jump        → D-pad HAT_UP     (jump / fly)
//   0x04  Slide       → D-pad HAT_DOWN   (crouch / roll)
//   0x00  Neutral     → D-pad released   (always send after each command)
//
// ── Neutral release ───────────────────────────────────────────────────────────
//   The firmware latches the D-pad direction until the next write.  After every
//   command byte, this manager schedules a 0x00 neutral release after
//   `commandHoldDuration` (default 150 ms) so the game receives a momentary
//   press, not a held direction.
//
// ── Reconnect behaviour ───────────────────────────────────────────────────────
//   On disconnect → scan restarts after 3 s.
//   On BT power-on → checks retrieveConnectedPeripherals first (handles the case
//   where M5Gamepad is already bonded as HID and may not appear in fresh scans).
//
// ── Concurrency ───────────────────────────────────────────────────────────────
//   SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor is set project-wide.
//   nonisolated(unsafe) on CBCentral/CBPeripheral stored props opts out so
//   CoreBluetooth can call delegate methods from its own queue.
//   All @Published mutations hop back to the main actor explicitly.

import Combine
import CoreBluetooth
import Foundation

// MARK: - Constants

private enum BandBLE {
    /// CMD service UUID — matches CMD_SERVICE_UUID in M5Gamepad firmware.
    static let serviceUUID     = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    /// CMD characteristic UUID — matches CMD_CHAR_UUID in M5Gamepad firmware.
    static let gestureCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    /// Advertised device name in firmware: #define DEVICE_NAME "M5Gamepad"
    static let deviceNameMatch = "M5Gamepad"
    static let reconnectDelay: TimeInterval = 3.0
}

// MARK: - BandBLEManager

/// Manages the CoreBluetooth Central role for the M5StickC Plus2 controller.
/// Gracefully degrades — all sends are no-ops when the device is off or disconnected.
@MainActor
final class BandBLEManager: NSObject, ObservableObject {

    // MARK: - Published state (always mutated on MainActor)

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var statusText: String = "Band: Off"
    /// Last GameCommand successfully handed to the BLE write path. Nil until first send.
    @Published private(set) var lastSentCommand: GameCommand?

    // MARK: - Configuration

    /// How long (seconds) a command D-pad direction is held before the neutral
    /// release byte (0x00) is sent.  Tune per game if needed; 0.15 s works for
    /// Subway Surfers (momentary lane-change press).
    var commandHoldDuration: TimeInterval = 0.15

    // MARK: - Private CoreBluetooth
    // nonisolated(unsafe): accessed from MainActor and the BLE queue.
    // CoreBluetooth serialises its own callbacks — no additional locking needed.

    nonisolated(unsafe) private var centralManager: CBCentralManager!
    nonisolated(unsafe) private var peripheral: CBPeripheral?
    nonisolated(unsafe) private var gestureCharacteristic: CBCharacteristic?
    private let bleQueue = DispatchQueue(label: "com.magicmotion.ble", qos: .userInitiated)

    // Timer that fires the neutral release byte after each command.
    private var neutralReleaseTimer: DispatchWorkItem?

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: nil
        )
    }

    // MARK: - Public API

    /// Send a GameCommand to the M5StickC Plus2.
    /// Schedules a neutral (0x00) release after `commandHoldDuration`.
    /// No-op when not connected.
    func send(command: GameCommand) {
        guard isConnected,
              let peripheral = peripheral,
              let characteristic = gestureCharacteristic else { return }

        // Cancel any pending neutral from a previous command.
        neutralReleaseTimer?.cancel()

        let data = Data([command.rawValue])
        lastSentCommand = command
        bleQueue.async {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }
        log("📡 \(command.displayName) → 0x\(String(format: "%02X", command.rawValue))")

        // Schedule D-pad release so the game sees a momentary press, not a held direction.
        let work = DispatchWorkItem { [weak self] in
            self?.sendNeutral()
        }
        neutralReleaseTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + commandHoldDuration, execute: work)
    }

    /// Release the D-pad (send neutral 0x00).
    /// Call explicitly on session end or pause to guarantee a clean controller state.
    func sendNeutral() {
        neutralReleaseTimer?.cancel()
        neutralReleaseTimer = nil
        guard isConnected,
              let peripheral = peripheral,
              let characteristic = gestureCharacteristic else { return }
        bleQueue.async {
            peripheral.writeValue(Data([0x00]), for: characteristic, type: .withoutResponse)
        }
        log("📡 NEUTRAL → 0x00")
    }

    /// Low-level send: write a single arbitrary byte to the CMD characteristic.
    /// Prefer `send(command:)` for normal use.
    func send(rawByte byte: UInt8) {
        guard isConnected,
              let peripheral = peripheral,
              let characteristic = gestureCharacteristic else { return }
        let data = Data([byte])
        bleQueue.async {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }
    }

    // MARK: - Private scan helpers

    nonisolated private func startScan() {
        guard centralManager.state == .poweredOn, !centralManager.isScanning else { return }
        setStatus("Band: Scanning…")
        centralManager.scanForPeripherals(
            withServices: [BandBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log("🔍 Scanning for \(BandBLE.deviceNameMatch)…")
    }

    nonisolated private func stopScan() {
        if centralManager.isScanning { centralManager.stopScan() }
    }

    /// Before scanning, check whether M5Gamepad is already connected (bonded as HID).
    /// A BLE peripheral that is paired to the iOS HID subsystem may not reappear in scans.
    nonisolated private func connectIfAlreadyKnown() {
        let known = centralManager.retrieveConnectedPeripherals(withServices: [BandBLE.serviceUUID])
        if let already = known.first(where: { $0.name == BandBLE.deviceNameMatch }) {
            log("♻️ Already connected peripheral found — attaching directly")
            self.peripheral = already
            already.delegate = self
            centralManager.connect(already, options: nil)
            setStatus("Band: Reconnecting…")
        } else {
            startScan()
        }
    }

    nonisolated private func reconnectAfterDelay() {
        DispatchQueue.global().asyncAfter(deadline: .now() + BandBLE.reconnectDelay) { [weak self] in
            self?.connectIfAlreadyKnown()
        }
    }

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
            log("✅ Bluetooth on — checking for known peripherals")
            setStatus("Band: Ready")
            connectIfAlreadyKnown()
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
        guard name == BandBLE.deviceNameMatch else { return }
        log("📡 Found: \(name) (RSSI \(RSSI)) — connecting…")
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
        log("❌ Failed to connect: \(error?.localizedDescription ?? "?")")
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
}

// MARK: - CBPeripheralDelegate

extension BandBLEManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        if let err = error { log("❌ Service discovery: \(err)"); return }
        peripheral.services?
            .filter { $0.uuid == BandBLE.serviceUUID }
            .forEach { peripheral.discoverCharacteristics([BandBLE.gestureCharUUID], for: $0) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        if let err = error { log("❌ Characteristic discovery: \(err)"); return }
        if let char = service.characteristics?.first(where: { $0.uuid == BandBLE.gestureCharUUID }) {
            gestureCharacteristic = char
            setConnected(true)
            log("✅ Ready — M5Gamepad CMD characteristic online")
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        // CMD char uses write-without-response so this delegate fires only on errors.
        if let err = error { log("❌ Write error: \(err)") }
    }
}
