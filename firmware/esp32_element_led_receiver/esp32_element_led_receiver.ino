/*
 * Element AV Synth — Bidirectional ESP32 BLE LED Receiver & Telemetry Broadcaster
 *
 * GATT Service UUID:            E1E00001-5A3C-4F92-8B1A-0000A1B2C3D4
 * TX Command Characteristic:    E1E00002-5A3C-4F92-8B1A-0000A1B2C3D4 (Write / WriteNoResp, 8 bytes)
 * RX Telemetry Characteristic:  E1E00003-5A3C-4F92-8B1A-0000A1B2C3D4 (Notify, 6 bytes every 250 ms)
 *
 * 8-Byte Command Packet (iOS -> ESP32):
 *   [0] 0xAA           Header
 *   [1] Z              Atomic Number (1..118)
 *   [2] H              Dominant Hue (0..255)
 *   [3] S              Saturation (0..255)
 *   [4] V              Value / Brightness (0..255)
 *   [5] PulseDur_MSB   Pulse Duration High Byte (ms; 0x0000 = steady continuous light)
 *   [6] PulseDur_LSB   Pulse Duration Low Byte (ms)
 *   [7] CRC            Sum of bytes[0..6] & 0xFF
 *
 * 6-Byte Telemetry Packet (ESP32 -> iOS Notify):
 *   [0] 0xBB           Telemetry Header
 *   [1] Lux_MSB        Ambient Photodiode Lux High Byte (uint16)
 *   [2] Lux_LSB        Ambient Photodiode Lux Low Byte (uint16)
 *   [3] TempC          Heatsink Temperature in deg C (int8 signed two's complement)
 *   [4] MeasuredFPS    Measured LED refresh rate (uint8 FPS)
 *   [5] CRC            Sum of bytes[0..4] & 0xFF
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <FastLED.h>

#define SERVICE_UUID          "E1E00001-5A3C-4F92-8B1A-0000A1B2C3D4"
#define COMMAND_CHAR_UUID     "E1E00002-5A3C-4F92-8B1A-0000A1B2C3D4"
#define TELEMETRY_CHAR_UUID   "E1E00003-5A3C-4F92-8B1A-0000A1B2C3D4"

#define LED_PIN               5
#define NUM_LEDS              16
#define PHOTODIODE_ADC_PIN    34
#define TELEMETRY_INTERVAL_MS 250

CRGB leds[NUM_LEDS];
BLECharacteristic *pTelemetryChar = nullptr;
volatile bool deviceConnected = false;

volatile uint8_t currentZ = 0;
volatile uint8_t targetH = 0, targetS = 255, targetV = 0;
volatile uint16_t pulseMs = 0;

unsigned long lastToggleMs = 0;
unsigned long lastTelemetryMs = 0;
uint32_t frameCounter = 0;
bool ledStateOn = true;

class ReceiverServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    deviceConnected = true;
  }
  void onDisconnect(BLEServer *pServer) override {
    deviceConnected = false;
    BLEDevice::startAdvertising();
  }
};

class SpectralPacketCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    std::string value = pCharacteristic->getValue();
    if (value.size() != 8) return;

    const uint8_t *b = reinterpret_cast<const uint8_t *>(value.data());
    if (b[0] != 0xAA) return;

    uint8_t crc = 0;
    for (int i = 0; i < 7; i++) crc = (crc + b[i]) & 0xFF;
    if (crc != b[7]) return;

    currentZ = b[1];
    targetH  = b[2];
    targetS  = b[3];
    targetV  = b[4];
    pulseMs  = (static_cast<uint16_t>(b[5]) << 8) | b[6];
    ledStateOn = true;
    lastToggleMs = millis();
  }
};

static void sendTelemetryFrame(uint16_t ambientLux, int8_t heatsinkTempC, uint8_t measuredFPS) {
  if (!deviceConnected || pTelemetryChar == nullptr) return;

  uint8_t frame[6];
  frame[0] = 0xBB;
  frame[1] = static_cast<uint8_t>((ambientLux >> 8) & 0xFF);
  frame[2] = static_cast<uint8_t>(ambientLux & 0xFF);
  frame[3] = static_cast<uint8_t>(heatsinkTempC);
  frame[4] = measuredFPS;

  uint8_t crc = 0;
  for (int i = 0; i < 5; i++) crc = (crc + frame[i]) & 0xFF;
  frame[5] = crc;

  pTelemetryChar->setValue(frame, 6);
  pTelemetryChar->notify();
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);

  FastLED.addLeds<WS2812B, LED_PIN, GRB>(leds, NUM_LEDS);
  FastLED.clear(true);

  BLEDevice::init("ElementAV-LED");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ReceiverServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic *pCommandChar = pService->createCharacteristic(
    COMMAND_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pCommandChar->setCallbacks(new SpectralPacketCallback());

  pTelemetryChar = pService->createCharacteristic(
    TELEMETRY_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTelemetryChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();
}

void loop() {
  unsigned long now = millis();

  if (pulseMs == 0) {
    fill_solid(leds, NUM_LEDS, CHSV(targetH, targetS, targetV));
    FastLED.show();
    frameCounter++;
    delay(8);
  } else if (now - lastToggleMs >= pulseMs) {
    lastToggleMs = now;
    ledStateOn = !ledStateOn;
    fill_solid(leds, NUM_LEDS, ledStateOn ? CHSV(targetH, targetS, targetV) : CRGB::Black);
    FastLED.show();
    frameCounter++;
  }

  // Stream 6-byte hardware telemetry every 250 ms when subscribed
  unsigned long elapsed = now - lastTelemetryMs;
  if (elapsed >= TELEMETRY_INTERVAL_MS) {
    uint16_t rawAdc = static_cast<uint16_t>(analogRead(PHOTODIODE_ADC_PIN));
    uint16_t ambientLux = static_cast<uint16_t>((static_cast<uint32_t>(rawAdc) * 2000UL) / 4095UL);
    int8_t tempC = static_cast<int8_t>(constrain(static_cast<int>(temperatureRead()), -40, 125));
    uint32_t fpsCalc = (frameCounter * 1000UL) / max(elapsed, 1UL);
    uint8_t measuredFPS = static_cast<uint8_t>(min<uint32_t>(fpsCalc, 255UL));

    sendTelemetryFrame(ambientLux, tempC, measuredFPS);
    frameCounter = 0;
    lastTelemetryMs = now;
  }
}
