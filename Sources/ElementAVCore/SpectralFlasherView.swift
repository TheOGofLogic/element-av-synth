import Foundation
import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#endif

// MARK: - High-Frame-Rate DisplayLink Driver (ProMotion 60-120 Hz on iOS)

@MainActor
public final class DisplayLinkDriver: ObservableObject {
    @Published public private(set) var tickTimestamp: Double = 0.0

    #if canImport(UIKit)
    private var displayLink: CADisplayLink?
    #else
    private var fallbackTimer: Timer?
    #endif

    public init() {}

    public func start() {
        #if canImport(UIKit)
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
        #else
        guard fallbackTimer == nil else { return }
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickTimestamp = Date().timeIntervalSinceReferenceDate
            }
        }
        #endif
    }

    public func stop() {
        #if canImport(UIKit)
        displayLink?.invalidate()
        displayLink = nil
        #else
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        #endif
    }

    #if canImport(UIKit)
    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        tickTimestamp = link.targetTimestamp
    }
    #endif
}

// MARK: - Full-Screen Metal-Backed Spectral Flasher View

public struct SpectralFlasherView: View {
    @ObservedObject public var synth: SpectralAudioSynthesizer
    @ObservedObject public var bleManager: BLELightControllerManager
    @Binding public var brightness: Double
    @Binding public var useCompositeColor: Bool
    public let onDismiss: () -> Void

    @StateObject private var displayLink = DisplayLinkDriver()
    @State private var showHUD: Bool = true
    @State private var showStrobeWarningAlert: Bool = false
    @State private var localStartTime: Double = Date().timeIntervalSinceReferenceDate

