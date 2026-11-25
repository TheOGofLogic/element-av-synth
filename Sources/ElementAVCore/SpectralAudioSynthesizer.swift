import Foundation
import AVFoundation
import Combine
import os

// MARK: - Visual / Pulse Synchronization Modes

public enum StrobeVisualMode: String, CaseIterable, Identifiable, Sendable {
    case gentlePulse = "Gentle Pulse"
    case spectralStrobe = "Spectral Strobe"
    case lineCycle = "Multi-Line Cycle"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .gentlePulse:
            return "Smooth cosine glow capped at <= 2.5 Hz (photosensitivity-safe default)"
        case .spectralStrobe:
            return "Crisp flash synced to element atomic-mass pulse duration"
        case .lineCycle:
            return "Cycles through each individual NIST emission wavelength per beat"
        }
    }
}

// MARK: - Shared Audio-Visual Beat Clock

public struct AVBeatState: Equatable, Sendable {
    public let cyclePhase: Double
    public let envelopeLevel: Double
    public let isFlashOn: Bool
    public let cycleIndex: Int
    public let effectivePeriodSeconds: Double
    public let effectiveRateHz: Double

    public static let idle = AVBeatState(
        cyclePhase: 0.0,
        envelopeLevel: 0.0,
        isFlashOn: false,
        cycleIndex: 0,
        effectivePeriodSeconds: 0.5,
        effectiveRateHz: 2.0
    )
}

/// Deterministic monotonic beat calculator shared between the audio render callback
/// and the CADisplayLink / SwiftUI flasher so audio and light stay sample-locked.
public enum AVBeatClock {
    /// Minimum safe full-cycle period (0.40 s = 2.5 Hz, below the 3-60 Hz photosensitive trigger band).
    public static let safeMinPeriodSeconds: Double = 0.40

    public static func effectivePeriodSeconds(
        pulseDurationMs: Int,
        mode: StrobeVisualMode,
        safeRateCapEnabled: Bool
    ) -> Double {
        let clampedMs = min(max(pulseDurationMs, 30), 400)
        // Full cycle = on-pulse + off-pulse (nominal 50% duty => 2 * pulseDurationMs)
        let rawPeriod = max((Double(clampedMs) * 2.0) / 1000.0, 0.06)
        if safeRateCapEnabled || mode == .gentlePulse {
            return max(rawPeriod, safeMinPeriodSeconds)
        }
        return rawPeriod
    }

    public static func state(
        elapsedSeconds: Double,
        pulseDurationMs: Int,
        dutyCycle: Double,
        mode: StrobeVisualMode,
        safeRateCapEnabled: Bool
    ) -> AVBeatState {
        let period = effectivePeriodSeconds(
            pulseDurationMs: pulseDurationMs,
            mode: mode,
            safeRateCapEnabled: safeRateCapEnabled
        )
        let clampedDuty = min(max(dutyCycle, 0.10), 0.90)
        let safeElapsed = max(elapsedSeconds, 0.0)

        let totalCycles = safeElapsed / period
        let cycleIndex = Int(floor(totalCycles))
        let phase = totalCycles - floor(totalCycles)

        let envelope: Double
        let flashOn: Bool

        switch mode {
        case .gentlePulse:
            // Smooth raised cosine wave (0.15 floor -> 1.0 peak) with zero sharp edges
            let wave = 0.5 - 0.5 * cos(2.0 * Double.pi * phase)
            envelope = 0.15 + 0.85 * wave
            flashOn = wave >= 0.45

        case .spectralStrobe, .lineCycle:
            // Anti-click trapezoid / fast exponential tail synced to duty cycle
            let edge = min(0.06, clampedDuty * 0.25)
            if phase < edge {
                envelope = phase / max(edge, 0.0001)
                flashOn = true
            } else if phase < clampedDuty {
                envelope = 1.0
                flashOn = true
            } else {
                let releaseWidth = max(min(0.12, 1.0 - clampedDuty), 0.0001)
                let releaseProgress = (phase - clampedDuty) / releaseWidth
                envelope = max(0.0, 1.0 - releaseProgress)
                flashOn = false
            }
        }

        return AVBeatState(
            cyclePhase: phase,
            envelopeLevel: min(max(envelope, 0.0), 1.0),
            isFlashOn: flashOn,
            cycleIndex: cycleIndex,
            effectivePeriodSeconds: period,
            effectiveRateHz: 1.0 / period
        )
    }
}

