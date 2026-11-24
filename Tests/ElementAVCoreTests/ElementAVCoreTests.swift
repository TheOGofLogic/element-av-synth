import XCTest
@testable import ElementAVCore

final class ElementAVCoreTests: XCTestCase {

    // MARK: - Wavelength -> RGB & Audio Frequency Mapping

    func testWavelengthToRGBBoundariesAndContinuity() {
        // 380 nm Violet (blue dominant, non-zero red)
        let violet = SpectralLine.nmToRGB(380.0)
        XCTAssertGreaterThan(violet.b, 0.25)
        XCTAssertGreaterThan(violet.r, 0.25)
        XCTAssertEqual(violet.g, 0.0, accuracy: 1e-6)

        // 589 nm Sodium D-line (warm amber-yellow: R=1, G>0.7, B=0)
        let sodium = SpectralLine.nmToRGB(589.0)
        XCTAssertEqual(sodium.r, 1.0, accuracy: 1e-6)
        XCTAssertGreaterThan(sodium.g, 0.70)
        XCTAssertEqual(sodium.b, 0.0, accuracy: 1e-6)

        // 700.5 nm continuity check (must NOT drop to black across 700-701 boundary)
        let deepRed = SpectralLine.nmToRGB(700.5)
        XCTAssertGreaterThan(deepRed.r, 0.90)
        XCTAssertEqual(deepRed.g, 0.0, accuracy: 1e-6)
        XCTAssertEqual(deepRed.b, 0.0, accuracy: 1e-6)

        // Out-of-visible-range yields zero
        let uv = SpectralLine.nmToRGB(250.0)
        XCTAssertEqual(uv.r, 0.0, accuracy: 1e-6)
        XCTAssertEqual(uv.g, 0.0, accuracy: 1e-6)
        XCTAssertEqual(uv.b, 0.0, accuracy: 1e-6)
    }

    func testAudioFrequencyLogarithmicScaling() {
        let violetLine = SpectralLine(wavelengthNm: 380.0, relativeIntensity: 1.0)
        let redLine = SpectralLine(wavelengthNm: 750.0, relativeIntensity: 1.0)
        let midLine = SpectralLine(wavelengthNm: 565.0, relativeIntensity: 1.0)

        XCTAssertEqual(violetLine.audioFrequencyHz, 2093.0, accuracy: 0.5)
        XCTAssertEqual(redLine.audioFrequencyHz, 110.0, accuracy: 0.5)

        // Geometric mean at exact midpoint of wavelength range
        let expectedMid = sqrt(110.0 * 2093.0)
        XCTAssertEqual(Double(midLine.audioFrequencyHz), expectedMid, accuracy: 1.0)
        XCTAssertGreaterThan(violetLine.audioFrequencyHz, midLine.audioFrequencyHz)
        XCTAssertGreaterThan(midLine.audioFrequencyHz, redLine.audioFrequencyHz)
    }

    func testPulseDurationScalingAndClamping() {
        let hydrogen = ElementCatalog.element(symbol: "H")!
        let uranium = ElementCatalog.element(symbol: "U")!

        XCTAssertEqual(hydrogen.pulseDurationMs, 40)
        XCTAssertEqual(uranium.pulseDurationMs, 242)
        XCTAssertLessThan(hydrogen.pulseDurationMs, uranium.pulseDurationMs)

        let superHeavy = ChemicalElementSynth(
            id: 118,
            symbol: "Og",
            name: "Oganesson",
            atomicMass: 999.0,
            spectralLines: [SpectralLine(wavelengthNm: 550.0, relativeIntensity: 1.0)]
        )
        XCTAssertEqual(superHeavy.pulseDurationMs, 400)
    }

    // MARK: - 8-Byte CoreBluetooth Packet Protocol

    func testBLEPacketRoundTripForEntireElementCatalog() {
        XCTAssertGreaterThanOrEqual(ElementCatalog.all.count, 15)

        for element in ElementCatalog.all {
            let raw = element.makeBLEPacket()
            XCTAssertEqual(raw.count, BLELightPacket.byteLength, "Packet for \(element.symbol) must be 8 bytes")
            XCTAssertEqual(raw[0], 0xAA)
            XCTAssertEqual(raw[1], UInt8(element.id & 0xFF))

            let parsed = BLELightPacket.parse(raw)
            XCTAssertNotNil(parsed, "Failed to parse BLE packet for \(element.symbol)")
            XCTAssertEqual(parsed?.atomicNumber, UInt8(element.id & 0xFF))
            XCTAssertEqual(parsed?.pulseDurationMs, UInt16(element.pulseDurationMs))

            // Corrupting a single byte must invalidate checksum
            var corrupted = raw
            corrupted[4] ^= 0x01
            XCTAssertNil(BLELightPacket.parse(corrupted))
        }
    }

