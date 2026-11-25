import Foundation
import SwiftUI
import simd

#if canImport(MetalKit)
import MetalKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Interactive Touch-to-Plasma State

public struct TouchPlasmaState: Equatable, Sendable {
    public var uv: SIMD2<Float>        // Normalized touch coordinates (0...1, 0...1)
    public var strength: Float         // 0.0 (idle) ... 1.0 (active drag)
    public var pinchScale: Float       // 0.5 ... 2.5 (pinch zoom / vortex expansion)

    public static let idle = TouchPlasmaState(
        uv: SIMD2<Float>(0.5, 0.5),
        strength: 0.0,
        pinchScale: 1.0
    )

    public init(uv: SIMD2<Float> = SIMD2<Float>(0.5, 0.5), strength: Float = 0.0, pinchScale: Float = 1.0) {
        self.uv = SIMD2<Float>(
            min(max(uv.x, 0.0), 1.0),
            min(max(uv.y, 0.0), 1.0)
        )
        self.strength = min(max(strength, 0.0), 1.0)
        self.pinchScale = min(max(pinchScale, 0.5), 2.5)
    }

    /// Maps vertical touch position into normalized audio low-pass filter cutoff (top = 1.0 open, bottom = 0.0 warm).
    public var suggestedFilterCutoffNormalized: Float {
        min(max(1.0 - uv.y, 0.05), 1.0)
    }
}

// MARK: - 16-Byte-Aligned Metal Uniform Bridge Structs

/// Exact 32-byte layout matching `SpectralLineUniform` in `SpectralPlasma.metal`.
public struct SpectralLineUniformBridge: Equatable, Sendable {
    public var colorAndIntensity: SIMD4<Float>
    public var params: SIMD4<Float>

    public init(
        r: Float = 0,
        g: Float = 0,
        b: Float = 0,
        intensity: Float = 0,
        frequencyHz: Float = 0,
        wavelengthNm: Float = 0
    ) {
        self.colorAndIntensity = SIMD4<Float>(r, g, b, intensity)
        self.params = SIMD4<Float>(frequencyHz, wavelengthNm, 0, 0)
    }
}

/// Exact 320-byte layout matching `PlasmaUniforms` in `SpectralPlasma.metal`.
public struct PlasmaUniformsBridge: Sendable {
    public static let maxSpectralLines: Int = 8
    public static let allLinesMask: UInt32 = 0xFFFF_FFFF

    public var timing: SIMD4<Float>            // x: time, y: beatPhase, z: envelopeLevel, w: intensityScale
    public var meta: SIMD4<UInt32>             // x: lineCount, y: activeLineIndex, z: modeRaw, w: reserved
    public var aspectAndViewport: SIMD4<Float> // x: aspectRatio, y: width, z: height, w: reserved
    public var touchControl: SIMD4<Float>      // x: touchU, y: touchV, z: touchStrength, w: pinchScale
    public var lines: (
        SpectralLineUniformBridge, SpectralLineUniformBridge,
        SpectralLineUniformBridge, SpectralLineUniformBridge,
        SpectralLineUniformBridge, SpectralLineUniformBridge,
        SpectralLineUniformBridge, SpectralLineUniformBridge
    )

    public init(
        time: Float = 0,
        beatPhase: Float = 0,
        envelopeLevel: Float = 1.0,
        intensityScale: Float = 1.0,
        lineCount: UInt32 = 0,
        activeLineIndex: UInt32 = PlasmaUniformsBridge.allLinesMask,
        visualModeIndex: UInt32 = 0,
        viewportSize: CGSize = CGSize(width: 1, height: 1),
        touch: TouchPlasmaState = .idle
    ) {
        let w = max(Float(viewportSize.width), 1.0)
        let h = max(Float(viewportSize.height), 1.0)
        self.timing = SIMD4<Float>(time, beatPhase, envelopeLevel, intensityScale)
        self.meta = SIMD4<UInt32>(lineCount, activeLineIndex, visualModeIndex, 0)
        self.aspectAndViewport = SIMD4<Float>(w / h, w, h, 0)
        self.touchControl = SIMD4<Float>(touch.uv.x, touch.uv.y, touch.strength, touch.pinchScale)
        self.lines = (
            .init(), .init(), .init(), .init(),
            .init(), .init(), .init(), .init()
        )
    }

    public mutating func setLine(index: Int, entry: SpectralLineUniformBridge) {
        switch index {
        case 0: lines.0 = entry
        case 1: lines.1 = entry
        case 2: lines.2 = entry
        case 3: lines.3 = entry
        case 4: lines.4 = entry
        case 5: lines.5 = entry
        case 6: lines.6 = entry
        case 7: lines.7 = entry
        default: break
        }
    }

    public func line(at index: Int) -> SpectralLineUniformBridge? {
        switch index {
        case 0: return lines.0
        case 1: return lines.1
        case 2: return lines.2
        case 3: return lines.3
        case 4: return lines.4
        case 5: return lines.5
        case 6: return lines.6
        case 7: return lines.7
        default: return nil
        }
    }
}

// MARK: - Pure Uniform Builder (Testable on macOS & iOS without GPU)

