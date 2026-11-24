import Foundation
import CoreBluetooth
import Combine

// MARK: - GATT UUID Constants

public enum ElementBLEUUIDs {
    /// Primary ElementAV Light Controller GATT Service UUID
    public static let elementLightService = CBUUID(string: "E1E00001-5A3C-4F92-8B1A-0000A1B2C3D4")
    /// 8-Byte Spectral Light Packet Characteristic UUID (Write / WriteWithoutResponse)
    public static let lightPacketCharacteristic = CBUUID(string: "E1E00002-5A3C-4F92-8B1A-0000A1B2C3D4")

    /// Nordic UART Service (NUS) fallback for nRF52 / ESP32 prototyping boards
    public static let nordicUARTService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    public static let nordicUARTRXCharacteristic = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

    public static let supportedServices: [CBUUID] = [
        elementLightService,
        nordicUARTService
    ]

    public static let supportedWriteCharacteristics: [CBUUID] = [
        lightPacketCharacteristic,
        nordicUARTRXCharacteristic
    ]
}

// MARK: - BLE Telemetry & Peripheral Models

public struct DiscoveredBLEDevice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let advertisedServiceUUIDs: [String]
    public let lastSeen: Date
}

public struct BLEPacketLogEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let elementSymbol: String
    public let packet: BLELightPacket
    public let writeMode: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        elementSymbol: String,
        packet: BLELightPacket,
        writeMode: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.elementSymbol = elementSymbol
        self.packet = packet
        self.writeMode = writeMode
    }
}

public enum BLEConnectionState: Equatable, Sendable {
    case idle
    case scanning
    case connecting(String)
    case discoveringServices(String)
    case ready(String)
    case failed(String)

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .scanning: return "Scanning..."
        case .connecting(let name): return "Connecting to \(name)..."
        case .discoveringServices(let name): return "Discovering GATT on \(name)..."
        case .ready(let name): return "Connected: \(name)"
        case .failed(let reason): return "Error: \(reason)"
        }
    }
}

// MARK: - CoreBluetooth Central Manager

@MainActor
public final class BLELightControllerManager: NSObject, ObservableObject {
    @Published public private(set) var bluetoothState: CBManagerState = .unknown
    @Published public private(set) var connectionState: BLEConnectionState = .idle
    @Published public private(set) var discoveredDevices: [DiscoveredBLEDevice] = []
    @Published public private(set) var connectedDeviceName: String?
    @Published public private(set) var activeCharacteristicUUID: String?
    @Published public private(set) var lastSentPacket: BLELightPacket?
    @Published public private(set) var packetsSentCount: Int = 0
    @Published public private(set) var packetLog: [BLEPacketLogEntry] = []
    @Published public var autoSyncOnChange: Bool = true
    @Published public var scanUnfilteredForBenchTesting: Bool = false

    private var centralManager: CBCentralManager?
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    public var isReadyToSend: Bool {
        connectedPeripheral?.state == .connected && writeCharacteristic != nil
    }

    public var bluetoothStateDescription: String {
        switch bluetoothState {
        case .poweredOn: return "Bluetooth Powered On"
        case .poweredOff: return "Bluetooth Powered Off"
        case .unauthorized: return "Bluetooth Permission Denied"
        case .unsupported: return "BLE Unsupported on Device"
        case .resetting: return "Bluetooth Resetting..."
        case .unknown: return "Bluetooth Initializing..."
        @unknown default: return "Bluetooth Unknown State"
        }
    }

    public override init() {
        super.init()
    }