    func testBLEPacketSteadyModeAndBrightnessScaling() {
        let sodium = ElementCatalog.element(symbol: "Na")!
        let steadyDim = sodium.makeBLEPacketStruct(brightnessScale: 0.5, pulseDurationOverrideMs: 0)
        XCTAssertEqual(steadyDim.pulseDurationMs, 0)
        XCTAssertLessThanOrEqual(steadyDim.value, 130)
        XCTAssertGreaterThanOrEqual(steadyDim.value, 125)
    }

    // MARK: - AVBeatClock & Photosensitivity Safe Cap

    func testBeatClockSafeCapEnforcesMax2Point5Hz() {
        // Hydrogen raw pulseDurationMs = 40 ms -> 80 ms raw period (12.5 Hz)
        let safeState = AVBeatClock.state(
            elapsedSeconds: 0.1,
            pulseDurationMs: 40,
            dutyCycle: 0.45,
            mode: .spectralStrobe,
            safeRateCapEnabled: true
        )
        XCTAssertLessThanOrEqual(safeState.effectiveRateHz, 2.5001)
        XCTAssertGreaterThanOrEqual(safeState.effectivePeriodSeconds, 0.40)

        // Unlocked raw strobe matches 12.5 Hz (0.08 s period)
        let rawState = AVBeatClock.state(
            elapsedSeconds: 0.02,
            pulseDurationMs: 40,
            dutyCycle: 0.45,
            mode: .spectralStrobe,
            safeRateCapEnabled: false
        )
        XCTAssertEqual(rawState.effectivePeriodSeconds, 0.08, accuracy: 1e-6)
        XCTAssertEqual(rawState.effectiveRateHz, 12.5, accuracy: 1e-4)
        XCTAssertTrue(rawState.isFlashOn)
    }

    // MARK: - Polyphonic Additive Audio Render Kernel

    func testSpectralRenderKernelProducesBoundedPolyphonicAudio() {
        let neon = ElementCatalog.element(symbol: "Ne")!
        let kernel = SpectralRenderKernel()
        kernel.configure(
            element: neon,
            masterGain: 0.8,
            harmonicRichness: 0.4,
            dutyCycle: 0.5,
            visualMode: .spectralStrobe,
            safeRateCapEnabled: true
        )

        let frameCount = 4096
        var left = [Float](repeating: 0.0, count: frameCount)
        var right = [Float](repeating: 0.0, count: frameCount)

        // Stopped -> silent
        let silentResult = left.withUnsafeMutableBufferPointer { lBuf in
            right.withUnsafeMutableBufferPointer { rBuf in
                kernel.renderBlock(
                    sampleRate: 48_000,
                    frameCount: frameCount,
                    left: lBuf.baseAddress!,
                    right: rBuf.baseAddress
                )
            }
        }
        XCTAssertEqual(silentResult.rms, 0.0, accuracy: 1e-6)

        // Playing -> bounded non-silent stereo polyphonic output
        kernel.setPlaying(true, resetClock: true)
        let activeResult = left.withUnsafeMutableBufferPointer { lBuf in
            right.withUnsafeMutableBufferPointer { rBuf in
                kernel.renderBlock(
                    sampleRate: 48_000,
                    frameCount: frameCount,
                    left: lBuf.baseAddress!,
                    right: rBuf.baseAddress
                )
            }
        }

        XCTAssertGreaterThan(activeResult.rms, 0.05)
        XCTAssertLessThanOrEqual(activeResult.rms, 1.0)
        for sample in left {
            XCTAssertTrue(sample.isFinite)
            XCTAssertLessThanOrEqual(abs(sample), 1.0)
        }
        for sample in right {
            XCTAssertTrue(sample.isFinite)
            XCTAssertLessThanOrEqual(abs(sample), 1.0)
        }
    }
}
