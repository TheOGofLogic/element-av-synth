import Foundation
import SwiftUI
import CoreGraphics

// MARK: - Spectral Line Definition

public struct SpectralLine: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let wavelengthNm: Double      // e.g. 589.0 nm (Sodium D line)
    public let relativeIntensity: Double // 0.0 - 1.0 (transition probability)
    public let label: String?            // Optional spectroscopic designation (e.g. "H-alpha", "D2")

    public init(
        id: UUID = UUID(),
        wavelengthNm: Double,
        relativeIntensity: Double,
        label: String? = nil
    ) {
        self.id = id
        self.wavelengthNm = wavelengthNm
        self.relativeIntensity = min(max(relativeIntensity, 0.0), 1.0)
        self.label = label
    }

    /// Raw sRGB components (0.0 - 1.0) derived from nanometer wavelength via Dan Bruton's algorithm.
    public var srgbComponents: (r: Double, g: Double, b: Double) {
        Self.nmToRGB(wavelengthNm)
    }

    /// HSV components (h: 0..<360, s: 0...1, v: 0...1) for the spectral line color.
    public var hsvComponents: (h: Double, s: Double, v: Double) {
        let (r, g, b) = srgbComponents
        return Self.rgbToHSV(r: r, g: g, b: b)
    }

    /// Uppercase sRGB hex representation (e.g. "#FFDD00").
    public var hexString: String {
        let (r, g, b) = srgbComponents
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255.0).rounded()),
            Int((g * 255.0).rounded()),
            Int((b * 255.0).rounded())
        )
    }

    /// Converts nanometer wavelength (380 - 780 nm) to sRGB SwiftUI Color weighted by relative intensity.
    public var displayColor: Color {
        let (r, g, b) = srgbComponents
        return Color(red: r, green: g, blue: b).opacity(relativeIntensity)
    }

    /// Wide-gamut Display-P3 representation for vibrant OLED/ProMotion light flash rendering.
    public var displayP3Color: Color {
        let (r, g, b) = srgbComponents
        return Color(.displayP3, red: r, green: g, blue: b, opacity: relativeIntensity)
    }

    /// Full-opacity spectral color (useful for swatches, badges, and full-brightness LED drive).
    public var fullIntensityColor: Color {
        let (r, g, b) = srgbComponents
        return Color(.displayP3, red: r, green: g, blue: b, opacity: 1.0)
    }

    /// Maps optical wavelength into audible frequency space (logarithmic octave scaling).
    /// 380 nm -> High C (C7 ~ 2093 Hz), 750 nm -> Low A (A2 ~ 110 Hz).
    public var audioFrequencyHz: Float {
        let minNm = 380.0
        let maxNm = 750.0
        let clamped = min(max(wavelengthNm, minNm), maxNm)

        // Inverted logarithmic mapping: longer wavelength (red) = lower bass, shorter (violet) = high pitch
        let norm = (clamped - minNm) / (maxNm - minNm) // 0 (violet) to 1 (red)
        let minFreq: Float = 110.0   // A2
        let maxFreq: Float = 2093.0  // C7

        return maxFreq * pow(minFreq / maxFreq, Float(norm))
    }

    /// Fractional MIDI note number corresponding to `audioFrequencyHz` (A4 = 69 = 440 Hz).
    public var midiNoteNumber: Double {
        69.0 + 12.0 * log2(Double(audioFrequencyHz) / 440.0)
    }

    /// Nearest standard pitch name (e.g., "F#4").
    public var musicalNoteName: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let rounded = Int(midiNoteNumber.rounded())
        let noteIndex = ((rounded % 12) + 12) % 12
        let octave = (rounded / 12) - 1
        return "\(names[noteIndex])\(octave)"
    }

    /// Algorithmic Wavelength to sRGB approximation (Dan Bruton algorithm with continuous 700-780 nm tail).
    public static func nmToRGB(_ nm: Double) -> (r: Double, g: Double, b: Double) {
        var r = 0.0, g = 0.0, b = 0.0

        switch nm {
        case 380..<440:
            r = -(nm - 440.0) / (440.0 - 380.0)
            b = 1.0
        case 440..<490:
            g = (nm - 440.0) / (490.0 - 440.0)
            b = 1.0
        case 490..<510:
            g = 1.0
            b = -(nm - 510.0) / (510.0 - 490.0)
        case 510..<580:
            r = (nm - 510.0) / (580.0 - 510.0)
            g = 1.0
        case 580..<645:
            r = 1.0
            g = -(nm - 645.0) / (645.0 - 580.0)
        case 645...780:
            r = 1.0
        default:
            break
        }

        // Intensity fall-off near human vision limits (continuous across 700 nm boundary)
        let factor: Double
        switch nm {
        case 380..<420:
            factor = 0.3 + 0.7 * (nm - 380.0) / (420.0 - 380.0)
        case 420..<700:
            factor = 1.0
        case 700...780:
            factor = 0.3 + 0.7 * (780.0 - nm) / (780.0 - 700.0)
        default:
            factor = 0.0
        }

        let gamma = 0.8
        let adjust: (Double) -> Double = { c in
            let scaled = c * factor
            return scaled <= 0.0 ? 0.0 : pow(scaled, gamma)
        }

        return (adjust(r), adjust(g), adjust(b))
    }

    /// Converts normalized sRGB (0...1) into HSV (h: 0..<360, s: 0...1, v: 0...1).
    public static func rgbToHSV(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC

        var hue = 0.0
        if delta > 0.0 {
            if maxC == r {
                hue = (g - b) / delta
            } else if maxC == g {
                hue = 2.0 + (b - r) / delta
            } else {
                hue = 4.0 + (r - g) / delta
            }
            hue *= 60.0
            if hue < 0.0 { hue += 360.0 }
        }

        let sat = maxC == 0.0 ? 0.0 : (delta / maxC)
        return (hue, sat, maxC)
    }
}