public enum PlasmaUniformsBuilder {
    public static func makeUniforms(
        element: ChemicalElementSynth,
        beatState: AVBeatState,
        visualMode: StrobeVisualMode,
        elapsedTime: Float,
        intensityScale: Float,
        viewportSize: CGSize,
        touch: TouchPlasmaState = .idle
    ) -> PlasmaUniformsBridge {
        let sortedLines = element.spectralLines
            .sorted { $0.relativeIntensity > $1.relativeIntensity }
        let topLines = Array(sortedLines.prefix(PlasmaUniformsBridge.maxSpectralLines))

        let activeLineIndex: UInt32
        if visualMode == .lineCycle, !topLines.isEmpty {
            activeLineIndex = UInt32(beatState.cycleIndex % topLines.count)
        } else {
            activeLineIndex = PlasmaUniformsBridge.allLinesMask
        }

        let modeIndex: UInt32
        switch visualMode {
        case .gentlePulse: modeIndex = 0
        case .spectralStrobe: modeIndex = 1
        case .lineCycle: modeIndex = 2
        }

        var bridge = PlasmaUniformsBridge(
            time: elapsedTime,
            beatPhase: Float(beatState.cyclePhase),
            envelopeLevel: Float(beatState.envelopeLevel),
            intensityScale: max(intensityScale, 0.0),
            lineCount: UInt32(topLines.count),
            activeLineIndex: activeLineIndex,
            visualModeIndex: modeIndex,
            viewportSize: viewportSize,
            touch: touch
        )

        for (index, line) in topLines.enumerated() {
            let (r, g, b) = SpectralLine.nmToRGB(line.wavelengthNm)
            bridge.setLine(
                index: index,
                entry: SpectralLineUniformBridge(
                    r: Float(r),
                    g: Float(g),
                    b: Float(b),
                    intensity: Float(line.relativeIntensity),
                    frequencyHz: line.audioFrequencyHz,
                    wavelengthNm: Float(line.wavelengthNm)
                )
            )
        }

        return bridge
    }
}

// MARK: - SwiftUI Metal Plasma View (iOS MTKView Bridge)

#if canImport(UIKit) && canImport(MetalKit)
public struct MetalPlasmaView: UIViewRepresentable {
    @ObservedObject public var synth: SpectralAudioSynthesizer
    public let intensityScale: Float
    public let touchState: TouchPlasmaState

    public init(
        synth: SpectralAudioSynthesizer,
        intensityScale: Float = 1.0,
        touchState: TouchPlasmaState = .idle
    ) {
        self.synth = synth
        self.intensityScale = intensityScale
        self.touchState = touchState
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.backgroundColor = .black
        mtkView.isOpaque = true

        guard let device = MTLCreateSystemDefaultDevice() else {
            return mtkView
        }

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        mtkView.preferredFramesPerSecond = 120
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.delegate = context.coordinator

        context.coordinator.setupPipeline(device: device, mtkView: mtkView)
        context.coordinator.update(synth: synth, intensityScale: intensityScale, touchState: touchState)
        return mtkView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(synth: synth, intensityScale: intensityScale, touchState: touchState)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(synth: synth, intensityScale: intensityScale, touchState: touchState)
    }

    @MainActor
    public final class Coordinator: NSObject, MTKViewDelegate {
        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?
        private var synth: SpectralAudioSynthesizer
        private var intensityScale: Float
        private var targetTouch: TouchPlasmaState
        private var smoothedTouch: TouchPlasmaState
        private let startTime: CFTimeInterval = CACurrentMediaTime()

        init(synth: SpectralAudioSynthesizer, intensityScale: Float, touchState: TouchPlasmaState) {
            self.synth = synth
            self.intensityScale = intensityScale
            self.targetTouch = touchState
            self.smoothedTouch = touchState
            super.init()
        }

        func update(synth: SpectralAudioSynthesizer, intensityScale: Float, touchState: TouchPlasmaState) {
            self.synth = synth
            self.intensityScale = intensityScale
            self.targetTouch = touchState
        }

        func setupPipeline(device: MTLDevice, mtkView: MTKView) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()

            // Prefer precompiled default.metallib from SpectralPlasma.metal, with runtime fallback for Previews
            let library: MTLLibrary? = device.makeDefaultLibrary()
                ?? (try? device.makeLibrary(source: Self.fallbackMSLSource, options: nil))

            guard let library,
                  let vertexFunc = library.makeFunction(name: "plasmaVertexShader"),
                  let fragmentFunc = library.makeFunction(name: "plasmaFragmentShader") else {
                return
            }

            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.vertexFunction = vertexFunc
            pipelineDesc.fragmentFunction = fragmentFunc
            pipelineDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

