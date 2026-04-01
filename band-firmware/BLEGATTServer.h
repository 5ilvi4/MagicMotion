#pragma once

// ============================================================
// BLEGATTServer.h — BLE GATT Peripheral (0xFFF0 service)
// Receives gesture bytes and session metadata from iPad.
// ============================================================

#include <Arduino.h>
#include <functional>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "Config.h"

// Forward-declared so DisplayManager.h doesn't need to include BLE headers
struct SessionMetadata {
    float   confidence  = 0.0f;
    float   accuracy    = 0.0f;
    uint8_t score       = 0;
    bool    isRunning   = false;
};

// ============================================================
class BLEGATTServer {
public:
    using GestureCallback       = std::function<void(uint8_t)>;
    using SessionUpdateCallback = std::function<void(const SessionMetadata&)>;
    using ConnectCallback       = std::function<void()>;
    using DisconnectCallback    = std::function<void()>;

    // --------------------------------------------------------
    // Initialise BLE stack and start advertising
    // --------------------------------------------------------
    void begin() {
        BLEDevice::init(BLE_DEVICE_NAME);
        BLEDevice::setMTU(64);

        _pServer = BLEDevice::createServer();
        _pServer->setCallbacks(&_serverCB);
        _serverCB._parent = this;

        BLEService* pService = _pServer->createService(BLE_SERVICE_UUID);

        // 0xFFF1 — Gesture characteristic (iPad writes, band reads)
        _pGestureChar = pService->createCharacteristic(
            BLE_GESTURE_CHAR_UUID,
            BLECharacteristic::PROPERTY_WRITE |
            BLECharacteristic::PROPERTY_WRITE_NR
        );
        _pGestureChar->setCallbacks(&_charCB);
        _charCB._parent = this;

        // 0xFFF2 — Session metadata characteristic (iPad writes)
        _pSessionChar = pService->createCharacteristic(
            BLE_SESSION_CHAR_UUID,
            BLECharacteristic::PROPERTY_WRITE
        );
        _pSessionChar->setCallbacks(&_charCB);

        pService->start();
        _startAdvertising();

        Serial.println("[BLE] GATT server started — advertising as \"" BLE_DEVICE_NAME "\"");
    }

    // --------------------------------------------------------
    // Callback setters
    // --------------------------------------------------------
    void onGesture(GestureCallback cb)            { _gestureCB = cb; }
    void onSessionUpdate(SessionUpdateCallback cb) { _sessionCB = cb; }
    void onConnect(ConnectCallback cb)             { _connectCB = cb; }
    void onDisconnect(DisconnectCallback cb)       { _disconnectCB = cb; }

    // --------------------------------------------------------
    // Poll-style API (used inside main loop)
    // --------------------------------------------------------
    bool hasNewGesture() const  { return _newGestureReady; }

    uint8_t consumeGesture() {
        _newGestureReady = false;
        return _lastGestureCode;
    }

    bool isClientConnected() const { return _clientConnected; }

    // --------------------------------------------------------
    // Optional: restart advertising after disconnect
    // --------------------------------------------------------
    void restartAdvertising() {
        _startAdvertising();
    }

private:
    BLEServer*          _pServer       = nullptr;
    BLECharacteristic*  _pGestureChar  = nullptr;
    BLECharacteristic*  _pSessionChar  = nullptr;

    GestureCallback       _gestureCB;
    SessionUpdateCallback _sessionCB;
    ConnectCallback       _connectCB;
    DisconnectCallback    _disconnectCB;

    volatile bool    _newGestureReady  = false;
    volatile uint8_t _lastGestureCode  = GESTURE_CODE_NOP;
    volatile bool    _clientConnected  = false;

    void _startAdvertising() {
        BLEAdvertising* pAdv = BLEDevice::getAdvertising();
        pAdv->addServiceUUID(BLE_SERVICE_UUID);
        pAdv->setScanResponse(true);
        pAdv->setMinPreferred(0x06);  // iPhone connection interval hint
        pAdv->setMaxPreferred(0x12);
        BLEDevice::startAdvertising();
        Serial.println("[BLE] Advertising started");
    }

    // --------------------------------------------------------
    // Inner class: server lifecycle callbacks
    // --------------------------------------------------------
    struct ServerCB : public BLEServerCallbacks {
        BLEGATTServer* _parent = nullptr;

        void onConnect(BLEServer*) override {
            Serial.println("[BLE] Client connected");
            _parent->_clientConnected = true;
            if (_parent->_connectCB) _parent->_connectCB();
        }

        void onDisconnect(BLEServer* pServer) override {
            Serial.println("[BLE] Client disconnected — restarting advertising");
            _parent->_clientConnected = false;
            if (_parent->_disconnectCB) _parent->_disconnectCB();
            // Auto-restart so iPad can reconnect
            pServer->getAdvertising()->start();
        }
    } _serverCB;

    // --------------------------------------------------------
    // Inner class: characteristic write callbacks
    // --------------------------------------------------------
    struct CharCB : public BLECharacteristicCallbacks {
        BLEGATTServer* _parent = nullptr;

        void onWrite(BLECharacteristic* pChar) override {
            std::string val = pChar->getValue();
            if (val.empty()) return;

            std::string uuid = pChar->getUUID().toString();

            // --- Gesture characteristic ---
            if (uuid == BLE_GESTURE_CHAR_UUID) {
                uint8_t code = static_cast<uint8_t>(val[0]);
                Serial.printf("[BLE] Gesture received: 0x%02X\n", code);
                _parent->_lastGestureCode  = code;
                _parent->_newGestureReady  = true;
                if (_parent->_gestureCB) _parent->_gestureCB(code);
            }

            // --- Session metadata characteristic ---
            // Protocol: 6 bytes [flags(1), score(1), confidence*100(2), accuracy*100(2)]
            else if (uuid == BLE_SESSION_CHAR_UUID && val.size() >= 6) {
                SessionMetadata meta;
                meta.isRunning   = (val[0] & 0x01) != 0;
                meta.score       = static_cast<uint8_t>(val[1]);
                uint16_t conf100 = (static_cast<uint16_t>(val[3]) << 8) | static_cast<uint8_t>(val[2]);
                uint16_t acc100  = (static_cast<uint16_t>(val[5]) << 8) | static_cast<uint8_t>(val[4]);
                meta.confidence  = conf100 / 100.0f;
                meta.accuracy    = acc100  / 100.0f;
                Serial.printf("[BLE] Session update: running=%d conf=%.2f acc=%.2f score=%d\n",
                              meta.isRunning, meta.confidence, meta.accuracy, meta.score);
                if (_parent->_sessionCB) _parent->_sessionCB(meta);
            }
        }
    } _charCB;
};
