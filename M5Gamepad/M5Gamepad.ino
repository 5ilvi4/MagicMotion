/*
 * M5Gamepad — M5StickC Plus2 BLE HID Gamepad + Command Receiver
 * Repository: https://github.com/5ilvi4/MagicMotion
 *
 * Architecture:
 *   [MagicMotion iPad App] --BLE write (CoreBluetooth)--> [CMD_CHAR on this device]
 *   [This device HID Gamepad]  --BLE HID notify--> [iPadOS → game]
 *
 * Two BLE roles on the same device:
 *   1. HID Gamepad service  — pair this in iOS Settings → Bluetooth as a game controller.
 *      The OS routes D-pad input to the foreground game automatically.
 *   2. CMD service          — MagicMotion app (CoreBluetooth) writes command bytes here.
 *      BandBLEManager.swift handles this connection independently of the HID pairing.
 *
 * Setup:
 *   1. Install required libraries (see below).
 *   2. Upload this sketch to M5StickC Plus2.
 *   3. On iPad: Settings → Bluetooth → pair "M5Gamepad".
 *   4. MagicMotion app auto-connects to the CMD service via CoreBluetooth.
 *   5. Body gestures detected by MagicMotion are mapped to command bytes and sent to this device.
 *
 * Command bytes written to CMD_CHAR_UUID from MagicMotion:
 *   0x00 = Neutral / release  (BandBLEManager sends this automatically after each command)
 *   0x01 = Left               (lane left / move left)
 *   0x02 = Right              (lane right / move right)
 *   0x03 = Up                 (jump)
 *   0x04 = Down               (crouch / slide)
 *
 * Required libraries (install via Arduino IDE Library Manager):
 *   - M5StickCPlus2   by M5Stack        (tested: 1.0.0+)
 *   - NimBLE-Arduino  by h2zero         (tested: 2.3.8+)
 */

#include <M5StickCPlus2.h>
#include <NimBLEDevice.h>
#include <NimBLEHIDDevice.h>

// ── Identity ─────────────────────────────────────────────────────────────────
#define DEVICE_NAME  "M5Gamepad"
#define MANUFACTURER "M5Stack"

// ── Custom GATT service — must match BandBLE constants in BandBLEManager.swift ──
#define CMD_SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CMD_CHAR_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// ── Command bytes (must match GameCommand.rawValue in GameProfileModels.swift) ─
#define CMD_NEUTRAL 0x00
#define CMD_LEFT    0x01
#define CMD_RIGHT   0x02
#define CMD_UP      0x03
#define CMD_DOWN    0x04

// ── HID D-pad hat switch values ───────────────────────────────────────────────
// Hat: 0=N, 2=E, 4=S, 6=W; 8=null/released (out of logical range 0–7)
#define HAT_UP      0x00
#define HAT_RIGHT   0x02
#define HAT_DOWN    0x04
#define HAT_LEFT    0x06
#define HAT_NEUTRAL 0x08

// ── BLE Appearance — Gamepad ──────────────────────────────────────────────────
#define BLE_APPEARANCE_GAMEPAD 0x03C4

// ── HID Report Descriptor — gamepad with one hat switch (D-pad) ──────────────
static const uint8_t reportMap[] = {
    0x05, 0x01,        // Usage Page (Generic Desktop)
    0x09, 0x05,        // Usage (Gamepad)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x01,        //   Report ID (1)
    0x09, 0x39,        //   Usage (Hat switch)
    0x15, 0x00,        //   Logical Minimum (0)
    0x25, 0x07,        //   Logical Maximum (7)
    0x35, 0x00,        //   Physical Minimum (0)
    0x46, 0x3B, 0x01,  //   Physical Maximum (315 degrees)
    0x65, 0x14,        //   Unit (English rotation, degrees)
    0x75, 0x04,        //   Report Size (4 bits)
    0x95, 0x01,        //   Report Count (1)
    0x81, 0x42,        //   Input (Data, Var, Abs, Null state)
    0x75, 0x04,        //   Report Size (4 bits) — padding
    0x95, 0x01,        //   Report Count (1)
    0x81, 0x03,        //   Input (Constant)
    0xC0               // End Collection
};

// ── Globals ───────────────────────────────────────────────────────────────────
NimBLEHIDDevice*      hid         = nullptr;
NimBLECharacteristic* inputReport = nullptr;
NimBLEServer*         pServer     = nullptr;
volatile bool         paired      = false;

// ── Display helper ────────────────────────────────────────────────────────────
void showStatus(const char* line1, const char* line2 = "") {
    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setCursor(4, 20);
    M5.Lcd.println(line1);
    if (line2[0] != '\0') {
        M5.Lcd.setCursor(4, 50);
        M5.Lcd.println(line2);
    }
}

