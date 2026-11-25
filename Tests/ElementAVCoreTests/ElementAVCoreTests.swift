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

    // MARK: - Metal Plasma Uniform Buffer Layout & Packing

    func testMetalPlasmaUniformMemoryLayoutMatchesMSL16ByteAlignment() {
        XCTAssertEqual(MemoryLayout<SpectralLineUniformBridge>.stride, 32)
        XCTAssertEqual(MemoryLayout<SpectralLineUniformBridge>.alignment, 16)
        XCTAssertEqual(MemoryLayout<PlasmaUniformsBridge>.stride, 320)
        XCTAssertEqual(MemoryLayout<PlasmaUniformsBridge>.alignment, 16)
    }

    func testTouchPlasmaUniformAndLowPassFilterModulation() {
        let touch = TouchPlasmaState(uv: SIMD2<Float>(0.25, 0.80), strength: 0.9, pinchScale: 1.6)
        XCTAssertEqual(touch.suggestedFilterCutoffNormalized, 0.20, accuracy: 1e-5)

        let neon = ElementCatalog.element(symbol: "Ne")!
        let uniforms = PlasmaUniformsBuilder.makeUniforms(
            element: neon,
            beatState: .idle,
            visualMode: .gentlePulse,
            elapsedTime: 2.0,
            intensityScale: 1.0,
            viewportSize: CGSize(width: 390, height: 844),
            touch: touch
        )
        XCTAssertEqual(uniforms.touchControl.x, 0.25, accuracy: 1e-5)
        XCTAssertEqual(uniforms.touchControl.y, 0.80, accuracy: 1e-5)
        XCTAssertEqual(uniforms.touchControl.z, 0.90, accuracy: 1e-5)
        XCTAssertEqual(uniforms.touchControl.w, 1.60, accuracy: 1e-5)

        // Verify one-pole low-pass filter measurably attenuates a high-pitch violet emission line (380 nm -> 2093 Hz)
        let violetElement = ChemicalElementSynth(
            id: 999,
            symbol: "Vx",
            name: "Violet Test",
            atomicMass: 10.0,
            spectralLines: [SpectralLine(wavelengthNm: 380.0, relativeIntensity: 1.0)]
        )
        let frameCount = 4096
        var leftOpen = [Float](repeating: 0.0, count: frameCount)
        var leftFiltered = [Float](repeating: 0.0, count: frameCount)

        let openKernel = SpectralRenderKernel()
        openKernel.configure(
            element: violetElement,
            masterGain: 0.8,
            harmonicRichness: 0.0,
            dutyCycle: 0.9,
            visualMode: .spectralStrobe,
            safeRateCapEnabled: true
        )
        openKernel.setFilterCutoff(normalized: 1.0)
        openKernel.setPlaying(true, resetClock: true)
        let openResult = leftOpen.withUnsafeMutableBufferPointer { buf in
            openKernel.renderBlock(sampleRate: 48_000, frameCount: frameCount, left: buf.baseAddress!, right: nil)
        }

        let filteredKernel = SpectralRenderKernel()
        filteredKernel.configure(
            element: violetElement,
            masterGain: 0.8,
            harmonicRichness: 0.0,
            dutyCycle: 0.9,
            visualMode: .spectralStrobe,
            safeRateCapEnabled: true
        )
        filteredKernel.setFilterCutoff(normalized: 0.0)
        filteredKernel.setPlaying(true, resetClock: true)
        // Render 2 blocks so the smooth cutoff ramp settles near 220 Hz
        _ = leftFiltered.withUnsafeMutableBufferPointer { buf in
            filteredKernel.renderBlock(sampleRate: 48_000, frameCount: frameCount, left: buf.baseAddress!, right: nil)
        }
        let filteredResult = leftFiltered.withUnsafeMutableBufferPointer { buf in
            filteredKernel.renderBlock(sampleRate: 48_000, frameCount: frameCount, left: buf.baseAddress!, right: nil)
        }

        XCTAssertGreaterThan(openResult.rms, filteredResult.rms * 2.0, "220 Hz LPF should strongly attenuate 2093 Hz violet tone")
    }

    func testMetalPlasmaUniformBuilderSortsAndClampsTop8Lines() {
        let neon = ElementCatalog.element(symbol: "Ne")!
        let beat = AVBeatState(
            cyclePhase: 0.25,
            envelopeLevel: 0.85,
            isFlashOn: true,
            cycleIndex: 3,
            effectivePeriodSeconds: 0.4,
            effectiveRateHz: 2.5
        )

        let blendUniforms = PlasmaUniformsBuilder.makeUniforms(
            element: neon,
            beatState: beat,
            visualMode: .gentlePulse,
            elapsedTime: 1.5,
            intensityScale: 0.9,
            viewportSize: CGSize(width: 1179, height: 2556)
        )

        XCTAssertEqual(blendUniforms.meta.x, UInt32(min(neon.spectralLines.count, 8)))
        XCTAssertEqual(blendUniforms.meta.y, PlasmaUniformsBridge.allLinesMask)
        XCTAssertEqual(blendUniforms.timing.x, 1.5, accuracy: 1e-5)
        XCTAssertEqual(blendUniforms.timing.y, 0.25, accuracy: 1e-5)
        XCTAssertEqual(blendUniforms.timing.z, 0.85, accuracy: 1e-5)
        XCTAssertEqual(blendUniforms.timing.w, 0.9, accuracy: 1e-5)
        XCTAssertEqual(blendUniforms.aspectAndViewport.x, Float(1179.0 / 2556.0), accuracy: 1e-4)

        // Strongest Neon line (640.22 nm, intensity 1.0) must be packed at slot 0
        let slot0 = blendUniforms.line(at: 0)
        XCTAssertNotNil(slot0)
        XCTAssertEqual(slot0!.colorAndIntensity.w, 1.0, accuracy: 1e-5)
        XCTAssertEqual(slot0!.params.y, 640.22, accuracy: 0.05)

        // Multi-line cycle mode must set activeLineIndex = cycleIndex % count
        let cycleUniforms = PlasmaUniformsBuilder.makeUniforms(
            element: neon,
            beatState: beat,
            visualMode: .lineCycle,
            elapsedTime: 1.5,
            intensityScale: 1.0,
            viewportSize: CGSize(width: 1179, height: 2556)
        )
        XCTAssertEqual(cycleUniforms.meta.y, UInt32(3 % neon.spectralLines.count))
    }

    // MARK: - Full 118-Element Periodic Table Catalog Integrity

    func testFull118ElementCatalogCompletenessAndValidity() throws {
        let all = ElementCatalog.all
        XCTAssertEqual(all.count, 118, "Catalog must contain all 118 IUPAC elements")

        let atomicNumbers = all.map(\.id)
        XCTAssertEqual(atomicNumbers, Array(1...118), "Atomic numbers must be contiguous 1...118")

        let uniqueSymbols = Set(all.map(\.symbol))
        XCTAssertEqual(uniqueSymbols.count, 118, "All 118 element symbols must be unique")

        XCTAssertEqual(ElementCatalog.element(symbol: "Au")?.id, 79)
        XCTAssertEqual(ElementCatalog.element(symbol: "Og")?.id, 118)
        XCTAssertEqual(ElementCatalog.filtered(query: "79").first?.symbol, "Au")
        XCTAssertEqual(ElementCatalog.filtered(query: "", category: "Noble Gas").count, 7)

        for element in all {
            XCTAssertGreaterThanOrEqual(element.spectralLines.count, 3, "\(element.symbol) must have >= 3 lines")
            XCTAssertGreaterThanOrEqual(element.pulseDurationMs, 30)
            XCTAssertLessThanOrEqual(element.pulseDurationMs, 400)

            let dom = try XCTUnwrap(element.dominantLine)
            let rgb = dom.srgbComponents
            XCTAssertGreaterThan(max(rgb.r, max(rgb.g, rgb.b)), 0.1, "\(element.symbol) dominant color must be visible")

            for line in element.spectralLines {
                XCTAssertGreaterThanOrEqual(line.wavelengthNm, 380.0, "\(element.symbol) wavelength below 380 nm")
                XCTAssertLessThanOrEqual(line.wavelengthNm, 780.0, "\(element.symbol) wavelength above 780 nm")
                XCTAssertGreaterThanOrEqual(line.audioFrequencyHz, 109.9)
                XCTAssertLessThanOrEqual(line.audioFrequencyHz, 2093.1)
            }

            let uniforms = PlasmaUniformsBuilder.makeUniforms(
                element: element,
                beatState: .idle,
                visualMode: .gentlePulse,
                elapsedTime: 0.5,
                intensityScale: 1.0,
                viewportSize: CGSize(width: 390, height: 844)
            )
            XCTAssertGreaterThanOrEqual(uniforms.meta.x, 3)
            XCTAssertLessThanOrEqual(uniforms.meta.x, 8)
        }
    }
}