// MARK: - 8-Byte BLE Light Controller Packet

/// Structured 8-byte CoreBluetooth LE peripheral payload:
/// `[0: 0xAA Header, 1: Atomic Z, 2: Dominant H, 3: S, 4: V, 5: PulseDur_MSB, 6: PulseDur_LSB, 7: Sum8 CRC]`
public struct BLELightPacket: Equatable, Sendable {
    public static let headerByte: UInt8 = 0xAA
    public static let byteLength: Int = 8

    public let atomicNumber: UInt8
    public let hue: UInt8
    public let saturation: UInt8
    public let value: UInt8
    public let pulseDurationMs: UInt16

    public init(
        atomicNumber: UInt8,
        hue: UInt8,
        saturation: UInt8,
        value: UInt8,
        pulseDurationMs: UInt16
    ) {
        self.atomicNumber = atomicNumber
        self.hue = hue
        self.saturation = saturation
        self.value = value
        self.pulseDurationMs = pulseDurationMs
    }

    public var data: Data {
        var bytes: [UInt8] = [
            Self.headerByte,
            atomicNumber,
            hue,
            saturation,
            value,
            UInt8((pulseDurationMs >> 8) & 0xFF),
            UInt8(pulseDurationMs & 0xFF),
            0x00
        ]
        bytes[7] = Self.checksum(bytes[0..<7])
        return Data(bytes)
    }

    public var checksumByte: UInt8 {
        data[7]
    }

    public var hexDescription: String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(UInt8(0)) { acc, byte in
            acc &+ byte
        }
    }

    /// Parses and validates an 8-byte BLE light controller packet (header + checksum).
    public static func parse(_ data: Data) -> BLELightPacket? {
        guard data.count == byteLength else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == headerByte else { return nil }
        guard checksum(bytes[0..<7]) == bytes[7] else { return nil }

        let ms = (UInt16(bytes[5]) << 8) | UInt16(bytes[6])
        return BLELightPacket(
            atomicNumber: bytes[1],
            hue: bytes[2],
            saturation: bytes[3],
            value: bytes[4],
            pulseDurationMs: ms
        )
    }
}

// MARK: - Chemical Element Model

public struct ChemicalElementSynth: Identifiable, Hashable, Sendable {
    public let id: Int                 // Atomic Number (Z)
    public let symbol: String          // e.g. "Na"
    public let name: String            // e.g. "Sodium"
    public let category: String        // e.g. "Alkali Metal", "Noble Gas"
    public let atomicMass: Double
    public let spectralLines: [SpectralLine]

