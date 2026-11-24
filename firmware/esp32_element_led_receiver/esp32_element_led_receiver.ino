/*
 * Element AV Synth — Reference ESP32 BLE LED Receiver (Arduino / NimBLE or ESP32 BLE)
 *
 * GATT Service UUID:        E1E00001-5A3C-4F92-8B1A-0000A1B2C3D4
 * Packet Characteristic:    E1E00002-5A3C-4F92-8B1A-0000A1B2C3D4 (Write / WriteNoResp)
 *
 * 8-Byte Packet Format:
 *   [0] 0xAA           Header
 *   [1] Z              Atomic Number (1..118)
 *   [2] H              Dominant Hue (0..255)
 *   [3] S              Saturation (0..255)
 *   [4] V              Value / Brightness (0..255)
 *   [5] PulseDur_MSB   Pulse Duration High Byte (ms; 0x0000 = steady continuous light)
 *   [6] PulseDur_LSB   Pulse Duration Low Byte (ms)
 *   [7] CRC            Sum of bytes[0..6] & 0xFF
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <FastLED.h>

#define SERVICE_UUID        "E1E00001-5A3C-4F92-8B1A-0000A1B2C3D4"
#define CHARACTERISTIC_UUID "E1E00002-5A3C-4F92-8B1A-0000A1B2C3D4"

#define LED_PIN     5
#define NUM_LEDS    16

CRGB leds[NUM_LEDS];
volatile uint8_t currentZ = 0;
volatile uint8_t targetH = 0, targetS = 255, targetV = 0;
volatile uint16_t pulseMs = 0;
unsigned long lastToggleMs = 0;
bool ledStateOn = true;

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

void setup() {
  Serial.begin(115200);
  FastLED.addLeds<WS2812B, LED_PIN, GRB>(leds, NUM_LEDS);
  FastLED.clear(true);

  BLEDevice::init("ElementAV-LED");
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);
  BLECharacteristic *pChar = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pChar->setCallbacks(new SpectralPacketCallback());
  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();
}

void loop() {
  if (pulseMs == 0) {
    fill_solid(leds, NUM_LEDS, CHSV(targetH, targetS, targetV));
    FastLED.show();
    delay(15);
    return;
  }

  unsigned long now = millis();
  if (now - lastToggleMs >= pulseMs) {
    lastToggleMs = now;
    ledStateOn = !ledStateOn;
    fill_solid(leds, NUM_LEDS, ledStateOn ? CHSV(targetH, targetS, targetV) : CRGB::Black);
    FastLED.show();
  }
}