// MARK: - Lock-Protected Real-Time Audio Render Kernel

public struct SpectralVoiceSpec: Equatable, Sendable {
    public let frequencyHz: Float
    public let amplitude: Float
    public let pan: Float // -1.0 (left) ... +1.0 (right)

    public init(frequencyHz: Float, amplitude: Float, pan: Float = 0.0) {
        self.frequencyHz = frequencyHz
        self.amplitude = amplitude
        self.pan = min(max(pan, -1.0), 1.0)
    }
}

/// Real-time audio-safe additive synthesis kernel usable both inside `AVAudioSourceNode`
/// and directly in unit tests without requiring audio hardware.
public final class SpectralRenderKernel: @unchecked Sendable {
    public static let maxVoices: Int = 16

    private struct State {
        var voiceCount: Int = 0
        var frequencies: [Float] = Array(repeating: 440.0, count: maxVoices)
        var amplitudes: [Float] = Array(repeating: 0.0, count: maxVoices)
        var pans: [Float] = Array(repeating: 0.0, count: maxVoices)
        var phases: [Float] = Array(repeating: 0.0, count: maxVoices)
        var normalizationScale: Float = 1.0

        var isPlaying: Bool = false
        var masterGain: Float = 0.72
        var harmonicRichness: Float = 0.35
        var filterCutoffNormalized: Float = 1.0 // 0.0 (~220 Hz) ... 1.0 (~14 kHz wide open)
        var smoothedFilterCutoff: Float = 1.0
        var lpStateL: Float = 0.0
        var lpStateR: Float = 0.0
        var pulseDurationMs: Int = 60
        var dutyCycle: Double = 0.45
        var visualMode: StrobeVisualMode = .gentlePulse
        var safeRateCapEnabled: Bool = true
        var singleLineIndex: Int? = nil

        var elapsedSamples: UInt64 = 0
        var lastRMS: Float = 0.0
        var lastBeat: AVBeatState = .idle
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func configure(
        element: ChemicalElementSynth,
        masterGain: Float,
        harmonicRichness: Float,
        dutyCycle: Double,
        visualMode: StrobeVisualMode,
        safeRateCapEnabled: Bool
    ) {
        let sortedLines = element.spectralLines
            .sorted { $0.relativeIntensity > $1.relativeIntensity }
            .prefix(Self.maxVoices)

        let count = sortedLines.count
        var specs: [SpectralVoiceSpec] = []
        specs.reserveCapacity(count)

        for (index, line) in sortedLines.enumerated() {
            // Subtle stereo spread across emission lines for a lush harmonic chord
            let pan: Float
            if count <= 1 {
                pan = 0.0
            } else {
                let norm = Float(index) / Float(count - 1)
                pan = (norm * 2.0 - 1.0) * 0.45
            }
            specs.append(SpectralVoiceSpec(
                frequencyHz: line.audioFrequencyHz,
                amplitude: Float(line.relativeIntensity),
                pan: pan
            ))
        }

        let voiceSpecs = specs

        lock.withLock { state in
            state.voiceCount = voiceSpecs.count
            var ampSum: Float = 0.0
            for i in 0..<Self.maxVoices {
                if i < voiceSpecs.count {
                    state.frequencies[i] = voiceSpecs[i].frequencyHz
                    state.amplitudes[i] = voiceSpecs[i].amplitude
                    state.pans[i] = voiceSpecs[i].pan
                    ampSum += voiceSpecs[i].amplitude
                } else {
                    state.amplitudes[i] = 0.0
                }
            }
            state.normalizationScale = ampSum > 0.0001 ? (1.0 / ampSum) : 1.0
            state.masterGain = min(max(masterGain, 0.0), 1.0)
            state.harmonicRichness = min(max(harmonicRichness, 0.0), 1.0)
            state.pulseDurationMs = element.pulseDurationMs
            state.dutyCycle = min(max(dutyCycle, 0.10), 0.90)
            state.visualMode = visualMode
            state.safeRateCapEnabled = safeRateCapEnabled
        }
    }

