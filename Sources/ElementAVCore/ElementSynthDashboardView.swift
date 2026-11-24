import Foundation
import SwiftUI

public struct ElementSynthDashboardView: View {
    @StateObject private var synth = SpectralAudioSynthesizer()
    @StateObject private var bleManager = BLELightControllerManager()

    @State private var brightness: Double = 0.90
    @State private var useCompositeColor: Bool = false
    @State private var bleStrobeEnabled: Bool = true
    @State private var showFlasher: Bool = false

    public init() {}

    public var body: some View {
        TabView {
            synthesizerTab
                .tabItem {
                    Label("Synth", systemImage: "waveform.path.ecg")
                }

            bleControllerTab
                .tabItem {
                    Label("BLE Light", systemImage: "antenna.radiowaves.left.and.right")
                }

            spectrumLabTab
                .tabItem {
                    Label("Spectrum", systemImage: "opticaldisc")
                }
        }
        .preferredColorScheme(.dark)
        .onChange(of: synth.selectedElement) { newElement in
            if bleManager.autoSyncOnChange && bleManager.isReadyToSend {
                bleManager.sendElement(
                    newElement,
                    brightness: brightness,
                    strobeEnabled: bleStrobeEnabled,
                    safeRateCapEnabled: synth.safeRateCapEnabled,
                    useCompositeColor: useCompositeColor
                )
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFlasher) {
            SpectralFlasherView(
                synth: synth,
                bleManager: bleManager,
                brightness: $brightness,
                useCompositeColor: $useCompositeColor,
                onDismiss: { showFlasher = false }
            )
        }
        #else
        .sheet(isPresented: $showFlasher) {
            SpectralFlasherView(
                synth: synth,
                bleManager: bleManager,
                brightness: $brightness,
                useCompositeColor: $useCompositeColor,
                onDismiss: { showFlasher = false }
            )
            .frame(minWidth: 520, minHeight: 520)
        }
        #endif
    }

    // MARK: - Tab 1: Synthesizer & Flasher Launch

    private var synthesizerTab: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    elementHeaderCard
                    elementPickerStrip
                    spectralLinesBarCard
                    synthControlsCard
                    actionButtonsRow
                }
                .padding()
            }
            .navigationTitle("Element AV Synth")
        }
    }

    private var elementHeaderCard: some View {
        let element = synth.selectedElement
        let previewColor = useCompositeColor
            ? element.compositeDisplayColor
            : (element.dominantLine?.fullIntensityColor ?? .white)
        let beat = synth.currentBeatState

        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(previewColor.opacity(synth.isPlaying ? (0.35 + 0.65 * beat.envelopeLevel) : 0.85))
                    .frame(width: 74, height: 74)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(previewColor, lineWidth: 2)
                    )
                    .shadow(color: previewColor.opacity(0.6), radius: synth.isPlaying ? 14 : 6)

                VStack(spacing: 2) {
                    Text("\(element.id)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.black.opacity(0.8))
                    Text(element.symbol)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(element.name)
                    .font(.title2.bold())
                Text("\(element.category) • \(String(format: "%.2f u", element.atomicMass))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let dom = element.dominantLine {
                    Text(String(format: "Dominant: %.1f nm (%@) -> %.1f Hz (%@)",
                                dom.wavelengthNm,
                                dom.hexString,
                                dom.audioFrequencyHz,
                                dom.musicalNoteName))
                        .font(.caption.monospaced())
                        .foregroundStyle(.cyan)
                }

                Text("Pulse: \(element.pulseDurationMs) ms raw • \(String(format: "%.2f Hz", AVBeatClock.state(elapsedSeconds: 0, pulseDurationMs: element.pulseDurationMs, dutyCycle: synth.dutyCycle, mode: synth.visualMode, safeRateCapEnabled: synth.safeRateCapEnabled).effectiveRateHz)) active")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var elementPickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ElementCatalog.all) { item in
                    let isSelected = item.id == synth.selectedElement.id
                    let swatch = item.dominantLine?.fullIntensityColor ?? .white

                    Button {
                        synth.selectedElement = item
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(item.id)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(item.symbol)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(swatch)
                                .frame(width: 34, height: 5)
                        }
                        .frame(width: 56, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? swatch.opacity(0.28) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? swatch : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var spectralLinesBarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Emission Spectrum (380 - 750 nm)")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(synth.selectedElement.spectralLines.count) voices")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black)

                    ForEach(synth.selectedElement.spectralLines) { line in
                        let normX = min(max((line.wavelengthNm - 380.0) / (750.0 - 380.0), 0.0), 1.0)
                        let xPos = normX * max(geo.size.width - 6, 1)
                        let barHeight = max(14.0, geo.size.height * line.relativeIntensity)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(line.fullIntensityColor)
                            .frame(width: 5, height: barHeight)
                            .shadow(color: line.fullIntensityColor.opacity(0.85), radius: 5)
                            .offset(x: xPos, y: (geo.size.height - barHeight) * 0.5)
                    }
                }
            }
            .frame(height: 68)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var synthControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Flash / Envelope Mode", selection: $synth.visualMode) {
                ForEach(StrobeVisualMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(synth.visualMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            sliderRow(title: "Master Volume", value: $synth.masterGain, range: 0.0...1.0, format: "%.0f%%", multiplier: 100)
            sliderRow(title: "Harmonic Shimmer", value: $synth.harmonicRichness, range: 0.0...1.0, format: "%.0f%%", multiplier: 100)
            sliderRow(title: "Pulse Duty Cycle", value: $synth.dutyCycle, range: 0.15...0.85, format: "%.0f%%", multiplier: 100)
            sliderRow(title: "Light Brightness", value: $brightness, range: 0.10...1.0, format: "%.0f%%", multiplier: 100)

            Toggle("Photosensitivity Safe Cap (<= 2.5 Hz)", isOn: $synth.safeRateCapEnabled)
                .font(.subheadline)
            Toggle("Blend Composite Discharge Color", isOn: $useCompositeColor)
                .font(.subheadline)

            if let audioError = synth.lastAudioError {
                Text(audioError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            Button {
                synth.togglePlayback()
            } label: {
                Label(synth.isPlaying ? "Stop Synth" : "Play Chord",
                      systemImage: synth.isPlaying ? "stop.fill" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(synth.isPlaying ? .red : .green)

            Button {
                showFlasher = true
            } label: {
                Label("Full-Screen Flash", systemImage: "sun.max.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        multiplier: Double = 1.0
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue * multiplier))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: - Tab 2: CoreBluetooth LED Light Controller

    private var bleControllerTab: some View {
        let previewPacket = synth.selectedElement.makeBLEPacketStruct(
            brightnessScale: brightness,
            pulseDurationOverrideMs: bleStrobeEnabled
                ? UInt16(synth.safeRateCapEnabled ? max(synth.selectedElement.pulseDurationMs, 200) : synth.selectedElement.pulseDurationMs)
                : 0,
            useCompositeColor: useCompositeColor
        )

        return NavigationStack {
            List {
                Section("8-Byte Peripheral Packet Preview (\(synth.selectedElement.symbol))") {
                    Text(previewPacket.hexDescription)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(.cyan)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Header: 0xAA  |  Z: \(previewPacket.atomicNumber)  |  CRC: \(String(format: "0x%02X", previewPacket.checksumByte))")
                        Text("HSV Bytes: H=\(previewPacket.hue), S=\(previewPacket.saturation), V=\(previewPacket.value)")
                        Text("Pulse Duration: \(previewPacket.pulseDurationMs) ms (\(previewPacket.pulseDurationMs == 0 ? "Steady Light" : "Strobe"))")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                    Toggle("Auto-Sync BLE on Element Change", isOn: $bleManager.autoSyncOnChange)
                    Toggle("Enable Hardware Strobe", isOn: $bleStrobeEnabled)

                    Button {
                        bleManager.sendElement(
                            synth.selectedElement,
                            brightness: brightness,
                            strobeEnabled: bleStrobeEnabled,
                            safeRateCapEnabled: synth.safeRateCapEnabled,
                            useCompositeColor: useCompositeColor
                        )
                    } label: {
                        Label("Send 8-Byte Packet Now", systemImage: "paperplane.fill")
                    }
                    .disabled(!bleManager.isReadyToSend)
                }

                Section("BLE Radio & Connection") {
                    HStack {
                        Text("Radio")
                        Spacer()
                        Text(bleManager.bluetoothStateDescription)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(bleManager.connectionState.label)
                            .foregroundStyle(bleManager.isReadyToSend ? .green : .secondary)
                    }
                    if let charUUID = bleManager.activeCharacteristicUUID {
                        Text("Write Char: \(charUUID)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Scan All BLE Devices (Bench Mode)", isOn: $bleManager.scanUnfilteredForBenchTesting)

                    HStack {
                        Button("Start Scan") {
                            bleManager.startScanning()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Stop Scan") {
                            bleManager.stopScanning()
                        }
                        .buttonStyle(.bordered)

                        if bleManager.isReadyToSend {
                            Button("Disconnect", role: .destructive) {
                                bleManager.disconnect()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Discovered LED Controllers (\(bleManager.discoveredDevices.count))") {
                    if bleManager.discoveredDevices.isEmpty {
                        Text("No peripherals found yet. Tap Start Scan with an nRF52 / ESP32 receiver powered on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bleManager.discoveredDevices) { device in
                            Button {
                                bleManager.connect(to: device)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.headline)
                                        Text("\(device.id.uuidString.prefix(18))...")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(device.rssi) dBm")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }
                    }
                }

                if !bleManager.packetLog.isEmpty {
                    Section("Recent TX Log (\(bleManager.packetsSentCount) sent)") {
                        ForEach(bleManager.packetLog) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.elementSymbol)
                                        .font(.caption.bold())
                                    Text(entry.packet.hexDescription)
                                        .font(.caption.monospaced())
                                    Spacer()
                                    Text(entry.writeMode)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("BLE Light Controller")
            .onAppear {
                bleManager.ensureCentralInitialized()
            }
        }
    }

    // MARK: - Tab 3: Emission Spectrum Reference

    private var spectrumLabTab: some View {
        NavigationStack {
            List {
                Section("\(synth.selectedElement.name) (\(synth.selectedElement.symbol)) Emission Lines") {
                    ForEach(synth.selectedElement.spectralLines) { line in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(line.fullIntensityColor)
                                .frame(width: 28, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.2f nm%@",
                                            line.wavelengthNm,
                                            line.label.map { " — \($0)" } ?? ""))
                                    .font(.subheadline.bold())
                                Text(String(format: "%.1f Hz (%@, MIDI %.1f) • %@",
                                            line.audioFrequencyHz,
                                            line.musicalNoteName,
                                            line.midiNoteNumber,
                                            line.hexString))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", line.relativeIntensity * 100.0))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.cyan)
                        }
                    }
                }
            }
            .navigationTitle("Spectrum Lab")
        }
    }
}