    public init(
        id: Int,
        symbol: String,
        name: String,
        category: String = "Element",
        atomicMass: Double,
        spectralLines: [SpectralLine]
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.category = category
        self.atomicMass = atomicMass
        self.spectralLines = spectralLines
    }

    /// Strongest emission line by relative intensity.
    public var dominantLine: SpectralLine? {
        spectralLines.max(by: { $0.relativeIntensity < $1.relativeIntensity })
    }

    /// Intensity-weighted composite sRGB color mimicking an atomic gas discharge tube.
    public var compositeRGB: (r: Double, g: Double, b: Double) {
        guard !spectralLines.isEmpty else { return (1.0, 1.0, 1.0) }
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        for line in spectralLines {
            let (r, g, b) = line.srgbComponents
            sumR += r * line.relativeIntensity
            sumG += g * line.relativeIntensity
            sumB += b * line.relativeIntensity
        }
        let peak = max(sumR, max(sumG, sumB))
        guard peak > 0.0 else { return (1.0, 1.0, 1.0) }
        return (sumR / peak, sumG / peak, sumB / peak)
    }

    public var compositeDisplayColor: Color {
        let (r, g, b) = compositeRGB
        return Color(.displayP3, red: r, green: g, blue: b, opacity: 1.0)
    }

    /// Strobe pulse duration in milliseconds derived from atomic mass.
    /// Lighter elements pulse faster (Hydrogen ~ 40 ms, Uranium ~ 242 ms), clamped to 30...400 ms.
    public var pulseDurationMs: Int {
        let base = 40.0 + (atomicMass * 0.85)
        return min(max(Int(base), 30), 400)
    }

    /// Builds the 8-byte Bluetooth LE Peripheral Packet:
    /// `[0: MsgID (0xAA), 1: Z, 2: Dominant H, 3: S, 4: V, 5: PulseDur_MSB, 6: PulseDur_LSB, 7: CRC]`
    /// - Parameters:
    ///   - brightnessScale: Optional master brightness multiplier (0.0...1.0).
    ///   - pulseDurationOverrideMs: Optional pulse duration override (e.g. `0` for steady non-strobing light, or safe-mode slowed rate).
    ///   - useCompositeColor: If true, blends all emission lines instead of using only the single strongest line.
    public func makeBLEPacketStruct(
        brightnessScale: Double = 1.0,
        pulseDurationOverrideMs: UInt16? = nil,
        useCompositeColor: Bool = false
    ) -> BLELightPacket {
        let (r, g, b): (Double, Double, Double)
        if useCompositeColor {
            (r, g, b) = compositeRGB
        } else if let dominant = dominantLine {
            (r, g, b) = SpectralLine.nmToRGB(dominant.wavelengthNm)
        } else {
            (r, g, b) = (1.0, 1.0, 1.0)
        }

        let (hue, sat, val) = SpectralLine.rgbToHSV(r: r, g: g, b: b)
        let clampedScale = min(max(brightnessScale, 0.0), 1.0)

        let hByte = UInt8(min(max((hue / 360.0) * 255.0, 0.0), 255.0).rounded())
        let sByte = UInt8(min(max(sat * 255.0, 0.0), 255.0).rounded())
        let vByte = UInt8(min(max(val * clampedScale * 255.0, 0.0), 255.0).rounded())
        let ms = pulseDurationOverrideMs ?? UInt16(pulseDurationMs)

        return BLELightPacket(
            atomicNumber: UInt8(id & 0xFF),
            hue: hByte,
            saturation: sByte,
            value: vByte,
            pulseDurationMs: ms
        )
    }

    /// Convenience method matching the baseline API signature returning raw 8-byte `Data`.
    public func makeBLEPacket(
        brightnessScale: Double = 1.0,
        pulseDurationOverrideMs: UInt16? = nil,
        useCompositeColor: Bool = false
    ) -> Data {
        makeBLEPacketStruct(
            brightnessScale: brightnessScale,
            pulseDurationOverrideMs: pulseDurationOverrideMs,
            useCompositeColor: useCompositeColor
        ).data
    }
}