            self.pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDesc)
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let pipelineState,
                  let drawable = view.currentDrawable,
                  let renderPassDesc = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
                return
            }

            // Smooth 120 Hz touch vortex interpolation so filaments gracefully retract on release
            let posLerp: Float = 0.28
            let strengthLerp: Float = targetTouch.strength > smoothedTouch.strength ? 0.35 : 0.08
            smoothedTouch = TouchPlasmaState(
                uv: SIMD2<Float>(
                    smoothedTouch.uv.x + (targetTouch.uv.x - smoothedTouch.uv.x) * posLerp,
                    smoothedTouch.uv.y + (targetTouch.uv.y - smoothedTouch.uv.y) * posLerp
                ),
                strength: smoothedTouch.strength + (targetTouch.strength - smoothedTouch.strength) * strengthLerp,
                pinchScale: smoothedTouch.pinchScale + (targetTouch.pinchScale - smoothedTouch.pinchScale) * 0.22
            )

            let elapsed = CACurrentMediaTime() - startTime
            let snap = synth.liveTelemetry()
            let beat: AVBeatState
            if snap.isPlaying {
                beat = snap.beat
            } else {
                beat = AVBeatClock.state(
                    elapsedSeconds: max(elapsed, 0.0),
                    pulseDurationMs: synth.selectedElement.pulseDurationMs,
                    dutyCycle: synth.dutyCycle,
                    mode: synth.visualMode,
                    safeRateCapEnabled: synth.safeRateCapEnabled
                )
            }

            var uniforms = PlasmaUniformsBuilder.makeUniforms(
                element: synth.selectedElement,
                beatState: beat,
                visualMode: synth.visualMode,
                elapsedTime: Float(elapsed),
                intensityScale: intensityScale,
                viewportSize: view.drawableSize,
                touch: smoothedTouch
            )

            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PlasmaUniformsBridge>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        private static let fallbackMSLSource: String = """
        #include <metal_stdlib>
        using namespace metal;
        struct SpectralLineUniform { float4 colorAndIntensity; float4 params; };
        struct PlasmaUniforms { float4 timing; uint4 meta; float4 aspectAndViewport; float4 touchControl; SpectralLineUniform lines[8]; };
        struct VertexOut { float4 position [[position]]; float2 uv; };
        vertex VertexOut plasmaVertexShader(uint vertexID [[vertex_id]]) {
            VertexOut out;
            float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
            out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
            out.uv = float2(uv.x, 1.0 - uv.y);
            return out;
        }
        static inline float hash21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123); }
        static inline float valueNoise(float2 p) {
            float2 i = floor(p); float2 f = fract(p); float2 u = f * f * (3.0 - 2.0 * f);
            return mix(mix(hash21(i), hash21(i + float2(1.0, 0.0)), u.x),
                       mix(hash21(i + float2(0.0, 1.0)), hash21(i + float2(1.0, 1.0)), u.x), u.y);
        }
        fragment float4 plasmaFragmentShader(VertexOut in [[stage_in]], constant PlasmaUniforms &u [[buffer(0)]]) {
            float2 uv = in.uv * 2.0 - 1.0;
            float aspect = max(u.aspectAndViewport.x, 0.1);
            float2 c = (aspect >= 1.0) ? float2(uv.x * aspect, uv.y) : float2(uv.x, uv.y / aspect);
            float2 tUV = u.touchControl.xy * 2.0 - 1.0;
            float2 tc = (aspect >= 1.0) ? float2(tUV.x * aspect, tUV.y) : float2(tUV.x, tUV.y / aspect);
            float tStr = clamp(u.touchControl.z, 0.0, 1.0);
            float pScale = clamp(u.touchControl.w, 0.5, 2.5);
            float2 toT = c - tc; float tDist = length(toT);
            float2 w = c;
            if (tStr > 0.001) {
                float sw = tStr * 2.4 * pScale * exp(-tDist * 2.5);
                w = tc + float2(toT.x * cos(sw) - toT.y * sin(sw), toT.x * sin(sw) + toT.y * cos(sw));
            }
            float dist = length(w) / pScale; float angle = atan2(w.y, w.x);
            float n = valueNoise(float2(dist * 3.5 - u.timing.x * 0.8, angle * 2.0 + u.timing.x * 0.3));
            float env = clamp(u.timing.z, 0.0, 1.0);
            float pulse = 1.0 + 0.18 * sin(u.timing.y * 2.0 * M_PI_F) + 0.22 * env;
            float core = exp(-dist * (2.9 / pulse)) * (0.75 + 0.45 * n);
            float corona = exp(-dist * 1.3) * 0.32;
            float tendril = exp(-tDist * (3.8 / pScale)) * tStr * 0.8;
            uint count = min(u.meta.x, 8u);
            float3 col = float3(0.0);
            for (uint i = 0; i < count; i++) {
                float focus = (u.meta.y == 0xFFFFFFFFu || u.meta.y == i) ? 1.0 : 0.14;
                float rip = sin(dist * 16.0 - u.timing.x * (u.lines[i].params.x * 0.0055) + float(i));
                col += u.lines[i].colorAndIntensity.xyz * (u.lines[i].colorAndIntensity.w * focus * (core + corona * (0.5 + 0.5 * rip) + tendril));
            }
            col *= (0.18 + 0.82 * env) * max(u.timing.w, 0.0);
            col = 1.0 - exp(-col * 1.45);
            return float4(clamp(col, 0.0, 1.0), 1.0);
        }
        """
    }
}
#endif