    public init(
        synth: SpectralAudioSynthesizer,
        bleManager: BLELightControllerManager,
        brightness: Binding<Double>,
        useCompositeColor: Binding<Bool>,
        onDismiss: @escaping () -> Void
    ) {
        self.synth = synth
        self.bleManager = bleManager
        self._brightness = brightness
        self._useCompositeColor = useCompositeColor
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let telemetry = activeBeatState()
        let activeLine = activeSpectralLine(for: telemetry)
        let activeRGB = activeColorRGB(for: activeLine)
        let intensity = min(max(telemetry.envelopeLevel * brightness, 0.0), 1.0)

        ZStack {
            // Metal-backed extended-gamut (Display-P3) full-screen spectral canvas
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let baseColor = Color(
                    .displayP3,
                    red: activeRGB.r * intensity,
                    green: activeRGB.g * intensity,
                    blue: activeRGB.b * intensity,
                    opacity: 1.0
                )
                context.fill(Path(rect), with: .color(baseColor))

                // Concentric discharge-tube plasma glow synced to envelope
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let maxRadius = hypot(size.width, size.height) * (0.35 + 0.35 * intensity)
                let glow = Gradient(colors: [
                    Color(.displayP3, red: min(activeRGB.r * 1.25, 1.0), green: min(activeRGB.g * 1.25, 1.0), blue: min(activeRGB.b * 1.25, 1.0), opacity: 0.45 * intensity),
                    Color.clear
                ])
                context.fill(
                    Path(rect),
                    with: .radialGradient(glow, center: center, startRadius: 8, endRadius: max(maxRadius, 24))
                )
            }
            .drawingGroup(opaque: true, colorMode: .extendedLinear)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showHUD.toggle()
                }
            }

            if showHUD {
                hudOverlay(telemetry: telemetry, activeLine: activeLine)
            }
        }
        .onAppear {
            localStartTime = Date().timeIntervalSinceReferenceDate
            displayLink.start()
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            displayLink.stop()
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        .alert("Photosensitivity Warning", isPresented: $showStrobeWarningAlert) {
            Button("Keep Safe Rate (<= 2.5 Hz)", role: .cancel) {
                synth.safeRateCapEnabled = true
            }
            Button("Unlock Raw Atomic Strobe", role: .destructive) {
                synth.safeRateCapEnabled = false
                if synth.visualMode == .gentlePulse {
                    synth.visualMode = .spectralStrobe
                }
            }
        } message: {
            Text("Unlocking raw atomic-mass strobe speed can produce flashes above 3 Hz (up to 12.5 Hz for Hydrogen), which may trigger seizures in individuals with photosensitive epilepsy. Proceed only if safe for everyone viewing the screen or connected LEDs.")
        }
    }

    private func activeBeatState() -> AVBeatState {
        // Touch displayLink.tickTimestamp so SwiftUI redraws at 60-120 Hz
        _ = displayLink.tickTimestamp
        let snap = synth.liveTelemetry()
        if snap.isPlaying {
            return snap.beat
        }
        // Even if audio is muted/paused, allow visual preview synced to the same deterministic clock
        let elapsed = max(Date().timeIntervalSinceReferenceDate - localStartTime, 0.0)
        return AVBeatClock.state(
            elapsedSeconds: elapsed,
            pulseDurationMs: synth.selectedElement.pulseDurationMs,
            dutyCycle: synth.dutyCycle,
            mode: synth.visualMode,
            safeRateCapEnabled: synth.safeRateCapEnabled
        )
    }

    private func activeSpectralLine(for beat: AVBeatState) -> SpectralLine? {
        let sortedLines = synth.selectedElement.spectralLines
            .sorted { $0.relativeIntensity > $1.relativeIntensity }
        guard !sortedLines.isEmpty else { return nil }
        if synth.visualMode == .lineCycle {
            return sortedLines[beat.cycleIndex % sortedLines.count]
        }
        return sortedLines.first
    }

    private func activeColorRGB(for activeLine: SpectralLine?) -> (r: Double, g: Double, b: Double) {
        if synth.visualMode != .lineCycle && useCompositeColor {
            return synth.selectedElement.compositeRGB
        }
        return activeLine?.srgbComponents ?? (1.0, 1.0, 1.0)
    }

    @ViewBuilder
    private func hudOverlay(telemetry: AVBeatState, activeLine: SpectralLine?) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(synth.selectedElement.symbol) — \(synth.selectedElement.name) (Z=\(synth.selectedElement.id))")
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let line = activeLine {
                        Text(String(format: "%.1f nm • %.1f Hz (%@) • %.2f Hz pulse",
                                    line.wavelengthNm,
                                    line.audioFrequencyHz,
                                    line.musicalNoteName,
                                    telemetry.effectiveRateHz))
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                Button {
                    synth.stop()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                .accessibilityLabel("Stop and close flasher")
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer()

            VStack(spacing: 12) {
                Picker("Visual Mode", selection: $synth.visualMode) {
                    ForEach(StrobeVisualMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    Button {
                        synth.togglePlayback()
                    } label: {
                        Label(synth.isPlaying ? "Mute Audio" : "Play Chord",
                              systemImage: synth.isPlaying ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(synth.isPlaying ? .orange : .green)

                    Button {
                        if synth.safeRateCapEnabled {
                            showStrobeWarningAlert = true
                        } else {
                            synth.safeRateCapEnabled = true
                        }
                    } label: {
                        Label(
                            synth.safeRateCapEnabled ? "Safe <=2.5Hz" : "Raw Strobe",
                            systemImage: synth.safeRateCapEnabled ? "shield.checkered" : "bolt.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(synth.safeRateCapEnabled ? .cyan : .red)
                }

                HStack {
                    Image(systemName: "sun.min")
                    Slider(value: $brightness, in: 0.1...1.0)
                    Image(systemName: "sun.max.fill")
                }
                .foregroundStyle(.white)

                if bleManager.isReadyToSend {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("BLE Synced: \(bleManager.connectedDeviceName ?? "LED Controller")")
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Button("Push Packet") {
                            bleManager.sendElement(
                                synth.selectedElement,
                                brightness: brightness,
                                strobeEnabled: true,
                                safeRateCapEnabled: synth.safeRateCapEnabled,
                                useCompositeColor: useCompositeColor
                            )
                        }
                        .font(.caption.bold())
                        .buttonStyle(.borderedProminent)
                    }
                }

                Text("Tap background to hide/show controls")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .padding()
    }
}