    public func setPlaying(_ playing: Bool, resetClock: Bool = false) {
        lock.withLock { state in
            state.isPlaying = playing
            if resetClock {
                state.elapsedSamples = 0
                for i in 0..<Self.maxVoices {
                    state.phases[i] = 0.0
                }
                state.lpStateL = 0.0
                state.lpStateR = 0.0
                state.lastRMS = 0.0
                state.lastBeat = .idle
            }
        }
    }

    /// Modulates the real-time stereo low-pass filter cutoff (`0.0` = ~220 Hz warm hum, `1.0` = ~14 kHz open).
    public func setFilterCutoff(normalized: Float) {
        let clamped = min(max(normalized, 0.0), 1.0)
        lock.withLock { state in
            state.filterCutoffNormalized = clamped
        }
    }

    /// Maps normalized cutoff (`0...1`) logarithmically to Hz (`220 Hz...14,000 Hz`).
    public static func filterCutoffHz(forNormalized normalized: Float) -> Float {
        let clamped = min(max(normalized, 0.0), 1.0)
        return 220.0 * powf(14_000.0 / 220.0, clamped)
    }

    public func updateParameters(
        masterGain: Float,
        harmonicRichness: Float,
        dutyCycle: Double,
        visualMode: StrobeVisualMode,
        safeRateCapEnabled: Bool
    ) {
        lock.withLock { state in
            state.masterGain = min(max(masterGain, 0.0), 1.0)
            state.harmonicRichness = min(max(harmonicRichness, 0.0), 1.0)
            state.dutyCycle = min(max(dutyCycle, 0.10), 0.90)
            state.visualMode = visualMode
            state.safeRateCapEnabled = safeRateCapEnabled
        }
    }

    public func snapshotTelemetry() -> (rms: Float, beat: AVBeatState, isPlaying: Bool) {
        lock.withLock { state in
            (state.lastRMS, state.lastBeat, state.isPlaying)
        }
    }

    private struct AudioOutputBuffers: @unchecked Sendable {
        let left: UnsafeMutablePointer<Float>
        let right: UnsafeMutablePointer<Float>?
    }