    /// Lazily initializes `CBCentralManager` so Bluetooth permission prompts only appear
    /// when the user opens the BLE tab or initiates scanning.
    public func ensureCentralInitialized() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public func startScanning() {
        ensureCentralInitialized()
        guard let central = centralManager else { return }
        guard central.state == .poweredOn else {
            connectionState = .failed(bluetoothStateDescription)
            return
        }

        discoveredDevices.removeAll()
        peripheralsByID.removeAll()
        connectionState = .scanning

        let serviceFilter: [CBUUID]? = scanUnfilteredForBenchTesting ? nil : ElementBLEUUIDs.supportedServices
        central.scanForPeripherals(
            withServices: serviceFilter,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func stopScanning() {
        centralManager?.stopScan()
        if case .scanning = connectionState {
            connectionState = .idle
        }
    }

    public func connect(to device: DiscoveredBLEDevice) {
        guard let central = centralManager,
              let peripheral = peripheralsByID[device.id] else {
            connectionState = .failed("Peripheral no longer cached; rescan.")
            return
        }

        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting(device.name)
        central.connect(peripheral, options: nil)
    }

    public func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        writeCharacteristic = nil
        connectedDeviceName = nil
        activeCharacteristicUUID = nil
        connectionState = .idle
    }

    /// Builds and transmits the 8-byte spectral light packet for the given element.
    @discardableResult
    public func sendElement(
        _ element: ChemicalElementSynth,
        brightness: Double = 1.0,
        strobeEnabled: Bool = true,
        safeRateCapEnabled: Bool = true,
        useCompositeColor: Bool = false
    ) -> BLELightPacket {
        let pulseOverrideMs: UInt16?
        if !strobeEnabled {
            pulseOverrideMs = 0 // 0 ms = continuous solid light on LED receiver
        } else if safeRateCapEnabled {
            // Ensure full cycle >= 400 ms (pulse half-period >= 200 ms) when safe cap is active
            pulseOverrideMs = UInt16(max(element.pulseDurationMs, 200))
        } else {
            pulseOverrideMs = UInt16(element.pulseDurationMs)
        }

        let packet = element.makeBLEPacketStruct(
            brightnessScale: brightness,
            pulseDurationOverrideMs: pulseOverrideMs,
            useCompositeColor: useCompositeColor
        )
        sendPacket(packet, elementSymbol: element.symbol)
        return packet
    }

    public func sendPacket(_ packet: BLELightPacket, elementSymbol: String = "?") {
        lastSentPacket = packet

        guard let peripheral = connectedPeripheral,
              peripheral.state == .connected,
              let characteristic = writeCharacteristic else {
            return
        }

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse

        peripheral.writeValue(packet.data, for: characteristic, type: writeType)
        packetsSentCount += 1

        let entry = BLEPacketLogEntry(
            elementSymbol: elementSymbol,
            packet: packet,
            writeMode: writeType == .withoutResponse ? "NoResp" : "WithResp"
        )
        packetLog.insert(entry, at: 0)
        if packetLog.count > 25 {
            packetLog.removeLast(packetLog.count - 25)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLELightControllerManager: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState = central.state
        Task { @MainActor in
            self.bluetoothState = newState
            if newState != .poweredOn {
                self.writeCharacteristic = nil
                self.connectedDeviceName = nil
                if case .scanning = self.connectionState {
                    self.connectionState = .failed(self.bluetoothStateDescription)
                }
            }
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "Unnamed BLE Peripheral"
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let rssiValue = RSSI.intValue

        Task { @MainActor in
            self.peripheralsByID[id] = peripheral
            let record = DiscoveredBLEDevice(
                id: id,
                name: advertisedName,
                rssi: rssiValue,
                advertisedServiceUUIDs: serviceUUIDs,
                lastSeen: Date()
            )
            if let existingIndex = self.discoveredDevices.firstIndex(where: { $0.id == id }) {
                self.discoveredDevices[existingIndex] = record
            } else {
                self.discoveredDevices.append(record)
                self.discoveredDevices.sort { $0.rssi > $1.rssi }
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "BLE LED Controller"
        Task { @MainActor in
            self.connectedDeviceName = name
            self.connectionState = .discoveringServices(name)
            peripheral.discoverServices(nil)
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let message = error?.localizedDescription ?? "Connection failed"
        Task { @MainActor in
            self.connectedPeripheral = nil
            self.writeCharacteristic = nil
            self.connectedDeviceName = nil
            self.connectionState = .failed(message)
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let message = error?.localizedDescription
        Task { @MainActor in
            self.connectedPeripheral = nil
            self.writeCharacteristic = nil
            self.connectedDeviceName = nil
            self.activeCharacteristicUUID = nil
            self.connectionState = message.map { .failed("Disconnected: \($0)") } ?? .idle
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLELightControllerManager: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            let msg = error.localizedDescription
            Task { @MainActor in
                self.connectionState = .failed("Service discovery failed: \(msg)")
            }
            return
        }

        let services = peripheral.services ?? []
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            let msg = error.localizedDescription
            Task { @MainActor in
                self.connectionState = .failed("Characteristic discovery failed: \(msg)")
            }
            return
        }

        let characteristics = service.characteristics ?? []
        let preferred = characteristics.first { char in
            ElementBLEUUIDs.supportedWriteCharacteristics.contains(char.uuid)
        } ?? characteristics.first { char in
            char.properties.contains(.writeWithoutResponse) || char.properties.contains(.write)
        }

        guard let target = preferred else { return }
        let uuidString = target.uuid.uuidString
        let name = peripheral.name ?? "BLE LED Controller"

        Task { @MainActor in
            self.writeCharacteristic = target
            self.activeCharacteristicUUID = uuidString
            self.connectionState = .ready(name)
        }
    }
}
