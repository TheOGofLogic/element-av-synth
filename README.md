# Element AV Synth — Spectral Audiovisual Synthesizer & BLE Light Controller

Native SwiftUI / iOS 16+ instrument that maps NIST atomic emission lines (380–780 nm) into synchronized Display-P3 light pulses, polyphonic `AVAudioSourceNode` harmonic chords, and 8-byte CoreBluetooth LE packets for external LED controllers (ESP32 / Nordic nRF52).

## Architecture

- **`Sources/ElementAVCore/SpectralMapping.swift`**: `SpectralLine` (Dan Bruton nm→sRGB/Display-P3 + continuous 700–780 nm tail, HSV, hex, logarithmic `audioFrequencyHz`, MIDI pitch), `ChemicalElementSynth` (atomic-mass pulse duration, composite discharge glow), and `BLELightPacket` (8-byte framing + Sum8 CRC parser/validator).
- **`Sources/ElementAVCore/ElementCatalog.swift`**: Complete 118-element IUPAC periodic table with NIST visible emission spectra (Z = 1–99) and relativistic bands (Z = 100–118), plus search and category filtering.
- **`Sources/ElementAVCore/MetalPlasmaView.swift`** & **`ios/Shaders/SpectralPlasma.metal`**: 120 Hz GPU-accelerated gas-discharge plasma visualizer with 16-byte-aligned `SIMD4`/`float4` uniforms (304 bytes).
- **`Sources/ElementAVCore/SpectralAudioSynthesizer.swift`**: Lock-protected real-time `SpectralRenderKernel` + `AVAudioEngine` / `AVAudioSourceNode` additive polyphonic synthesizer and deterministic `AVBeatClock`.
- **`Sources/ElementAVCore/SpectralFlasherView.swift`**: 60–120 Hz `CADisplayLink`-driven, Metal-backed extended-linear Display-P3 full-screen strobe/pulse view with photosensitivity safe-rate cap (≤ 2.5 Hz default) and explicit raw-strobe opt-in warning.
- **`Sources/ElementAVCore/BLELightControllerManager.swift`**: `CBCentralManager` + `CBPeripheral` GATT scanner/writer supporting the ElementAV Light Service (`E1E00001-5A3C-4F92-8B1A-0000A1B2C3D4`) and Nordic UART Service (NUS) fallback.
- **`Sources/ElementAVCore/ElementSynthDashboardView.swift`**: 3-tab SwiftUI instrument (`Synth`, `BLE Light`, `Spectrum`).
- **`firmware/esp32_element_led_receiver/esp32_element_led_receiver.ino`**: Reference ESP32 + FastLED BLE GATT receiver decoding the exact 8-byte packet format.

## 8-Byte BLE Packet Layout

| Byte | Field | Description |
| :---: | :--- | :--- |
| `0` | `0xAA` | Header / MsgID |
| `1` | `Z` | Atomic number (`1...118`) |
| `2` | `H` | Dominant/composite Hue (`0...255`) |
| `3` | `S` | Saturation (`0...255`) |
| `4` | `V` | Value / Brightness (`0...255`) |
| `5` | `PulseDur_MSB` | Pulse duration high byte (ms; `0x0000` = steady light) |
| `6` | `PulseDur_LSB` | Pulse duration low byte (ms) |
| `7` | `CRC` | `(bytes[0] + ... + bytes[6]) & 0xFF` |

## Build & Test (macOS / CI)

```bash
# Run SwiftPM XCTest suite
swift test

# Generate Xcode project
cd ios && xcodegen generate
```