    /// Renders `frameCount` frames into `left` (and optional `right`) buffers.
    /// Safe to invoke from the `AVAudioSourceNode` real-time render block.
    @discardableResult
    public func renderBlock(
        sampleRate: Double,
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>?
    ) -> (rms: Float, beat: AVBeatState) {
        guard frameCount > 0, sampleRate > 0 else {
            return (0.0, .idle)
        }

        let buffers = AudioOutputBuffers(left: left, right: right)

        return lock.withLock { state in
            guard state.isPlaying, state.voiceCount > 0 else {
                for frame in 0..<frameCount {
                    buffers.left[frame] = 0.0
                    if let rightPtr = buffers.right {
                        rightPtr[frame] = 0.0
                    }
                }
                state.lastRMS = 0.0
                return (0.0, state.lastBeat)
            }

            let twoPi: Float = 2.0 * Float.pi
            let invSampleRate = Float(1.0 / sampleRate)
            let richness = state.harmonicRichness
            let secondHarmonicGain: Float = 0.30 * richness
            let thirdHarmonicGain: Float = 0.14 * richness
            let harmonicNorm: Float = 1.0 / (1.0 + secondHarmonicGain + thirdHarmonicGain)
            let baseScale = state.normalizationScale * harmonicNorm * state.masterGain

            var sumSquares: Float = 0.0
            var latestBeat = state.lastBeat

            for frame in 0..<frameCount {
                let elapsedSeconds = Double(state.elapsedSamples) / sampleRate
                let beat = AVBeatClock.state(
                    elapsedSeconds: elapsedSeconds,
                    pulseDurationMs: state.pulseDurationMs,
                    dutyCycle: state.dutyCycle,
                    mode: state.visualMode,
                    safeRateCapEnabled: state.safeRateCapEnabled
                )
                latestBeat = beat

                let env = Float(beat.envelopeLevel)
                var sampleL: Float = 0.0
                var sampleR: Float = 0.0

                let activeLineIdx: Int? = (state.visualMode == .lineCycle && state.voiceCount > 0)
                    ? (beat.cycleIndex % state.voiceCount)
                    : nil

                for i in 0..<state.voiceCount {
                    let freq = state.frequencies[i]
                    let phase = state.phases[i]

                    // Always advance phase smoothly to avoid phase discontinuities when cycling lines
                    var nextPhase = phase + twoPi * freq * invSampleRate
                    if nextPhase >= twoPi {
                        nextPhase.formTruncatingRemainder(dividingBy: twoPi)
                    }
                    state.phases[i] = nextPhase

                    let voiceWeight: Float
                    if let active = activeLineIdx {
                        // In lineCycle mode, emphasize the currently flashing spectral line while keeping a subtle pad bed
                        voiceWeight = (i == active) ? 1.0 : 0.14
                    } else {
                        voiceWeight = 1.0
                    }

                    let amp = state.amplitudes[i] * voiceWeight
                    guard amp > 0.0001 else { continue }

                    var osc = sinf(phase)
                    if richness > 0.001 {
                        osc += secondHarmonicGain * sinf(phase * 2.0)
                        osc += thirdHarmonicGain * sinf(phase * 3.0)
                    }

                    let voiceOut = osc * amp
                    let pan = state.pans[i]
                    let gainL = 0.5 * (1.0 - pan) + 0.5 * (1.0 - abs(pan))
                    let gainR = 0.5 * (1.0 + pan) + 0.5 * (1.0 - abs(pan))

                    sampleL += voiceOut * gainL
                    sampleR += voiceOut * gainR
                }

                // Apply beat amplitude envelope & gentle soft-clipping limiter
                let rawL = tanhf(sampleL * baseScale * env * 1.35)
                let rawR = tanhf(sampleR * baseScale * env * 1.35)

                // Smooth one-pole low-pass filter modulated by interactive touch gestures
                state.smoothedFilterCutoff += (state.filterCutoffNormalized - state.smoothedFilterCutoff) * 0.004
                let cutoffHz = Self.filterCutoffHz(forNormalized: state.smoothedFilterCutoff)
                let alpha = min(max(1.0 - expf(-twoPi * cutoffHz * invSampleRate), 0.001), 1.0)
                state.lpStateL += alpha * (rawL - state.lpStateL)
                state.lpStateR += alpha * (rawR - state.lpStateR)

                let outL = state.lpStateL
                let outR = state.lpStateR

                buffers.left[frame] = outL
                if let rightPtr = buffers.right {
                    rightPtr[frame] = outR
                }
                sumSquares += 0.5 * (outL * outL + outR * outR)
                state.elapsedSamples &+= 1
            }

            let rms = sqrtf(sumSquares / Float(frameCount))
            state.lastRMS = rms
            state.lastBeat = latestBeat
            return (rms, latestBeat)
        }
    }
}

// MARK: - AVAudioEngine Polyphonic Synthesizer Controller

@MainActor
public final class SpectralAudioSynthesizer: ObservableObject {
    @Published public var selectedElement: ChemicalElementSynth {
        didSet { syncKernelConfiguration() }
    }
    @Published public var isPlaying: Bool = false
    @Published public var masterGain: Double = 0.72 {
        didSet { syncKernelParameters() }
    }
    @Published public var harmonicRichness: Double = 0.38 {
        didSet { syncKernelParameters() }
    }
    @Published public var dutyCycle: Double = 0.45 {
        didSet { syncKernelParameters() }
    }
    @Published public var visualMode: StrobeVisualMode = .gentlePulse {
        didSet { syncKernelParameters() }
    }
    @Published public var safeRateCapEnabled: Bool = true {
        didSet { syncKernelParameters() }
    }
    @Published public var filterCutoffNormalized: Double = 1.0 {
        didSet { kernel.setFilterCutoff(normalized: Float(filterCutoffNormalized)) }
    }
    @Published public private(set) var currentBeatState: AVBeatState = .idle
    @Published public private(set) var currentRMS: Float = 0.0
    @Published public private(set) var lastAudioError: String?