// ── Send HID D-pad report ─────────────────────────────────────────────────────
void sendDPad(uint8_t hat) {
    if (!inputReport || !paired) return;
    uint8_t report[1] = { (uint8_t)(hat & 0x0F) };
    inputReport->setValue(report, 1);
    inputReport->notify();
}

// ── BLE server callbacks ──────────────────────────────────────────────────────
class ServerCallbacks : public NimBLEServerCallbacks {

    void onConnect(NimBLEServer* s, NimBLEConnInfo& info) override {
        paired = true;
        showStatus("Connected!", "");
        // Keep advertising so both the HID host and the app can connect.
        NimBLEDevice::startAdvertising();
    }

    void onDisconnect(NimBLEServer* s, NimBLEConnInfo& info, int reason) override {
        // Only mark unpaired when no clients remain.
        if (s->getConnectedCount() == 0) {
            paired = false;
            showStatus("Disconnected", "Advertising");
        }
        NimBLEDevice::startAdvertising();
    }

    void onAuthenticationComplete(NimBLEConnInfo& info) override {
        if (info.isAuthenticated()) {
            paired = true;
            showStatus("Paired!", DEVICE_NAME);
        }
    }
};

// ── Custom GATT characteristic callbacks (gesture command receiver) ───────────
class CmdCallback : public NimBLECharacteristicCallbacks {

    void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& info) override {
        std::string val = c->getValue();
        if (val.empty()) return;

        uint8_t cmd = (uint8_t)val[0];

        switch (cmd) {
            case CMD_LEFT:
                sendDPad(HAT_LEFT);
                showStatus("< LEFT", "Lane Left");
                break;
            case CMD_RIGHT:
                sendDPad(HAT_RIGHT);
                showStatus("> RIGHT", "Lane Right");
                break;
            case CMD_UP:
                sendDPad(HAT_UP);
                showStatus("^ UP", "Jump");
                break;
            case CMD_DOWN:
                sendDPad(HAT_DOWN);
                showStatus("v DOWN", "Slide");
                break;
            case CMD_NEUTRAL:
            default:
                sendDPad(HAT_NEUTRAL);
                showStatus("READY", "");
                break;
        }
    }
};

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    M5.begin();
    M5.Lcd.setRotation(3);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setTextColor(WHITE);
    showStatus("BLE Init...", "");

    NimBLEDevice::init(DEVICE_NAME);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);  // max TX power

    // JustWorks pairing: bonding + secure connections, no PIN needed
    NimBLEDevice::setSecurityAuth(BLE_SM_PAIR_AUTHREQ_BOND | BLE_SM_PAIR_AUTHREQ_SC);
    NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);

    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());
    pServer->advertiseOnDisconnect(false);  // manual re-advertise for dual connections

    // ── HID service (iPad pairs this as a game controller) ───────────────────
    hid = new NimBLEHIDDevice(pServer);
    hid->setManufacturer(MANUFACTURER);
    hid->setPnp(0x02, 0x05AC, 0x0000, 0x0001);  // Apple vendor ID — required for iOS
    hid->setHidInfo(0x00, 0x01);
    hid->setReportMap((uint8_t*)reportMap, sizeof(reportMap));
    inputReport = hid->getInputReport(1);         // matches Report ID 1 in descriptor
    hid->setBatteryLevel(100);

    // ── Custom command service (MagicMotion app writes gesture bytes here) ────
    NimBLEService* cmdSvc = pServer->createService(CMD_SERVICE_UUID);
    NimBLECharacteristic* cmdChar = cmdSvc->createCharacteristic(
        CMD_CHAR_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    cmdChar->setCallbacks(new CmdCallback());

    // ── Start all services ────────────────────────────────────────────────────
    pServer->start();

    // ── Advertise: gamepad appearance + HID + Battery + custom CMD service ────
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->setAppearance(BLE_APPEARANCE_GAMEPAD);
    adv->setName(DEVICE_NAME);
    adv->addServiceUUID(hid->getHidService()->getUUID());
    adv->addServiceUUID(hid->getBatteryService()->getUUID());
    adv->addServiceUUID(CMD_SERVICE_UUID);
    adv->enableScanResponse(true);
    adv->start();

    showStatus("Advertising", DEVICE_NAME);
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    M5.update();

    // Button A: cycle through D-pad directions for hardware testing (no app needed)
    if (M5.BtnA.wasPressed()) {
        static uint8_t testIdx = 0;
        const uint8_t testSeq[] = { HAT_UP, HAT_RIGHT, HAT_DOWN, HAT_LEFT, HAT_NEUTRAL };
        const char*   testLbl[] = { "TEST: UP", "TEST: RIGHT", "TEST: DOWN", "TEST: LEFT", "TEST: NEUTRAL" };
        sendDPad(testSeq[testIdx]);
        showStatus(testLbl[testIdx], "");
        testIdx = (testIdx + 1) % 5;
    }

    delay(10);
}