    public let kernel = SpectralRenderKernel()

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var telemetryTimer: Timer?

    public init(initialElement: ChemicalElementSynth = ElementCatalog.element(symbol: "Ne") ?? ElementCatalog.all[0]) {
        self.selectedElement = initialElement
        syncKernelConfiguration()
    }

    /// Reads the freshest sample-locked beat & RMS telemetry directly from the audio kernel.
    public func liveTelemetry() -> (rms: Float, beat: AVBeatState, isPlaying: Bool) {
        kernel.snapshotTelemetry()
    }

    public func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    public func start() {
        guard !isPlaying else { return }
        lastAudioError = nil
        syncKernelConfiguration()

        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            #endif

            if audioEngine == nil {
                setupAudioGraph()
            }

            guard let engine = audioEngine else { return }
            if !engine.isRunning {
                try engine.start()
            }

            kernel.setPlaying(true, resetClock: true)
            isPlaying = true
            startTelemetryTimer()
        } catch {
            lastAudioError = "Audio start failed: \(error.localizedDescription)"
            isPlaying = false
            kernel.setPlaying(false)
        }
    }

    public func stop() {
        kernel.setPlaying(false, resetClock: false)
        isPlaying = false
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        audioEngine?.pause()
        currentRMS = 0.0
        currentBeatState = .idle
    }

    private func setupAudioGraph() {
        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000.0
        let renderFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) ?? outputFormat

        let renderKernel = self.kernel
        let node = AVAudioSourceNode(format: renderFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let firstBuf = ablPointer.first,
                  let leftPtr = firstBuf.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let rightPtr: UnsafeMutablePointer<Float>? = ablPointer.count > 1
                ? ablPointer[1].mData?.assumingMemoryBound(to: Float.self)
                : nil

            renderKernel.renderBlock(
                sampleRate: sampleRate,
                frameCount: Int(frameCount),
                left: leftPtr,
                right: rightPtr
            )
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: mainMixer, format: renderFormat)
        engine.prepare()

        self.audioEngine = engine
        self.sourceNode = node
    }

    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snap = self.kernel.snapshotTelemetry()
                self.currentRMS = snap.rms
                self.currentBeatState = snap.beat
            }
        }
    }

    private func syncKernelConfiguration() {
        kernel.configure(
            element: selectedElement,
            masterGain: Float(masterGain),
            harmonicRichness: Float(harmonicRichness),
            dutyCycle: dutyCycle,
            visualMode: visualMode,
            safeRateCapEnabled: safeRateCapEnabled
        )
    }

    private func syncKernelParameters() {
        kernel.updateParameters(
            masterGain: Float(masterGain),
            harmonicRichness: Float(harmonicRichness),
            dutyCycle: dutyCycle,
            visualMode: visualMode,
            safeRateCapEnabled: safeRateCapEnabled
        )
    }
}
